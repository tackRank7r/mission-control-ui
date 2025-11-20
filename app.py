# File: app.py
# Action: REPLACE entire file
# Purpose: FastAPI backend for chat, starting Twilio calls, and emailing summaries.

import os
import io
import smtplib
from email.message import EmailMessage
from typing import Optional, List, Dict
from urllib.parse import quote_plus

from fastapi import FastAPI, HTTPException, Request, BackgroundTasks
from fastapi.responses import PlainTextResponse, JSONResponse
from pydantic import BaseModel
from twilio.rest import Client as TwilioClient
import httpx
from openai import OpenAI

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

TWILIO_ACCOUNT_SID = os.environ.get("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.environ.get("TWILIO_AUTH_TOKEN", "")
TWILIO_CALLER_ID = os.environ.get("TWILIO_CALLER_ID", "")
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "").rstrip("/")

SUMMARY_EMAIL_FROM = os.environ.get("SUMMARY_EMAIL_FROM", "")
DEFAULT_SUMMARY_EMAIL_TO = os.environ.get("SUMMARY_EMAIL_TO")

SMTP_HOST = os.environ.get("SMTP_HOST", "")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USERNAME = os.environ.get("SMTP_USERNAME", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")

MISSING_TWILIO = not (TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN and TWILIO_CALLER_ID)

if not PUBLIC_BASE_URL:
    raise RuntimeError("PUBLIC_BASE_URL must be set so Twilio can reach your webhooks.")

# ---------------------------------------------------------------------------
# Clients
# ---------------------------------------------------------------------------

if MISSING_TWILIO:
    twilio_client: Optional[TwilioClient] = None
else:
    twilio_client = TwilioClient(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)

openai_client = OpenAI()

app = FastAPI(title="SideKick360 Orchestrator")

# ---------------------------------------------------------------------------
# Health & metadata
# ---------------------------------------------------------------------------

@app.get("/health", response_class=PlainTextResponse)
async def health() -> str:
    """
    Simple health-check used by Render and the iOS client.
    Returns plain text 'ok' on success.
    """
    return "ok"


@app.get("/meta/phone-number")
async def meta_phone_number():
    """
    Returns the Twilio caller ID that the backend will use for outbound calls.
    The iOS “View phone number” screen can hit this.
    """
    return {"twilioCallerId": TWILIO_CALLER_ID}

# ---------------------------------------------------------------------------
# Chat / ask endpoint
# ---------------------------------------------------------------------------

class AskMessage(BaseModel):
    role: str
    content: str


class AskRequest(BaseModel):
    messages: Optional[List[AskMessage]] = None
    message: Optional[str] = None
    prompt: Optional[str] = None
    input: Optional[str] = None


def _messages_from_payload(payload: AskRequest) -> List[Dict[str, str]]:
    if payload.messages:
        return [{"role": m.role, "content": m.content} for m in payload.messages]

    # Fallbacks: single-string variants
    text = payload.message or payload.prompt or payload.input
    if not text:
        return []

    return [{"role": "user", "content": text}]


@app.post("/ask")
@app.post("/api/ask")
@app.post("/chat")
@app.post("/api/chat")
async def ask(request: Request):
    """
    Flexible chat endpoint used by the iOS APIClient.ask(...).

    It accepts several shapes (JSON with `messages`, or single-string
    `message` / `prompt` / `input`) and always returns:
        {"reply": "<assistant text>"}
    """
    try:
        raw = await request.json()
    except Exception:
        raw = {}

    payload = AskRequest(**raw)
    msgs = _messages_from_payload(payload)
    if not msgs:
        raise HTTPException(status_code=400, detail="No input provided.")

    # Very small wrapper over OpenAI Responses API.
    # We collapse the message history into a single textual prompt.
    prompt_parts = []
    for m in msgs:
        role = (m["role"] or "user").lower()
        content = m.get("content", "")
        prompt_parts.append(f"{role.upper()}: {content}")
    prompt = "\n".join(prompt_parts) + "\nASSISTANT:"

    resp = openai_client.responses.create(
        model="gpt-4.1-mini",
        input=prompt,
    )

    try:
        reply = resp.output[0].content[0].text
    except Exception:
        # As a last resort, dump the whole object.
        reply = str(resp)

    return JSONResponse({"reply": reply})

# ---------------------------------------------------------------------------
# Twilio call orchestration
# ---------------------------------------------------------------------------

class StartCallRequest(BaseModel):
    phoneNumber: str
    instructions: str
    userEmail: Optional[str] = None


def normalize_phone_number(raw: str) -> str:
    """Very simple normalization: keep digits, assume US if 10 digits."""
    digits = "".join(ch for ch in raw if ch.isdecimal() or ch == "+")
    if digits.startswith("+"):
        return digits
    if len(digits) == 10:
        return "+1" + digits
    # Fallback: just prefix + if missing
    return "+" + digits


def xml_escape(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


def send_summary_email(summary: str, call_sid: Optional[str], to_email: str):
    if not SUMMARY_EMAIL_FROM or not to_email:
        # Misconfigured; nothing we can do.
        return

    msg = EmailMessage()
    msg["Subject"] = "SideKick360 – Call Summary"
    msg["From"] = SUMMARY_EMAIL_FROM
    msg["To"] = to_email

    body_lines = []
    if call_sid:
        body_lines.append(f"Call SID: {call_sid}")
    body_lines.append("")
    body_lines.append(summary)

    msg.set_content("\n".join(body_lines))

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as smtp:
        smtp.starttls()
        if SMTP_USERNAME and SMTP_PASSWORD:
            smtp.login(SMTP_USERNAME, SMTP_PASSWORD)
        smtp.send_message(msg)


def process_recording_and_email(
    recording_url: str,
    call_sid: Optional[str],
    user_email: Optional[str],
):
    """Background task: download audio, transcribe with OpenAI, summarize, email."""
    # Twilio RecordingUrl usually needs an extension (e.g. .mp3) to fetch audio.
    audio_url = recording_url + ".mp3"

    with httpx.Client(timeout=60.0) as client:
        resp = client.get(audio_url)
        resp.raise_for_status()
        audio_bytes = resp.content

    audio_file = io.BytesIO(audio_bytes)
    audio_file.name = "call.mp3"

    # 1) Transcribe the call audio
    transcription = openai_client.audio.transcriptions.create(
        model="gpt-4o-transcribe",
        file=audio_file,
    )
    transcript_text = transcription.text

    # 2) Summarize as an email
    summary_response = openai_client.responses.create(
        model="gpt-4.1-mini",
        input=(
            "Summarize this phone call as a short, clear email to the user. "
            "Include key decisions, dates/times, and any follow-up actions.\n\n"
            f"Transcript:\n{transcript_text}"
        ),
    )

    try:
        summary_text = summary_response.output[0].content[0].text
    except Exception:
        summary_text = transcript_text  # Fallback – send raw transcript

    to_email = user_email or DEFAULT_SUMMARY_EMAIL_TO
    if to_email:
        send_summary_email(summary_text, call_sid, to_email)


@app.post("/calls/start")
async def start_call(payload: StartCallRequest):
    """
    Called by the iOS app via CallService.
    Starts a Twilio outbound call and sets up a recording callback.
    """
    if twilio_client is None:
        raise HTTPException(
            status_code=500,
            detail="Twilio is not configured on the server (check env vars).",
        )

    to_number = normalize_phone_number(payload.phoneNumber)
    if not to_number:
        raise HTTPException(status_code=400, detail="Invalid phone number.")

    user_email = payload.userEmail or DEFAULT_SUMMARY_EMAIL_TO
    if not user_email:
        raise HTTPException(
            status_code=400,
            detail="No email provided and SUMMARY_EMAIL_TO is not set.",
        )

    recording_callback = (
        f"{PUBLIC_BASE_URL}/twilio/recording-complete"
        f"?user_email={quote_plus(user_email)}"
    )

    safe_instructions = xml_escape(payload.instructions)
    twiml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Say voice="Polly.Joanna">
        You are receiving a call on behalf of the user from an AI assistant.
        This call may be recorded to create a summary for them.
    </Say>
    <Pause length="1"/>
    <Say voice="Polly.Joanna">{safe_instructions}</Say>
</Response>"""

    call = twilio_client.calls.create(
        to=to_number,
        from_=TWILIO_CALLER_ID,
        twiml=twiml,
        record=True,
        recording_status_callback=recording_callback,
        recording_status_callback_event=["completed"],
    )

    return {"status": "started", "callSid": call.sid}


@app.post("/twilio/recording-complete")
async def recording_complete(request: Request, background_tasks: BackgroundTasks):
    """
    Twilio hits this when the call recording is complete.
    We schedule a background task to fetch the audio, transcribe, summarize, and email.
    """
    form = await request.form()

    recording_url = form.get("RecordingUrl")
    call_sid = form.get("CallSid")
    user_email = request.query_params.get("user_email")

    if not recording_url:
        raise HTTPException(status_code=400, detail="Missing RecordingUrl from Twilio.")

    background_tasks.add_task(
        process_recording_and_email,
        recording_url,
        call_sid,
        user_email,
    )

    # Twilio only cares that we respond 200 OK with some body.
    return PlainTextResponse("OK")
