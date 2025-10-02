

# ===== Flask backend: add bearer auth & /health/auth =====
# File: app.py
import os
import logging
from flask import Flask, request, make_response, jsonify
from dotenv import load_dotenv
from openai import OpenAI
from twilio.twiml.voice_response import VoiceResponse, Gather

load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

API_TOKEN = os.getenv("API_TOKEN")  # <-- define in your .env
app = Flask(__name__)
app.logger.setLevel(logging.INFO)

def require_auth():
    # WHY: lock down your endpoints; avoids accepting GitHub PAT by mistake.
    if not API_TOKEN:
        return None  # auth disabled if not configured
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return make_response(jsonify(error="missing_bearer"), 401)
    token = auth.split(" ", 1)[1].strip()
    if token != API_TOKEN:
        return make_response(jsonify(error="invalid_bearer"), 403)
    return None

def https_base() -> str:
    proto = request.headers.get("X-Forwarded-Proto", "http")
    base = request.url_root
    if proto == "https" and base.startswith("http://"):
        base = base.replace("http://", "https://", 1)
    return base.replace("http://", "https://", 1).rstrip("/")

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

def twiml(response: VoiceResponse):
    return str(response), 200, {"Content-Type": "text/xml"}

@app.get("/")
def home():
    return "Flask + GPT is running. Try /ask?text=Hello"

@app.get("/health")
def health():
    return "OK", 200

@app.get("/health/auth")
def health_auth():
    auth_err = require_auth()
    if auth_err: return auth_err
    return jsonify(ok=True, message="Auth OK"), 200

@app.route("/ask", methods=["GET", "POST"])
def ask():
    auth_err = require_auth()
    if auth_err: return auth_err

    if request.method == "GET":
        text = (request.args.get("text") or "").strip()
    else:
        data = request.get_json(silent=True) or {}
        text = (data.get("text") or "").strip()
    if not text:
        return make_response("Provide text via ?text=... or JSON {'text':'...'}", 400)
    answer = ask_gpt(text)
    resp = make_response(answer, 200)
    resp.headers["Content-Type"] = "text/plain; charset=utf-8"
    return resp

@app.route("/voice-test", methods=["GET", "POST"])
def voice_test():
    # Typically leave this open for Twilio webhook testing
    vr = VoiceResponse()
    vr.say("Your Twilio webhook is connected. This is a test.")
    return twiml(vr)

@app.route("/voice", methods=["GET", "POST"])
def voice():
    # If you front this with Twilio only, you can skip auth here; otherwise enable:
    # auth_err = require_auth();  if auth_err: return auth_err
    vr = VoiceResponse()
    try:
        gather_action = f"{https_base()}/gather"
        gather = Gather(input="speech", action=gather_action, method="POST",
                        language="en-US", speechTimeout="auto")
        gather.say("Hi! What can I help you with?")
        vr.append(gather)
        vr.redirect(f"{https_base()}/voice")
        return twiml(vr)
    except Exception:
        app.logger.exception("ERROR in /voice")
        vr.say("I hit an application error. Please try again.")
        return twiml(vr)

@app.route("/gather", methods=["GET", "POST"])
def gather():
    # Same note as /voice regarding auth
    vr = VoiceResponse()
    try:
        if request.method == "GET":
            vr.say("Let's try that again.")
            vr.redirect(f"{https_base()}/voice")
            return twiml(vr)

        user_text = (request.form.get("SpeechResult") or "").strip()
        if not user_text:
            vr.say("I didn't catch that. Please try again after the beep.")
            vr.redirect(f"{https_base()}/voice")
            return twiml(vr)

        answer = ask_gpt(user_text)
        vr.say(answer)
        vr.pause(length=1)
        vr.say("You can ask another question after the beep.")

        again = Gather(input="speech", action=f"{https_base()}/gather",
                       method="POST", language="en-US", speechTimeout="auto")
        vr.append(again)
        return twiml(vr)
    except Exception:
        app.logger.exception("ERROR in /gather")
        vr.say("I hit an application error while processing your speech. Please try again.")
        vr.redirect(f"{https_base()}/voice")
        return twiml(vr)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
