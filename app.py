# File: app.py
# Action: REPLACE entire file
# Purpose: FastAPI backend for starting Twilio calls and emailing OpenAI summaries.

import os
import io
import smtplib
from email.message import EmailMessage
from typing import Optional
from urllib.parse import quote

from fastapi import FastAPI, HTTPException, Request, BackgroundTasks
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel
from twilio.rest import Client as TwilioClient
import httpx
from openai import OpenAI

# --- Configuration from environment ---

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

if not TWILIO_ACCOUNT_SID or not TWILIO_AUTH_TOKEN or not TWILIO_CALLER_ID:
    raise RuntimeError("Missing Twilio configuration in environment variables.")

if not PUBLIC_BASE_URL:
    raise RuntimeError("PUBLIC_BASE_URL must be set so Twilio can reach your webhooks.")

# --- Clients ---

twilio_client = TwilioClient(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
openai_client = OpenAI()

app = FastAPI(title="Jarvis Call Orchestrator")
 # Action: INSERT after `app = FastAPI(...)`

@app.get("/health")
async def health():
    return {"status": "ok"}

# --- Models ---

class StartCallRequest(BaseModel):
    phoneNumber: str
    instructions: str
    userEmail: Optional[str] = None


# --- Utilities ---

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
    msg["Subject"] = "Jarvis – Call Summary"
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


def process_recording_and_email(recording_url: str, call_sid: Optional[str], user_email: Optional[str]):
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

    # Extract the plain text from the responses output
    try:
        summary_text = summary_response.output[0].content[0].text
    except Exception:
        summary_text = transcript_text  # Fallback – send raw transcript

    to_email = user_email or DEFAULT_SUMMARY_EMAIL_TO
    if to_email:
        send_summary_email(summary_text, call_sid, to_email)


# --- API endpoints ---

@app.post("/calls/start")
async def start_call(payload: StartCallRequest):
    """
    Called by the iOS app via CallService.
    Starts a Twilio outbound call and sets up a recording callback.
    """
    to_number = normalize_phone_number(payload.phoneNumber)
    if not to_number:
        raise HTTPException(status_code=400, detail="Invalid phone number.")

    user_email = payload.userEmail or DEFAULT_SUMMARY_EMAIL_TO
    if not user_email:
        raise HTTPException(
            status_code=400,
            detail="No email provided and SUMMARY_EMAIL_TO is not set."
        )

    recording_callback = (
        f"{PUBLIC_BASE_URL}/twilio/recording-complete"
        f"?user_email={quote(user_email)}"
    )

    # TwiML: you can make this more sophisticated (multi-step, pauses, etc).
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
