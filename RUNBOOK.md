# SideKick360 / Jarvis - Technical Runbook

## Overview

SideKick360 (Jarvis) is an AI-powered personal assistant with:
- iOS native app for chat and voice interaction
- Flask backend hosted on Render
- n8n workflow automation for agentic phone calls
- Twilio integration for outbound calling
- ElevenLabs TTS for natural voice synthesis

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   iOS App       │────▶│  Flask Backend   │────▶│    OpenAI       │
│  (SwiftUI)      │     │   (Render)       │     │   GPT-4         │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │      n8n         │
                        │  (Workflows)     │
                        └──────────────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
       ┌──────────┐     ┌──────────┐     ┌──────────┐
       │  Twilio  │     │ElevenLabs│     │  Polly   │
       │  Voice   │     │   TTS    │     │   TTS    │
       └──────────┘     └──────────┘     └──────────┘
```

---

## Project Structure

```
CGPTPROJECT/
├── app.py                    # Main Flask backend (all endpoints)
├── requirements.txt          # Python dependencies
├── render.yaml               # Render deployment config
├── Procfile                  # Gunicorn start command
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
All endpoints require `Authorization: Bearer <APP_BACKEND_BEARER>` header.

### Core Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check (used by UptimeRobot) |
| `/diagnostics` | GET | System diagnostics |
| `/ask` | POST | Main AI chat endpoint |
| `/api/chat` | POST | Legacy chat endpoint |
| `/speak` | POST | TTS endpoint (returns audio/mpeg) |
| `/history` | GET | Get chat session history |

### Call Management

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/call/schedule` | POST | Schedule a new outbound call |
| `/n8n/pending-calls` | GET | Get calls ready to execute |
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

### Twilio (for phone calls)

```bash
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_FROM_NUMBER=+1234567890
```

### TTS Options

```bash
# ElevenLabs (recommended - most natural)
ELEVENLABS_API_KEY=...
ELEVENLABS_VOICE_ID=21m00Tcm4TlvDq8ikWAM  # Rachel (default)

# AWS Polly (fallback)
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
POLLY_VOICE=Matthew
```

---

## n8n Workflows

### Call Scheduler (Primary)
- **Trigger:** Every 30 seconds
- **Flow:** Poll `/n8n/pending-calls` → Split items → Mark started → Initiate Twilio call → Update call SID
- **n8n URL:** https://fdaf.app.n8n.cloud

### Configuration Required in n8n

1. **Variables:**
   - `JARVIS_BACKEND_URL` = `https://cgptproject-v2.onrender.com`
   - `TWILIO_FROM_NUMBER` = `+12568604020`

2. **Credentials:**
   - Twilio API (Account SID + Auth Token)
   - Header Auth for backend (Bearer token)

---

## Phone Call Flow

```
1. iOS App/API → POST /call/schedule
                    ↓
2. CallTask created (status: "scheduled")
                    ↓
3. n8n polls /n8n/pending-calls every 30s
                    ↓
4. n8n initiates Twilio call with TwiML redirect
                    ↓
5. Twilio calls target phone
                    ↓
6. On answer → Twilio requests /twilio/voice
                    ↓
7. Backend returns TwiML with greeting (ElevenLabs audio)
                    ↓
8. Speech recognition captures response
                    ↓
9. /twilio/voice/respond generates AI response
                    ↓
10. Loop until conversation ends
                    ↓
11. Call marked complete, summary generated
```

---

## TTS Priority Chain

1. **ElevenLabs** (if `ELEVENLABS_API_KEY` set) - Most natural
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
- **Twilio Debugger:** Monitor → Logs → Errors
- **n8n Executions:** Check workflow run history
- **Render Logs:** Dashboard → Logs

---

## ElevenLabs Agents: Alternative Architecture

### Current Approach: Custom Stack
```
iOS App → Flask Backend → n8n → Twilio → Custom TwiML → ElevenLabs TTS
```

### Alternative: ElevenLabs Agents Platform
```
iOS App → Flask Backend → ElevenLabs Conversational AI (handles everything)
```

---

## Comparison: Current Stack vs ElevenLabs Agents

### Option A: Current Custom Stack (n8n + Twilio + ElevenLabs TTS)

| Pros | Cons |
|------|------|
| **Full control** - Complete customization of conversation flow, prompts, and logic | **Complex setup** - Multiple services to configure and maintain |
| **Flexible integration** - Can integrate with any service via n8n workflows | **Latency** - Multiple hops (n8n → Twilio → Backend → TTS) add delay |
| **Cost transparency** - Pay separately for each service, optimize individually | **Debugging difficulty** - Issues can occur at any point in the chain |

**Best for:** Complex workflows, custom business logic, integration with many external services

---

### Option B: ElevenLabs Conversational AI Agents

| Pros | Cons |
|------|------|
| **Seamless voice** - Ultra-low latency, natural conversation flow | **Less control** - Limited customization of conversation logic |
| **Simpler architecture** - One platform handles voice, AI, and phone | **Vendor lock-in** - Dependent on ElevenLabs platform |
| **Built-in phone numbers** - No separate Twilio setup needed | **Cost** - May be more expensive at scale than DIY approach |

**Best for:** Simple call flows, rapid prototyping, voice-first experiences

---

### Hybrid Approach (Recommended)

Use **both** based on call type:

| Call Type | Recommended Stack |
|-----------|-------------------|
| Simple info calls (appointments, reservations) | ElevenLabs Agents |
| Complex multi-step workflows | Current n8n + Twilio stack |
| Calls requiring external API integration | Current n8n + Twilio stack |

**Implementation:**
1. Add `call_type` field to CallTask model
2. Route simple calls to ElevenLabs Agents API
3. Route complex calls through n8n/Twilio

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
- **Cause:** Workflow not active
- **Fix:** Toggle workflow "Active" in n8n

---

## Quick Reference

### Schedule a Test Call
```bash
curl -X POST "https://cgptproject-v2.onrender.com/call/schedule" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"target_phone":"+1XXXXXXXXXX","target_name":"Test","objective":"test"}'
```

### Check Pending Calls
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
| 2026-01-27 | Added ElevenLabs TTS integration |
| 2026-01-27 | Fixed Twilio TwiML configuration |
| 2026-01-26 | Deployed n8n workflow integration |
| 2026-01-25 | Initial Flask backend with call scheduling |

---

*Last updated: January 27, 2026*
