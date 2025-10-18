
# file: app.py  — NON-DESTRUCTIVE MERGE: keeps your features, adds /api/chat + optional Twilio voice
from __future__ import annotations

import hashlib
import hmac
import logging
import os
import sys
from functools import wraps
from typing import Callable, Optional, Tuple

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from flask import Flask, Response, jsonify, make_response, request

# Optional OpenAI for /ask and /api/chat
try:
    from openai import OpenAI  # openai>=1.x
except Exception:  # pragma: no cover
    OpenAI = None  # type: ignore

# Optional Twilio (voice) — enabled only if installed
try:
    from twilio.twiml.voice_response import VoiceResponse, Gather  # type: ignore
    _TWILIO_AVAILABLE = True
except Exception:  # pragma: no cover
    VoiceResponse = None  # type: ignore
    Gather = None  # type: ignore
    _TWILIO_AVAILABLE = False

# --- App setup ---
app = Flask(__name__)
app.logger.setLevel(logging.INFO)
app.logger.warning(
    "BOOT cwd=%s file=%s py=%s",
    os.getcwd(),
    __file__,
    sys.version.split()[0],
)

# --- Config ---
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
POLLY_VOICE_DEFAULT = os.getenv("POLLY_VOICE", "Joanna")
POLLY_FORMAT_DEFAULT = os.getenv("POLLY_FORMAT", "mp3")  # mp3 | ogg_vorbis
POLLY_ENGINE_DEFAULT = os.getenv("POLLY_ENGINE", "neural")
TTS_CACHE_S3_BUCKET = os.getenv("TTS_CACHE_S3_BUCKET")

# Security
BACKEND_BEARER = os.getenv("APP_BACKEND_BEARER") or os.getenv("API_TOKEN")

# --- AWS clients ---
_session = boto3.session.Session(region_name=AWS_REGION)
polly = _session.client("polly")
s3 = _session.client("s3") if TTS_CACHE_S3_BUCKET else None

# --- Auth ---
def _extract_bearer(auth_header: Optional[str]) -> Optional[str]:
    if not auth_header:
        return None
    parts = auth_header.split()
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1]
    return None

def require_bearer_token(fn: Callable):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not BACKEND_BEARER:
            return jsonify({"error": "server_misconfigured_no_token"}), 500
        token = _extract_bearer(request.headers.get("Authorization"))
        if not token or not hmac.compare_digest(token, BACKEND_BEARER):
            return jsonify({"error": "unauthorized"}), 401
        return fn(*args, **kwargs)
    return wrapper

# --- Twilio helpers ---
def https_base() -> str:
    """Force https base URL for Twilio callbacks (why: Twilio requires https)."""
    proto = request.headers.get("X-Forwarded-Proto", "http")
    base = request.url_root
    if proto == "https" and base.startswith("http://"):
        base = base.replace("http://", "https://", 1)
    base = base.replace("http://", "https://", 1)
    return base.rstrip("/")

# --- TTS helpers (AWS Polly) ---
def _tts_cache_key(text: str, voice: str, fmt: str, engine: str) -> str:
    h = hashlib.sha256()
    h.update(voice.encode()); h.update(b"|")
    h.update(fmt.encode());   h.update(b"|")
    h.update(engine.encode());h.update(b"|")
    h.update(" ".join(text.split()).encode())  # normalize whitespace
    ext = "mp3" if fmt == "mp3" else "ogg"
    return f"tts/{voice}/{engine}/{h.hexdigest()}.{ext}"

def _s3_get(bucket: str, key: str) -> Optional[bytes]:
    if not s3:
        return None
    try:
        obj = s3.get_object(Bucket=bucket, Key=key)
        return obj["Body"].read()
    except (ClientError, BotoCoreError, KeyError):
        return None

def _s3_put(bucket: str, key: str, data: bytes, content_type: str) -> None:
    if not s3:
        return
    try:
        s3.put_object(
            Bucket=bucket, Key=key, Body=data, ContentType=content_type,
            CacheControl="public, max-age=31536000, immutable",
        )
    except (ClientError, BotoCoreError) as e:
        app.logger.warning("S3 cache put failed: %s", e)

def synthesize_speech(
    text: str,
    voice: str = POLLY_VOICE_DEFAULT,
    fmt: str = POLLY_FORMAT_DEFAULT,
    engine: str = POLLY_ENGINE_DEFAULT,
) -> Tuple[Optional[bytes], Optional[str]]:
    if not text:
        return None, None
    cache_key = None
    if TTS_CACHE_S3_BUCKET:
        cache_key = _tts_cache_key(text, voice, fmt, engine)
        cached = _s3_get(TTS_CACHE_S3_BUCKET, cache_key)
        if cached:
            ct = "audio/mpeg" if fmt == "mp3" else "audio/ogg"
            return cached, ct
    try:
        resp = polly.synthesize_speech(Text=text, OutputFormat=fmt, VoiceId=voice, Engine=engine)
        audio = resp["AudioStream"].read()
        ct = "audio/mpeg" if fmt == "mp3" else "audio/ogg"
        if TTS_CACHE_S3_BUCKET and cache_key and audio:
            _s3_put(TTS_CACHE_S3_BUCKET, cache_key, audio, ct)
        return audio, ct
    except Exception as e:  # boundary
        app.logger.exception("Polly error: %s", e)
        return None, None

# --- OpenAI wrapper ---
def _openai_client():
    if OpenAI is None:
        raise RuntimeError("openai package not available")
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError("OPENAI_API_KEY not set")
    return OpenAI(api_key=key)

def generate_ai_reply(prompt: str) -> str:
    model = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    try:
        client = _openai_client()
        res = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You are a concise AI Secretary."},
                {"role": "user", "content": prompt},
            ],
            temperature=0.3,
        )
        return (res.choices[0].message.content or "").strip()
    except Exception as e:
        app.logger.warning("OpenAI error: %s", e)
        return "I'm here."

# --- Public JSON routes (kept) ---
@app.get("/health")
def health() -> Response:
    return jsonify({"ok": True, "service": "ai-secretary", "polly_region": AWS_REGION})

@app.get("/diagnostics")
def diagnostics() -> Response:
    import flask
    import boto3 as boto3_pkg
    return jsonify(
        {
            "python_version": sys.version.split()[0],
            "flask_version": flask.__version__,
            "boto3_version": boto3_pkg.__version__,
            "aws_region": AWS_REGION,
            "s3_cache_enabled": bool(TTS_CACHE_S3_BUCKET),
            "env_flags": {
                "APP_BACKEND_BEARER": bool(os.getenv("APP_BACKEND_BEARER")),
                "OPENAI_API_KEY": bool(os.getenv("OPENAI_API_KEY")),
                "AWS_ACCESS_KEY_ID": bool(os.getenv("AWS_ACCESS_KEY_ID")),
                "AWS_SECRET_ACCESS_KEY": bool(os.getenv("AWS_SECRET_ACCESS_KEY")),
                "TTS_CACHE_S3_BUCKET": bool(os.getenv("TTS_CACHE_S3_BUCKET")),
            },
        }
    )

@app.get("/__stamp")
def __stamp() -> Response:
    return jsonify({"commit": os.getenv("RENDER_GIT_COMMIT") or os.getenv("GIT_SHA") or "unknown"})

@app.get("/__where")
def __where() -> Response:
    return jsonify({"cwd": os.getcwd(), "__file__": __file__})

@app.get("/")
def index():
    return (
        "<h1>AI Secretary</h1>"
        '<p>Service is running. Try <a href="/health">/health</a> or <a href="/diagnostics">/diagnostics</a>.</p>',
        200,
        {"Content-Type": "text/html; charset=utf-8"},
    )

# --- Auth-required routes (kept) ---
@app.post("/ask")
@require_bearer_token
def ask() -> Response:
    data = request.get_json(silent=True) or {}
    prompt = str(data.get("prompt", "")).strip()
    if not prompt:
        return jsonify({"error": "missing_prompt"}), 400
    reply = generate_ai_reply(prompt)
    return jsonify({"reply": reply})

@app.post("/speak")
@require_bearer_token
def speak() -> Response:
    data = request.get_json(silent=True) or {}
    text = str(data.get("text", "")).strip()
    voice = str(data.get("voice", POLLY_VOICE_DEFAULT))
    fmt = str(data.get("format", POLLY_FORMAT_DEFAULT))
    engine = str(data.get("engine", POLLY_ENGINE_DEFAULT))

    audio, content_type = synthesize_speech(text, voice=voice, fmt=fmt, engine=engine)
    if not audio:
        return jsonify({"error": "tts_failed"}), 500

    resp = make_response(audio)
    resp.headers["Content-Type"] = content_type or "application/octet-stream"
    return resp

# --- iOS chat endpoints (NEW; additive, not replacing anything) ---
@app.get("/api/chat")
def api_chat_ping() -> Response:
    # why: used by the app’s “Test Backend” button
    return jsonify({"status": "ok", "path": "/api/chat", "method": "GET"})

@app.post("/api/chat")
@require_bearer_token
def api_chat_post() -> Response:
    """
    Accepts: { messages: [{role,content,...}, ...], userText: str }
    Returns: { reply: str }
    """
    data = request.get_json(silent=True) or {}
    user_text = str(data.get("userText", "")).strip()

    if not user_text:
        msgs = data.get("messages") or []
        for m in reversed(msgs):
            if (m.get("role") == "user") and str(m.get("content", "")).strip():
                user_text = str(m["content"]).strip()
                break

    if not user_text:
        return jsonify({"error": "empty_user_text"}), 400

    reply = generate_ai_reply(user_text)
    return jsonify({"reply": reply})

# --- Twilio Voice (OPTIONAL; enabled only if twilio is installed) ---
if _TWILIO_AVAILABLE:
    @app.get("/voice")
    @app.post("/voice")
    def voice() -> Response:
        app.logger.info("VOICE hit: method=%s url=%s", request.method, request.url)
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
            vr.redirect(f"{https_base()}/voice")  # reprompt on no input
            return str(vr), 200, {"Content-Type": "text/xml"}
        except Exception:
            app.logger.exception("ERROR in /voice")
            vr.say("I hit an application error. Please try again.")
            return str(vr), 200, {"Content-Type": "text/xml"}

    @app.get("/gather")
    @app.post("/gather")
    def gather() -> Response:
        app.logger.info(
            "GATHER hit: method=%s url=%s form=%s",
            request.method, request.url, dict(request.form)
        )
        vr = VoiceResponse()
        try:
            if request.method == "GET":
                vr.say("Let's try that again.")
                vr.redirect(f"{https_base()}/voice")
                return str(vr), 200, {"Content-Type": "text/xml"}

            user_text = str(request.form.get("SpeechResult", "")).strip()
            app.logger.info("SpeechResult: %r", user_text)

            if not user_text:
                vr.say("I didn't catch that. Please try again after the beep.")
                vr.redirect(f"{https_base()}/voice")
                return str(vr), 200, {"Content-Type": "text/xml"}

            answer = generate_ai_reply(user_text)
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
            return str(vr), 200, {"Content-Type": "text/xml"}
        except Exception:
            app.logger.exception("ERROR in /gather")
            vr.say("I hit an application error while processing your speech. Please try again.")
            vr.redirect(f"{https_base()}/voice")
            return str(vr), 200, {"Content-Type": "text/xml"}
else:
    @app.get("/voice")
    @app.post("/voice")
    def voice_unavailable() -> Response:
        return make_response("Twilio not installed on this deployment.", 501)

    @app.get("/gather")
    @app.post("/gather")
    def gather_unavailable() -> Response:
        return make_response("Twilio not installed on this deployment.", 501)

# --- Main ---
if __name__ == "__main__":
    port = int(os.getenv("PORT", "5000"))
    app.run(host="0.0.0.0", port=port, debug=bool(os.getenv("FLASK_DEBUG")))
