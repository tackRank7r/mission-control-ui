# Runbook & Deployment Audit — 2026-02-15

## Scope of review
- `RUNBOOK.md`
- `docs/schedule-call-spec.md`
- `README.md` (root)
- `second-brain/README.md`
- Mission Control content sources (`second-brain/content/*`)
- `progress.md`

## Findings

### 1. `RUNBOOK.md`
- **Stale last-updated timestamp (Jan 31)** — predates all hotline polish + OTP scheduling specs delivered Feb 11.
- **No mention of OTP endpoints (`/auth/request-code`, `/auth/verify-code`)** or the new email-verification gate required before `/call/schedule` executes.
- **Hotline coverage stops at basic Twilio fallback** — does not capture Whisper transcription helper, OpenAI TTS path, or verification steps (how to smoke-test hotline end-to-end, what signals to watch in logs, and how to reset sessions).
- **Mission Control / second-brain not referenced** — current runbook does not mention where hotline transcripts or call summaries land inside the new dashboard, nor how ops should use it daily.
- **Deployment guidance limited to Flask + Render** — nothing about deploying/rolling back the Next.js Mission Control app or coordinating secrets (SendGrid, OTP salt, allowed email list) between backend + dashboard.
- **Call scheduling flow** — still describes legacy flow (no contact picker metadata, tone, requester email, summary emails). Needs update aligning with the Feb 11 spec (contact.email, tone, agent name, metadata entry point, summary send).
- **Environment variable table** missing: SendGrid, OTP salts, Mission Control envs, new hotline-specific flags.

### 2. `README.md`
- Placeholder content (`# CGPTPROJECT`) offers no quickstart or linkage to RUNBOOK or new components. Needs at least: project overview, subdirectories (Flask backend, iOS, second-brain Mission Control), and pointers to the runbook sections for backend + dashboard deployments.

### 3. `docs/schedule-call-spec.md`
- Contains the authoritative description of OTP/email verification, tone controls, and summary email logic, but this remains siloed. RUNBOOK and root README should ingest the key operational steps instead of forcing readers to dig into this spec.

### 4. `second-brain/README.md`
- Solid technical deployment guide (Node/Next.js/SendGrid), but **missing operational workflow** describing how Mission Control is supposed to be used daily (scratchpad intake → triage → promote to `MEMORY.md`, how to review hotline transcripts, where OTP/verification alerts surface).
- No instructions for syncing hotline call summaries or verifying that `/api/conversations/sync` is healthy after deploys.

### 5. Mission Control content (`second-brain/content/*`)
- Provides sample notes/memory, but there is **no documented daily workflow** that explains:
  - Morning/afternoon cadence for writing scratchpad notes.
  - When/how to promote items into `MEMORY.md` vs. daily note files.
  - How to log hotline verifications, OTP issues, or deployment status inside Mission Control.

### 6. `progress.md`
- References work on hotline webhook + Mission Control but does not link to updated procedures. Could be cited inside RUNBOOK as the change log entry for Feb 11 deliverables.

## Sections to update / add

| Doc | Section(s) to revise | Notes |
| --- | --- | --- |
| `RUNBOOK.md` | Overview / Architecture | Highlight hotline stack (Whisper transcription, OpenAI TTS fallback) + note Mission Control integration.
|  | Backend Endpoints | Add OTP endpoints + new `/call/schedule` fields/requirements.
|  | Direct Hotline Runbook | Expand to include verification steps (ngrok → test call → check Whisper + OpenAI logs), session reset guidance, and monitoring signals.
|  | Environment Variables | Add SendGrid + OTP secrets + Mission Control-related envs.
|  | Deployment | Split into Flask (Render) + Mission Control (Next.js/Vercel) with coordinated steps.
|  | Monitoring / Troubleshooting | Add OTP failure modes, SendGrid email issues, Mission Control sync health checks.
|  | New section: "Mission Control Daily Workflow" | Describe scratchpad → decision log → `MEMORY.md` promotion, hotline summary review cadence.
| `README.md` | Entire file | Provide high-level map + link to runbook, mention hotline + Mission Control components.
| `docs/schedule-call-spec.md` | (Optional) Append "Runbook parity" blurb | Cross-link to RUNBOOK once updated so spec readers know ops instructions live elsewhere.
| `second-brain/README.md` | Add "Daily Ops Workflow" + "Hotline Transcript Verification" sections | Explain scratchpad use, OTP monitoring, and how Mission Control ties into backend deployments.
| Mission Control content (`content/docs/*` or new `MISSION_CONTROL_WORKFLOW.md`) | New canonical daily workflow doc | Should walk through: (1) morning scratchpad capture, (2) tagging decisions, (3) promoting to `memory/YYYY-MM-DD.md` & `LONG_TERM_MEMORY.md`, (4) documenting hotline verifications & OTP alerts.
| `RUNBOOK.md` / `progress.md` | Version history entry | Record Feb 15 change once updates land.

Delivering this audit first positions us to update the runbook + related docs as soon as the hotline + OTP work merges.
