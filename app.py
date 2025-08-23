import os
import logging
from flask import Flask, request, make_response
from dotenv import load_dotenv
from openai import OpenAI
from twilio.twiml.voice_response import VoiceResponse, Gather
from twilio.request_validator import RequestValidator

# --------- Load local .env in development (Render uses Env Vars) ----------
load_dotenv()

# --------- Secrets / Config ----------
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "")
# For temporary testing without Twilio signature validation, set to "true" in env.
SKIP_TWILIO_VALIDATION = os.getenv("SKIP_TWILIO_VALIDATION", "false").lower() == "true"

# --------- Clients ----------
client = OpenAI(api_key=OPENAI_API_KEY)

# --------- App ----------
app = Flask(__name__)
app.logger.setLevel(logging.INFO)

@app.route("/whereami")
def whereami():
    # shows the exact public base URL Twilio/you should use
    from flask import request
    return {
        "host": request.host,               # e.g., ai-secretary.onrender.com
        "host_url": request.host_url,       # e.g., https://ai-secretary.onrender.com/
        "url_root": request.url_root,       # same as above
        "full_url_you_hit": request.url,    # includes path (/whereami)
        "scheme": request.scheme            # http/https
    }


# --------- Helpers ----------
def https_base() -> str:
    """
    Build an absolute HTTPS base URL for callbacks.
    Works behind proxies/Render (Twilio requires https).
    """
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

# ---- Twilio signature validation ----
def is_valid_twilio_request(req) -> bool:
    """
    Verify that this request genuinely came from Twilio.
    Twilio sends 'X-Twilio-Signature' for webhooks.
    """
    if SKIP_TWILIO_VALIDATION:
        return True  # allow while you're testing; turn off in production

    if not TWILIO_AUTH_TOKEN:
        app.logger.warning("TWILIO_AUTH_TOKEN not set; rejecting webhook.")
        return False

    signature = req.headers.get("X-Twilio-Signature", "")
    validator = RequestValidator(TWILIO_AUTH_TOKEN)
    # Twilio signs full URL + POST params (GET will have no params)
    url = req.url
    params = dict(req.form) if req.method == "POST" else {}
    try:
        return validator.validate(url, params, signature)
    except Exception as e:
        app.logger.exception("Twilio validation error: %r", e)
        return False

# --------- Basic / diagnostics routes ----------
@app.route("/")
def home():
    return "Flask + GPT is running. Try /ask?text=Hello"

@app.route("/ask", methods=["GET", "POST"])
def ask():
    text = (request.args.get("text") or "").strip() if request.method == "GET" else (
        (request.get_json(silent=True) or {}).get("text") or ""
    ).strip()
    if not text:
        return make_response("Provide text via ?text=... or JSON {'text':'...'}", 400)
    answer = ask_gpt(text)
    r = make_response(answer, 200)
    r.headers["Content-Type"] = "text/plain; charset=utf-8"
    return r

@app.route("/health", methods=["GET"])
def health():
    return "OK", 200

@app.route("/voice-test", methods=["GET", "POST"])
def voice_test():
    app.logger.info("VOICE-TEST hit: %s %s", request.method, request.url)
    vr = VoiceResponse()
    vr.say("Your Twilio webhook is connected. This is a test.")
    return twiml(vr)

# --------- Twilio call flow ----------
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

# --------- Main ----------
# --------- Main ----------
if __name__ == "__main__":
    port = int(os.getenv("PORT", "5000"))  # <-- use Render's PORT if present
    app.run(host="0.0.0.0", port=port)

