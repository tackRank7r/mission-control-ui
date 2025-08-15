import os
import logging
from flask import Flask, request, make_response
from dotenv import load_dotenv
from openai import OpenAI
from twilio.twiml.voice_response import VoiceResponse, Gather

# ---------- Setup ----------
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

app = Flask(__name__)
app.logger.setLevel(logging.INFO)

# ---------- Helpers ----------
def https_base() -> str:
    """Return your public base URL, forced to https (Twilio expects https)."""
    # Respect X-Forwarded-Proto if present (some proxies set it)
    proto = request.headers.get("X-Forwarded-Proto", "http")
    base = request.url_root
    if proto == "https" and base.startswith("http://"):
        base = base.replace("http://", "https://", 1)
    # Fallback force https
    base = base.replace("http://", "https://", 1)
    return base.rstrip("/")

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

def twiml(vr: VoiceResponse):
    return str(vr), 200, {"Content-Type": "text/xml"}

# ---------- Basic routes ----------
@app.route("/")
def home():
    return "Flask + GPT is running. Try /ask?text=Hello"

@app.route("/ask", methods=["GET", "POST"])
def ask():
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

# ---------- Diagnostics ----------
@app.route("/health", methods=["GET"])
def health():
    return "OK", 200

@app.route("/voice-test", methods=["GET", "POST"])
def voice_test():
    app.logger.info("VOICE-TEST hit: method=%s url=%s", request.method, request.url)
    vr = VoiceResponse()
    vr.say("Your Twilio webhook is connected. This is a test.")
    return twiml(vr)

# ---------- Twilio call flow ----------
@app.route("/voice", methods=["GET", "POST"])
def voice():
    app.logger.info("VOICE hit: method=%s url=%s", request.method, request.url)
    vr = VoiceResponse()
    try:
        gather = Gather(
            input="speech",
            action=f"{https_base()}/gather",  # absolute https
            method="POST",
            language="en-US",
            speechTimeout="auto",
        )
        gather.say("Hi! What can I help you with?")
        vr.append(gather)

        # If nothing captured, reprompt
        vr.redirect(f"{https_base()}/voice")
        return twiml(vr)
    except Exception:
        app.logger.exception("ERROR in /voice")
        vr.say("I hit an application error. Please try again.")
        return twiml(vr)

@app.route("/gather", methods=["GET", "POST"])
def gather():
    app.logger.info(
        "GATHER hit: method=%s url=%s form=%s",
        request.method, request.url, dict(request.form)
    )
    vr = VoiceResponse()
    try:
        # If GET (browser/misfire), reprompt
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
    app.run(host="0.0.0.0", port=5000)
