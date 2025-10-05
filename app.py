import os
import re
import json
import logging
from datetime import datetime
from flask import Flask, request, make_response
from dotenv import load_dotenv
from openai import OpenAI
from twilio.twiml.voice_response import VoiceResponse, Gather
from twilio.request_validator import RequestValidator
from twilio.rest import Client as TwilioClient


# --- 1) TOP OF app.py: add imports and env helpers (keep your existing imports) ---
try:
    from flask_sock import Sock
except ImportError:
    # If not installed yet, add it to requirements.txt and redeploy
    raise

# Reuse your existing bearer env var if you already have one.
APP_BACKEND_BEARER = os.getenv("APP_BACKEND_BEARER", "")

def _authorized(hdr: str | None) -> bool:
    # If no bearer configured on server, allow; else exact match "Bearer <token>"
    if not APP_BACKEND_BEARER:
        return True
    return hdr == f"Bearer {APP_BACKEND_BEARER}"

# --- 2) AFTER you create your Flask app object ---
# Example: app = Flask(__name__)
sock = Sock(app)  # add alongside your existing app

# --- 3) ADD the WebSocket endpoint (echo stub). Keep your existing routes untouched. ---
@sock.route("/voice")
def ws_voice(ws):
    # The Authorization header is in the HTTP handshake headers:
    auth = request.headers.get("Authorization", "")
    if not _authorized(auth):
        # Close with a small message; client will show an error.
        ws.send(json.dumps({"type": "error", "error": "invalid_bearer"}))
        ws.close()
        return

    # Let the iOS client know we’re live
    ws.send(json.dumps({"type": "partial", "text": "Connected. Send PCM16k mono frames."}))

    # Simple loop: echo counts for binary audio frames; echo text for JSON/control frames
    while True:
        msg = ws.receive()  # None on close
        if msg is None:
            break
        if isinstance(msg, (bytes, bytearray)):
            ws.send(json.dumps({"type": "final", "text": f"received {len(msg)} bytes"}))
        else:
            # If the client sends JSON as text, keep it simple and reflect it
            ws.send(json.dumps({"type": "final", "text": f"text: {msg}"}))



# ---------- Optional email: Twilio SendGrid ----------
try:
    from sendgrid import SendGridAPIClient
    from sendgrid.helpers.mail import Mail
    SENDGRID_AVAILABLE = True
except Exception:
    SENDGRID_AVAILABLE = False

# ---------- Load .env FIRST (Render uses env vars) ----------
load_dotenv()

# ---------- Secrets / Config ----------
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

# Twilio creds (signature validation + outbound calls)
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN  = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_NUMBER      = os.getenv("TWILIO_NUMBER", "")

# For temporary testing without Twilio signature validation, set to "true"
SKIP_TWILIO_VALIDATION = os.getenv("SKIP_TWILIO_VALIDATION", "false").lower() == "true"

# Securing your JSON APIs (/ask, /call)
API_TOKEN = os.getenv("API_TOKEN", "")

# Email notifications (fallbacks)
SENDGRID_API_KEY   = os.getenv("SENDGRID_API_KEY", "")
ADMIN_EMAIL_FROM   = os.getenv("ADMIN_EMAIL_FROM", "")
ADMIN_EMAIL_TO     = os.getenv("ADMIN_EMAIL_TO", "")
ENABLE_EMAIL       = bool(SENDGRID_API_KEY and ADMIN_EMAIL_FROM and ADMIN_EMAIL_TO and SENDGRID_AVAILABLE)

# Fallback heuristics
MAX_TURNS_PER_CALL = int(os.getenv("MAX_TURNS_PER_CALL", "10"))
FALLBACK_KEYWORDS  = [
    "i don't understand", "i'm not sure", "can't help with that",
    "i'm unable", "i cannot", "i can’t", "not able to handle"
]

# Logging (JSON lines)
LOG_PATH = os.getenv("LOG_PATH", "/tmp/calls.jsonl")

# ---------- Clients ----------
client = OpenAI(api_key=OPENAI_API_KEY)
twilio_client = (TwilioClient(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
                 if TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN else None)

# ---------- In-memory call state (OK for MVP; use Redis/DB later) ----------
# CALL_STATE[CallSid] = {
#   "intent": "reservation"|"qa"|None,
#   "slots": { "party_size":None, "date":None, "time":None, "name":None, "callback_number":None },
#   "turns": 0
# }
CALL_STATE = {}
CALL_NOTES = {}   # CallSid -> list of {"role": "user"/"assistant", "text": str}

RESERVATION_SLOT_KEYS = ["party_size", "date", "time", "name", "callback_number"]

# ---------- App ----------
app = Flask(__name__)
app.logger.setLevel(logging.INFO)

# ---------- Helpers ----------
def https_base() -> str:
    proto = request.headers.get("X-Forwarded-Proto", "http")
    base = request.url_root
    if proto == "https" and base.startswith("http://"):
        base = base.replace("http://", "https://", 1)
    base = base.replace("http://", "https://", 1)
    return base.rstrip("/")

def twiml(vr: VoiceResponse):
    return str(vr), 200, {"Content-Type": "text/xml"}

def ask_gpt(prompt: str) -> str:
    try:
        resp = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.7,
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        app.logger.exception("OpenAI error")
        return f"Sorry, I hit an error talking to ChatGPT: {e}"

def is_valid_twilio_request(req) -> bool:
    if SKIP_TWILIO_VALIDATION:
        return True
    if not TWILIO_AUTH_TOKEN:
        app.logger.warning("TWILIO_AUTH_TOKEN not set; rejecting webhook.")
        return False
    signature = req.headers.get("X-Twilio-Signature", "")
    validator = RequestValidator(TWILIO_AUTH_TOKEN)
    url = req.url
    params = dict(req.form) if req.method == "POST" else {}
    try:
        return validator.validate(url, params, signature)
    except Exception as e:
        app.logger.exception("Twilio validation error: %r", e)
        return False

def is_valid_api_request(req) -> bool:
    if not API_TOKEN:
        app.logger.error("API_TOKEN not set; denying API request.")
        return False
    return req.headers.get("Authorization", "") == f"Bearer {API_TOKEN}"

def normalize_e164(num: str) -> str:
    s = "".join(ch for ch in num if ch.isdigit() or ch == "+")
    if s and s[0] != "+":
        if len(s) == 10:  # naive US default
            s = "+1" + s
    return s

def note_append(call_sid: str, role: str, text: str):
    CALL_NOTES.setdefault(call_sid, []).append({"role": role, "text": text})

def log_json(call_sid: str, role: str, text: str, intent: str | None, slots: dict | None):
    try:
        row = {
            "ts": datetime.utcnow().isoformat() + "Z",
            "call_sid": call_sid,
            "role": role,
            "text": text,
            "intent": intent,
            "slots": (slots or {}),
        }
        with open(LOG_PATH, "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    except Exception:
        app.logger.exception("log_json failed")

def send_email(subject: str, body: str) -> bool:
    if not ENABLE_EMAIL:
        app.logger.info("Email disabled or SendGrid not available.")
        return False
    try:
        sg = SendGridAPIClient(SENDGRID_API_KEY)
        message = Mail(
            from_email=ADMIN_EMAIL_FROM,
            to_emails=ADMIN_EMAIL_TO,
            subject=subject,
            plain_text_content=body,
        )
        sg.send(message)
        return True
    except Exception:
        app.logger.exception("SendGrid email error")
        return False

def should_fallback(call_sid: str, assistant_text: str) -> bool:
    turns = CALL_STATE.get(call_sid, {}).get("turns", 0)
    if turns >= MAX_TURNS_PER_CALL:
        return True
    low = (assistant_text or "").lower()
    return any(k in low for k in FALLBACK_KEYWORDS)

# ---------- Intent & Reservation parsing ----------
def detect_intent(user_text: str) -> str:
    t = user_text.lower()
    if any(w in t for w in ["reservation", "reserve", "book a table", "book", "table for"]):
        return "reservation"
    return "qa"

def ensure_call_state(call_sid: str):
    if call_sid not in CALL_STATE:
        CALL_STATE[call_sid] = {
            "intent": None,
            "turns": 0,
            "slots": {k: None for k in RESERVATION_SLOT_KEYS},
        }

def fill_reservation_slots_from_text(slots: dict, text: str) -> dict:
    t = text.lower()

    # party size
    m = re.search(r"\b(?:for|party|table)\s*(\d{1,2})\b", t)
    if m and not slots.get("party_size"):
        slots["party_size"] = m.group(1)

    # time (very naive)
    m = re.search(r"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b", t)
    if m and not slots.get("time"):
        hh = m.group(1)
        mm = m.group(2) or "00"
        ampm = m.group(3) or ""
        slots["time"] = f"{hh}:{mm}{(' ' + ampm) if ampm else ''}".strip()

    # date keywords (naive)
    for kw in ["today", "tonight", "tomorrow", "mon", "tue", "wed", "thu", "fri", "sat", "sun",
               "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]:
        if kw in t and not slots.get("date"):
            slots["date"] = kw
            break

    # name
    m = re.search(r"\b(?:name(?: is)?|under)\s+([a-z]+(?:\s+[a-z]+)?)\b", t)
    if m and not slots.get("name"):
        slots["name"] = m.group(1).title()

    # callback number
    m = re.search(r"(\+?\d[\d\-\s\(\)]{7,}\d)", text)  # keep original (not lower)
    if m and not slots.get("callback_number"):
        slots["callback_number"] = normalize_e164(m.group(1))

    return slots

def reservation_missing_slots(slots: dict) -> list[str]:
    return [k for k in RESERVATION_SLOT_KEYS if not slots.get(k)]

def reservation_next_question(missing: list[str]) -> str:
    order = RESERVATION_SLOT_KEYS
    for k in order:
        if k in missing:
            if k == "party_size":
                return "How many people is the reservation for?"
            if k == "date":
                return "What day would you like? For example, today, tomorrow, or a weekday."
            if k == "time":
                return "What time would you like the reservation?"
            if k == "name":
                return "What name should I put the reservation under?"
            if k == "callback_number":
                return "What is a callback phone number, with country code please?"
    return "Could you provide more details?"

def reservation_confirmation(slots: dict) -> str:
    return (f"To confirm, I have a reservation for {slots['party_size']} "
            f"on {slots['date']} at {slots['time']}, under {slots['name']}, "
            f"callback number {slots['callback_number']}. Is that correct?")

# ---------- Diagnostics ----------
@app.route("/whereami")
def whereami():
    return {
        "host": request.host,
        "host_url": request.host_url,
        "url_root": request.url_root,
        "full_url_you_hit": request.url,
        "scheme": request.scheme,
    }

@app.route("/health", methods=["GET"])
def health():
    return "OK", 200

@app.route("/")
def home():
    return "Flask + GPT is running. Try /ask (Bearer token), /voice (Twilio), /voice-test."

# ---------- JSON Ask (secured) ----------
@app.route("/ask", methods=["GET", "POST"])
def ask():
    if not is_valid_api_request(request):
        return make_response("Unauthorized", 401)
    text = (request.args.get("text") or "").strip() if request.method == "GET" else (
        (request.get_json(silent=True) or {}).get("text") or ""
    ).strip()
    if not text:
        return make_response("Provide text via ?text=... or JSON {'text':'...'}", 400)
    answer = ask_gpt(text)
    r = make_response(answer, 200)
    r.headers["Content-Type"] = "text/plain; charset=utf-8"
    return r

# ---------- Outbound calls (secured) ----------
@app.route("/call", methods=["POST"])
def start_call():
    if not is_valid_api_request(request):
        return make_response("Unauthorized", 401)
    if not twilio_client or not TWILIO_NUMBER:
        return make_response("Server missing Twilio creds (TWILIO_ACCOUNT_SID/TWILIO_AUTH_TOKEN/TWILIO_NUMBER).", 500)
    data = request.get_json(silent=True) or {}
    to = normalize_e164((data.get("to") or "").strip())
    if not to or len(to) < 8:
        return make_response("Provide JSON {'to':'+15558675309'} (E.164).", 400)
    try:
        call = twilio_client.calls.create(
            to=to,
            from_=TWILIO_NUMBER,
            url=f"{https_base()}/outbound-answer",
            method="POST",
        )
        return {"sid": call.sid}, 200
    except Exception as e:
        app.logger.exception("Twilio outbound call error")
        return make_response(f"Twilio error: {e}", 500)

@app.route("/outbound-answer", methods=["GET", "POST"])
def outbound_answer():
    vr = VoiceResponse()
    gather = Gather(
        input="speech",
        action=f"{https_base()}/gather",
        method="POST",
        language="en-US",
        speechTimeout="auto",
    )
    gather.say("Hi! What can I help you with?")
    vr.append(gather)
    vr.redirect(f"{https_base()}/voice")
    return twiml(vr)

# ---------- Twilio inbound call flow ----------
@app.route("/voice", methods=["GET", "POST"])
def voice():
    app.logger.info("VOICE hit: %s %s", request.method, request.url)
    if not is_valid_twilio_request(request):
        app.logger.warning("Invalid Twilio signature on /voice")
        return "Forbidden", 403
    vr = VoiceResponse()
    try:
        gather = Gather(
            input="speech",
            action=f"{https_base()}/gather",
            method="POST",
            language="en-US",
            speechTimeout="auto",
        )
        gather.say("Hi! What can I help you with?")
        vr.append(gather)
        vr.redirect(f"{https_base()}/voice")
        return twiml(vr)
    except Exception:
        app.logger.exception("ERROR in /voice")
        vr.say("I hit an application error. Please try again.")
        return twiml(vr)

@app.route("/voice-test", methods=["GET", "POST"])
def voice_test():
    app.logger.info("VOICE-TEST hit: %s %s", request.method, request.url)
    vr = VoiceResponse()
    vr.say("Your Twilio webhook is connected. This is a test.")
    return twiml(vr)

# ---------- Core conversation loop with intent + slot filling ----------
@app.route("/gather", methods=["GET", "POST"])
def gather():
    app.logger.info("GATHER hit: %s %s form=%s", request.method, request.url, dict(request.form))
    if not is_valid_twilio_request(request):
        app.logger.warning("Invalid Twilio signature on /gather")
        return "Forbidden", 403

    vr = VoiceResponse()
    try:
        if request.method == "GET":
            vr.say("Let's try that again.")
            vr.redirect(f"{https_base()}/voice")
            return twiml(vr)

        call_sid = request.form.get("CallSid", "unknown")
        user_text = (request.form.get("SpeechResult") or "").strip()
        app.logger.info("SpeechResult: %r (CallSid=%s)", user_text, call_sid)

        ensure_call_state(call_sid)
        state = CALL_STATE[call_sid]
        state["turns"] += 1
        note_append(call_sid, "user", user_text)
        log_json(call_sid, "user", user_text, state.get("intent"), state.get("slots"))

        if not user_text:
            vr.say("I didn't catch that. Please try again after the beep.")
            vr.redirect(f"{https_base()}/voice")
            return twiml(vr)

        # --- Voice command: "call <number>" ---
        m = re.search(r"(?:call|dial)\s+([+\d][\d\-\s\(\)]{6,})", user_text.lower())
        if m:
            number = normalize_e164(m.group(1))
            if number and len(number) >= 8:
                vr.say(f"Calling {number}.")
                from_number = TWILIO_NUMBER or None
                with vr.dial(caller_id=from_number) as d:
                    d.number(number)
                note_append(call_sid, "assistant", f"[dial] {number}")
                log_json(call_sid, "assistant", f"[dial] {number}", state.get("intent"), state.get("slots"))
                return twiml(vr)
            vr.say("Please say the number with the country code, like plus one then the number.")
            vr.redirect(f"{https_base()}/voice")
            return twiml(vr)

        # --- Intent detection (once) ---
        if state["intent"] is None:
            state["intent"] = detect_intent(user_text)

        if state["intent"] == "reservation":
            # Fill slots from current utterance
            state["slots"] = fill_reservation_slots_from_text(state["slots"], user_text)
            missing = reservation_missing_slots(state["slots"])

            if not missing:
                # All info present – confirm + email + end
                confirm = reservation_confirmation(state["slots"])
                vr.say(confirm)
                note_append(call_sid, "assistant", confirm)
                log_json(call_sid, "assistant", confirm, state["intent"], state["slots"])

                summary = ("Reservation details:\n" +
                           json.dumps(state["slots"], indent=2))
                send_email(subject=f"Reservation request (Call {call_sid})",
                           body=summary + "\n\n(Automated summary from AI Secretary)")

                vr.say("Thanks. I’ll follow up by email to confirm next steps.")
                return twiml(vr)

            # Ask next missing slot
            q = reservation_next_question(missing)
            vr.say(q)
            note_append(call_sid, "assistant", q)
            log_json(call_sid, "assistant", q, state["intent"], state["slots"])

            again = Gather(
                input="speech",
                action=f"{https_base()}/gather",
                method="POST",
                language="en-US",
                speechTimeout="auto",
            )
            vr.append(again)
            return twiml(vr)

        # --- General Q&A fallback if not reservation ---
        answer = ask_gpt(user_text)
        note_append(call_sid, "assistant", answer)
        log_json(call_sid, "assistant", answer, state["intent"], state["slots"])

        if should_fallback(call_sid, answer):
            vr.say("Thanks. I’m going to take notes and have my manager follow up by email.")
            # Build a concise transcript
            last = CALL_NOTES.get(call_sid, [])[-12:]
            lines = [f"[{n['role']}] {n['text']}" for n in last]
            send_email(subject=f"AI Secretary fallback (Call {call_sid})",
                       body="Recent turns:\n" + "\n".join(lines))
            vr.say("Goodbye.")
            return twiml(vr)

        vr.say(answer)
        vr.pause(length=1)
        vr.say("You can ask another question after the beep.")
        again = Gather(
            input="speech",
            action=f"{https_base()}/gather",
            method="POST",
            language="en-US",
            speechTimeout="auto",
        )
        vr.append(again)
        return twiml(vr)

    except Exception:
        app.logger.exception("ERROR in /gather")
        vr.say("I hit an application error while processing your speech. Please try again.")
        vr.redirect(f"{https_base()}/voice")
        return twiml(vr)

# ---------- Main ----------
if __name__ == "__main__":
    port = int(os.getenv("PORT", "5000"))
    app.run(host="0.0.0.0", port=port)

