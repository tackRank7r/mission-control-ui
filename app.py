import os
import logging
from flask import Flask, request, make_response
from dotenv import load_dotenv
from openai import OpenAI
from twilio.twiml.voice_response import VoiceResponse, Gather
from twilio.request_validator import RequestValidator
from twilio.rest import Client as TwilioClient

# ---------- Load .env FIRST (Render uses env vars; this helps local dev) ----------
load_dotenv()

# ---------- Secrets / Config ----------
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# Twilio creds (used for both signature validation and outbound calls)
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_NUMBER = os.getenv("TWILIO_NUMBER", "")

# For temporary testing without Twilio signature validation, set to "true" in env.
SKIP_TWILIO_VALIDATION = os.getenv("SKIP_TWILIO_VALIDATION", "false").lower() == "true"

# ✅ API token for your own JSON APIs (/ask, /call)
# Set in Render → Environment → API_TOKEN, and your iOS app sends: Authorization: Bearer <API_TOKEN>
API_TOKEN = os.getenv("API_TOKEN", "")

# ---------- Clients ----------
client = OpenAI(api_key=OPENAI_API_KEY)
twilio_client = (
    TwilioClient(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
    if TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN
    else None
)

# ---------- App ----------
app = Flask(__name__)
app.logger.setLevel(logging.INFO)

# ---------- Helpers ----------
def https_base() -> str:
    """Build an absolute HTTPS base URL for callbacks (Twilio requires https)."""
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
    """Verify the webhook came from Twilio via signature header."""
    if SKIP_TWILIO_VALIDATION:
        return True  # allow during manual curl tests only

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

# ✅ Bearer-token guard for /ask and /call
def is_valid_api_request(req) -> bool:
    """
    Require Authorization: Bearer <API_TOKEN> for JSON APIs.
    Purpose: prevent random internet access to /ask and /call.
    """
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
    to_raw = (data.get("to") or "").strip()
    to = normalize_e164(to_raw)
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

        # Fallback loop if nothing captured
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

        user_text = (request.form.get("SpeechResult") or "").strip()
        app.logger.info("SpeechResult: %r", user_text)

        if not user_text:
            vr.say("I didn't catch that. Please try again after the beep.")
            vr.redirect(f"{https_base()}/voice")
            return twiml(vr)

        answer = ask_gpt(user_text)

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
