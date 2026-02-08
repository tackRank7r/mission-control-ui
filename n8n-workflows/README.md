# Jarvis n8n Workflows

This directory contains n8n workflow JSON files for the Jarvis agentic calling system.

## Workflows

### 1. Call Scheduler (`call-scheduler.json`)
Polls the backend every 30 seconds for pending calls and initiates them via Twilio.

**Trigger:** Schedule (every 30 seconds)
**Flow:**
1. Fetch pending calls from `/n8n/pending-calls`
2. For each call, mark as started via `/n8n/call/{id}/start`
3. Initiate Twilio call
4. Update call with Twilio SID or log error

### 2. Twilio Voice Handler (`twilio-voice-handler.json`)
Handles initial Twilio voice webhook when a call connects.

**Trigger:** Webhook POST `/twilio-voice`
**Flow:**
1. Look up call task by Twilio CallSid
2. Return TwiML with initial greeting

### 3. Voice Conversation Turn (`twilio-voice-respond.json`)
Handles speech input during calls and generates AI responses.

**Trigger:** Webhook POST `/voice-respond`
**Flow:**
1. Look up call task
2. Process conversation turn via backend
3. Return TwiML for next response or call end

### 4. Twilio Status Callback (`twilio-status-callback.json`)
Handles Twilio status updates (answered, completed, failed, etc.)

**Trigger:** Webhook POST `/twilio-status`
**Flow:**
1. Look up call task
2. If call completed, trigger post-call summary
3. Log status updates

### 5. Post-Call Summary (`post-call-summary.json`)
Generates AI summary of completed calls.

**Trigger:** Webhook POST `/call-completed`
**Flow:**
1. Fetch call details including transcript
2. Generate AI summary using OpenAI
3. Save summary to backend

### 6. Error Logger (`error-logger.json`)
Centralized error logging with optional email alerts.

**Trigger:** Webhook POST `/log-error`
**Flow:**
1. Log error to backend
2. If critical, send alert email

---

## Setup Instructions

### 1. Environment Variables (n8n)

In n8n Cloud: **Menu (☰) → Settings → Variables → + Add Variable**

| Variable | Value |
|----------|-------|
| `JARVIS_BACKEND_URL` | `https://YOUR-BACKEND.onrender.com` |
| `N8N_WEBHOOK_URL` | `https://YOUR-N8N-INSTANCE.app.n8n.cloud/webhook` |
| `TWILIO_FROM_NUMBER` | `+1XXXXXXXXXX` |
| `ADMIN_EMAIL` | `admin@example.com` |

### 2. Credentials (n8n)

Create these credentials in n8n:

**Jarvis Backend Auth (HTTP Header Auth)**
- Header Name: `Authorization`
- Header Value: `Bearer YOUR_APP_BACKEND_BEARER`

**Twilio API**
- Account SID: Your Twilio Account SID
- Auth Token: Your Twilio Auth Token

**OpenAI API**
- API Key: Your OpenAI API key

**SMTP Credentials** (for error alerts)
- Configure with your email provider

### 3. Import Workflows

1. Go to n8n → Workflows
2. Click "Import from File"
3. Select each JSON file
4. Activate the workflows

### 4. Configure Twilio

In your Twilio Console, set these webhook URLs:

**Voice URL (when call answers):**
```
https://YOUR-N8N-INSTANCE.app.n8n.cloud/webhook/twilio-voice
```

**Status Callback URL:**
```
https://YOUR-N8N-INSTANCE.app.n8n.cloud/webhook/twilio-status
```

### 5. Backend Environment Variables

Ensure your Flask backend has these set:

```
APP_BACKEND_BEARER=your-secret-token
OPENAI_API_KEY=sk-...
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_FROM_NUMBER=+1234567890
N8N_BASE_URL=https://YOUR-N8N-INSTANCE.app.n8n.cloud
```

---

## Workflow Diagram

```
[iOS App] --> [Flask Backend] --> [n8n Call Scheduler]
                                         |
                                         v
                                   [Twilio API]
                                         |
                                         v
                               [Twilio Voice Handler]
                                         |
                                         v
                              [Voice Conversation Turn]
                                         |
                                    (loop until done)
                                         |
                                         v
                               [Twilio Status Callback]
                                         |
                                         v
                               [Post-Call Summary]
                                         |
                                         v
                               [Flask Backend]
                                         |
                                         v
                                   [iOS App]
```

---

## Testing

### Test Call Scheduling
```bash
curl -X POST https://YOUR-BACKEND.onrender.com/call/schedule \
  -H "Authorization: Bearer YOUR_APP_BACKEND_BEARER" \
  -H "Content-Type: application/json" \
  -d '{
    "target_phone": "+1234567890",
    "target_name": "Test Restaurant",
    "objective": "reservation",
    "context": {"party_size": 2, "preferred_time": "7pm"}
  }'
```

### Test Error Logging
```bash
curl -X POST https://YOUR-N8N-INSTANCE.app.n8n.cloud/webhook/log-error \
  -H "Content-Type: application/json" \
  -d '{
    "workflow": "test",
    "node": "test-node",
    "level": "error",
    "message": "Test error message",
    "severity": "normal"
  }'
```

### Check Logs
```bash
curl https://YOUR-BACKEND.onrender.com/n8n/logs \
  -H "Authorization: Bearer YOUR_APP_BACKEND_BEARER"
```

---

## Troubleshooting

### Calls not starting
1. Check n8n execution logs for errors
2. Verify Twilio credentials are correct
3. Check `/n8n/pending-calls` returns scheduled calls
4. Ensure `TWILIO_FROM_NUMBER` is set

### No audio/TwiML errors
1. Check Flask logs for TwiML generation errors
2. Verify the voice webhook URL is accessible
3. Test TwiML response manually

### Summary not generating
1. Check OpenAI API key is valid
2. Verify transcript is being recorded
3. Check post-call-summary workflow logs

### Errors not logging
1. Verify backend `/n8n/log` endpoint is accessible
2. Check error-logger workflow is active
