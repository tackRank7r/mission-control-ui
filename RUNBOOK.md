# SideKick360 / Jarvis - Technical Runbook

## Overview

SideKick360 (Jarvis) is an AI-powered personal assistant with:
- iOS native app for chat and voice interaction
- Flask backend hosted on Render
- **Hybrid call routing**: ElevenLabs Conversational AI Agents (preferred) with Twilio/n8n fallback
- Usage-based routing with weekly cost and call limits
- ElevenLabs TTS for natural voice synthesis

---

## Architecture

### Hybrid Call Routing (Active)

```
                         POST /call/schedule
                                │
                    ┌───────────┴───────────┐
                    │  Routing Decision      │
                    │  _should_use_agent()   │
                    └───────────┬───────────┘
                          ┌─────┴─────┐
                          │           │
                    ┌─────▼─────┐ ┌───▼────────────┐
                    │ PREMIUM   │ │ BUDGET          │
                    │ ElevenLabs│ │ Twilio Custom   │
                    │ Agents API│ │ (n8n + TwiML)   │
                    └─────┬─────┘ └───┬────────────┘
                          │           │
                    ElevenLabs    n8n polls
                    handles      /n8n/pending-calls
                    everything   → Twilio → TwiML
                                 → GPT-4o-mini
                                 → ElevenLabs TTS
```

### Routing Rules

| Condition | Route |
|-----------|-------|
| Admin user | Always ElevenLabs Agents |
| Weekly cost < $20 AND user calls < 4/week | ElevenLabs Agents |
| Weekly cost >= $20 | Twilio custom (all users) |
| User calls >= 4/week | Twilio custom (that user) |
| ElevenLabs Agent API fails | Auto-fallback to Twilio custom |
| `ELEVENLABS_AGENT_ID` not set | Twilio custom (all calls) |

### Full System Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   iOS App       │────▶│  Flask Backend   │────▶│    OpenAI       │
│  (SwiftUI)      │     │   (Render)       │     │   GPT-4o-mini   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                 ┌─────────────┼─────────────┐
                 ▼                           ▼
          ┌──────────────┐            ┌──────────────┐
          │  ElevenLabs  │            │     n8n      │
          │  Agents API  │            │  (Workflows) │
          │  (preferred) │            │  (fallback)  │
          └──────────────┘            └──────────────┘
                                           │
                            ┌──────────────┼──────────────┐
                            ▼              ▼              ▼
                     ┌──────────┐   ┌──────────┐   ┌──────────┐
                     │  Twilio  │   │ElevenLabs│   │  Polly   │
                     │  Voice   │   │   TTS    │   │   TTS    │
                     └──────────┘   └──────────┘   └──────────┘
```

---

## Project Structure

```
CGPTPROJECT/
├── app.py                    # Main Flask backend (all endpoints)
├── requirements.txt          # Python dependencies
├── render.yaml               # Render deployment config
├── Procfile                  # Gunicorn start command
├── RUNBOOK.md                # This file
├── n8n-workflows/            # n8n workflow JSON files
│   ├── call-scheduler.json
│   ├── twilio-voice-handler.json
│   ├── twilio-voice-respond.json
│   ├── twilio-status-callback.json
│   ├── post-call-summary.json
│   ├── error-logger.json
│   └── README.md
└── ios/
    └── JarvisClient/         # iOS Xcode project
        └── JarvisClient/
            ├── JarvisClientApp.swift
            ├── RootShellView.swift
            ├── ChatViewModel.swift
            ├── VoiceChatManager.swift
            ├── CallService.swift
            ├── APIClient.swift
            └── Secrets.swift
```

---

## Backend Endpoints (app.py)

### Authentication
All endpoints require `Authorization: Bearer <APP_BACKEND_BEARER>` header (except `/health`, `/n8n/*`, `/twilio/*`).

### Core Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (used by UptimeRobot) |
| `/diagnostics` | GET | System diagnostics |
| `/ask` | POST | Main AI chat endpoint |
| `/api/chat` | POST | Legacy chat endpoint |
| `/speak` | POST | TTS endpoint (returns audio/mpeg) |
| `/history` | GET | Get chat session history |
| `/usage` | GET | **Weekly usage stats and routing status** |

### Call Management

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/call/schedule` | POST | Schedule a new outbound call **(routes via hybrid logic)** |
| `/call/<id>` | GET | Get call details and status |
| `/call/<id>/cancel` | POST | Cancel a scheduled call |
| `/call/<id>/events` | GET | Get audit trail for a call |
| `/calls` | GET | List user's calls |
| `/n8n/pending-calls` | GET | Get calls ready for n8n (Twilio custom only) |
| `/n8n/call/<id>/start` | POST | Mark call as started |
| `/n8n/call/<id>/turn` | POST | Log conversation turn |
| `/n8n/call/<id>/complete` | POST | Mark call completed |
| `/n8n/call/<id>/error` | POST | Mark call failed |
| `/n8n/call/lookup` | GET | Look up call by Twilio SID |

### Twilio Webhooks

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/twilio/voice` | POST | Initial call webhook (returns TwiML) |
| `/twilio/voice/respond` | POST | Conversation turn webhook |
| `/twilio/status` | POST | Call status callback |
| `/audio/<cache_key>` | GET | Serve ElevenLabs audio |

---

## Environment Variables

### Required (Render)

```bash
APP_BACKEND_BEARER=your_secret_token
OPENAI_API_KEY=sk-...
DATABASE_URL=postgresql://...  # Auto-set by Render
```

### ElevenLabs Conversational AI Agents (hybrid routing)

```bash
ELEVENLABS_API_KEY=sk_...
ELEVENLABS_VOICE_ID=lAxf5ma5HGtzxC434SWT   # Tori
ELEVENLABS_AGENT_ID=your_agent_id           # From ElevenLabs dashboard
ELEVENLABS_PHONE_NUMBER_ID=your_phone_id    # From ElevenLabs dashboard
```

### Twilio (for fallback phone calls)

```bash
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_FROM_NUMBER=+12568604020
```

### TTS Fallbacks

```bash
# AWS Polly (fallback)
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
POLLY_VOICE=Matthew
```

---

## Hybrid Routing System

### How It Works

When `/call/schedule` is called:

1. `_should_use_elevenlabs_agent(user_id)` checks:
   - Is `ELEVENLABS_AGENT_ID` configured? If not → Twilio custom
   - Is the user an admin (`is_admin=True`)? If yes → always ElevenLabs Agents
   - Is weekly total cost < $20 (2000 cents)? If no → Twilio custom
   - Has the user made < 4 calls this week? If no → Twilio custom
   - Otherwise → ElevenLabs Agents

2. **ElevenLabs Agents route:**
   - Calls `POST https://api.elevenlabs.io/v1/convai/twilio/outbound-call`
   - ElevenLabs handles the entire conversation (AI, voice, phone)
   - Call status set to `"in_progress"` immediately
   - If the API call fails → auto-fallback to Twilio custom

3. **Twilio custom route:**
   - Call status stays `"scheduled"`
   - n8n polls `/n8n/pending-calls` every 30 seconds
   - n8n initiates Twilio call → TwiML → GPT-4o-mini + ElevenLabs TTS

### Cost Tracking

| Route | Cost per minute |
|-------|----------------|
| ElevenLabs Agents | $0.10/min (10 cents) |
| Twilio custom | $0.02/min (2 cents) |

Costs are calculated when calls complete and stored in `CallTask.cost_cents`.

### Limits (configurable in app.py)

```python
WEEKLY_COST_LIMIT_CENTS = 2000   # $20/week
WEEKLY_CALLS_PER_USER = 4        # 4 calls/week per user
```

Week resets every Monday 00:00 UTC.

### Database Fields

**User model:**
- `is_admin` (Boolean) — admin users bypass all limits

**CallTask model:**
- `routing_type` — `"elevenlabs_agent"` or `"twilio_custom"`
- `cost_cents` — calculated based on routing_type rate

---

## Phone Call Flows

### Flow A: ElevenLabs Agents (preferred)

```
1. iOS App/API → POST /call/schedule
                    ↓
2. _should_use_elevenlabs_agent() → True
                    ↓
3. POST to ElevenLabs Agents API (outbound-call)
                    ↓
4. ElevenLabs handles entire call
   (AI conversation, voice synthesis, phone connection)
                    ↓
5. Call completed → cost tracked at $0.10/min
```

### Flow B: Twilio Custom (fallback)

```
1. iOS App/API → POST /call/schedule
                    ↓
2. _should_use_elevenlabs_agent() → False (over limits)
                    ↓
3. CallTask created (status: "scheduled", routing_type: "twilio_custom")
                    ↓
4. n8n polls /n8n/pending-calls every 30s
                    ↓
5. n8n initiates Twilio call with TwiML redirect
                    ↓
6. Twilio calls target phone
                    ↓
7. On answer → Twilio requests /twilio/voice
                    ↓
8. Backend returns TwiML with greeting (ElevenLabs TTS audio)
                    ↓
9. Speech recognition captures response
                    ↓
10. /twilio/voice/respond → GPT-4o-mini → ElevenLabs TTS
                    ↓
11. Loop until conversation ends
                    ↓
12. Call marked complete → cost tracked at $0.02/min
```

---

## n8n Workflows

### Call Scheduler (Primary — Twilio custom calls only)
- **Trigger:** Every 30 seconds
- **Flow:** Poll `/n8n/pending-calls` → Split items → Mark started → Initiate Twilio call → Update call SID
- **n8n URL:** https://fdaf.app.n8n.cloud
- **Note:** Only picks up calls with `routing_type: "twilio_custom"` (those not routed to ElevenLabs Agents)

### Configuration Required in n8n

1. **Variables:**
   - `JARVIS_BACKEND_URL` = `https://cgptproject-v2.onrender.com`
   - `TWILIO_FROM_NUMBER` = `+12568604020`

2. **Credentials:**
   - Twilio API (Account SID + Auth Token)
   - Header Auth for backend (Bearer token)

---

## TTS Priority Chain (for Twilio custom calls)

1. **ElevenLabs** (if `ELEVENLABS_API_KEY` set) - Most natural, uses Tori voice
2. **AWS Polly** (if AWS credentials set) - Good quality
3. **OpenAI TTS** (if `OPENAI_API_KEY` set) - Fallback

---

## Deployment

### Render
- Auto-deploys on push to `main` branch
- Free tier sleeps after 15 min inactivity
- UptimeRobot pings `/health` every 5 min to keep warm

### Manual Deploy
```bash
git add . && git commit -m "message" && git push origin main
```

---

## Monitoring

- **UptimeRobot:** Pings `/health` every 5 minutes
- **Usage endpoint:** `GET /usage` shows weekly cost, call counts, and current routing mode
- **Twilio Debugger:** Monitor → Logs → Errors
- **n8n Executions:** Check workflow run history
- **Render Logs:** Dashboard → Logs

---

## Setting Up ElevenLabs Agents (Prerequisites)

1. Go to [ElevenLabs dashboard](https://elevenlabs.io) → Conversational AI → Create Agent
2. Configure the agent with Tori's voice and personality
3. Connect your Twilio phone number (+12568604020) under the agent's phone settings
4. Copy the **Agent ID** and **Phone Number ID**
5. Set env vars on Render:
   - `ELEVENLABS_AGENT_ID` = your agent ID
   - `ELEVENLABS_PHONE_NUMBER_ID` = your phone number ID

---

## Troubleshooting

### "Application error has occurred" on call
- **Cause:** Render server sleeping (cold start timeout)
- **Fix:** Ensure UptimeRobot is pinging `/health`

### "12100 - Document parse failure" in Twilio
- **Cause:** Invalid TwiML returned
- **Fix:** Use `<Response><Redirect>URL</Redirect></Response>` format

### n8n "Bad request - please check parameters"
- **Cause:** Invalid phone number or missing fields
- **Fix:** Check phone format (+1XXXXXXXXXX), verify all fields populated

### Calls not being picked up by n8n
- **Cause:** Workflow not active, or calls routed to ElevenLabs Agents
- **Fix:** Toggle workflow "Active" in n8n; check `/usage` endpoint to see routing mode

### ElevenLabs Agent call fails with 401
- **Cause:** Invalid or expired API key
- **Fix:** Regenerate key at elevenlabs.io, update `ELEVENLABS_API_KEY` in Render

### All calls routing to Twilio custom
- **Cause:** `ELEVENLABS_AGENT_ID` or `ELEVENLABS_PHONE_NUMBER_ID` not set
- **Fix:** Set both env vars on Render (see Setup section)

### Calls routing to Twilio unexpectedly
- **Cause:** Weekly cost limit ($20) or per-user call limit (4/week) reached
- **Fix:** Check `GET /usage` endpoint; admin users bypass limits

---

## Quick Reference

### Schedule a Test Call
```bash
curl -X POST "https://cgptproject-v2.onrender.com/call/schedule" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"target_phone":"+1XXXXXXXXXX","target_name":"Test","objective":"test"}'
```
Response includes `routing_type` showing which stack handled the call.

### Check Usage / Routing Status
```bash
curl "https://cgptproject-v2.onrender.com/usage" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Check Pending Calls (Twilio custom only)
```bash
curl https://cgptproject-v2.onrender.com/n8n/pending-calls
```

### Clear a Failed Call
```bash
curl -X POST "https://cgptproject-v2.onrender.com/n8n/call/CALL_ID/error" \
  -H "Content-Type: application/json" \
  -d '{"error":"Manual clear"}'
```

### Test Health
```bash
curl https://cgptproject-v2.onrender.com/health
```

---

## Key URLs

| Service | URL |
|---------|-----|
| Backend | https://cgptproject-v2.onrender.com |
| n8n | https://fdaf.app.n8n.cloud |
| Render Dashboard | https://dashboard.render.com |
| Twilio Console | https://console.twilio.com |
| ElevenLabs | https://elevenlabs.io |

---

## Version History

| Date | Change |
|------|--------|
| 2026-01-28 | **Hybrid routing**: ElevenLabs Agents preferred, Twilio fallback with $20/week and 4 calls/week limits |
| 2026-01-28 | Added `is_admin` to User, `routing_type` to CallTask, `/usage` endpoint |
| 2026-01-27 | Added ElevenLabs TTS integration |
| 2026-01-27 | Fixed Twilio TwiML configuration |
| 2026-01-26 | Deployed n8n workflow integration |
| 2026-01-25 | Initial Flask backend with call scheduling |

---

*Last updated: January 28, 2026*
