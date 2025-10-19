# =====================================
# File: app.py  (FULL REPLACEMENT)
# Flask backend for Jarvis (Render)
# - /ask: demo echo (replace with your real LLM logic)
# - /speak: TTS (Polly -> OpenAI fallback), returns audio/mpeg bytes
# - /diagnostics: flags used by the iOS DiagnosticsView
# - /health: Render health check
# =====================================
import os
import json
from flask import Flask, request, jsonify, Response
from datetime import datetime

# Optional deps—installed per requirements.txt
# If not available, we'll degrade gracefully.
try:
    import boto3
    from botocore.exceptions import BotoCoreError, ClientError
except Exception:
    boto3 = None
    BotoCoreError = ClientError = Exception

try:
    from openai import OpenAI
except Exception:
    OpenAI = None

app = Flask(__name__)

# -----------------------
# Config / Environment
# -----------------------
APP_BACKEND_BEARER = os.getenv("APP_BACKEND_BEARER", "")  # matches render.yaml
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
POLLY_VOICE = os.getenv("POLLY_VOICE", "Matthew")
POLLY_ENGINE = os.getenv("POLLY_ENGINE", "standard")  # "neural" if voice/region supports it
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

def _auth_ok(req) -> bool:
    if not APP_BACKEND_BEARER:
        return True  # no auth configured
    return req.headers.get("Authorization", "") == f"Bearer {APP_BACKEND_BEARER}"

# -----------------------
# Health & Diagnostics
# -----------------------
@app.route("/health", methods=["GET"])
def health():
    return jsonify(ok=True, ts=datetime.utcnow().isoformat() + "Z"), 200

@app.route("/diagnostics", methods=["GET"])
def diagnostics():
    flags = {
        "has_backend_bearer": bool(APP_BACKEND_BEARER),
        "has_openai": bool(OPENAI_API_KEY),
        "has_aws_keys": bool(os.getenv("AWS_ACCESS_KEY_ID") and os.getenv("AWS_SECRET_ACCESS_KEY")),
        "use_s3_cache": False,  # change if you add caching
        "aws_region": AWS_REGION,
        "polly_voice": POLLY_VOICE,
        "polly_format": "mp3",
        "polly_engine": POLLY_ENGINE,
        "tts_provider_env": "polly" if os.getenv("AWS_ACCESS_KEY_ID") else ("openai" if OPENAI_API_KEY else "none"),
        "tts_provider_effective": "polly" if os.getenv("AWS_ACCESS_KEY_ID") else ("openai" if OPENAI_API_KEY else "none"),
    }
    return jsonify(ok=True, flags=flags), 200

# -----------------------
# Chat (stub) – replace with your real logic
# iOS client can hit /ask or /api/chat (legacy)
# -----------------------
def _extract_user_text(body: dict) -> str:
    # Modern shape: {"messages":[{"role":"user","content":"..."}, ...]}
    if "messages" in body and isinstance(body["messages"], list):
        last = body["messages"][-1]
        if isinstance(last, dict):
            return (last.get("content") or "").strip()

    # Legacy aliases (accept many shapes)
    for k in ["prompt","user_text","text","message","query","q","input","userText","content"]:
        if k in body and isinstance(body[k], str) and body[k].strip():
            return body[k].strip()
    return ""

@app.route("/ask", methods=["POST"])
def ask():
    if not _auth_ok(request):
        return jsonify(error="unauthorized"), 401
    try:
        body = request.get_json(force=True, silent=True) or {}
        user_text = _extract_user_text(body)
        if not user_text:
            return jsonify(error="empty_user_text"), 400

        # TODO: replace with your actual LLM call; this is a demo echo
        reply = f"You said: {user_text}"
        return jsonify(reply=reply), 200
    except Exception as e:
        app.logger.exception("ask failed")
        return jsonify(error="server_error", detail=str(e)), 500

# Legacy /api/chat – accept many payloads
@app.route("/api/chat", methods=["POST", "GET"])
def chat_legacy():
    if not _auth_ok(request):
        return jsonify(error="unauthorized"), 401
    try:
        if request.method == "GET":
            # accept everything as query params
            user_text = ""
            for k in ["prompt","user_text","text","message","query","q","input","userText"]:
                v = request.args.get(k, "").strip()
                if v:
                    user_text = v
                    break
        else:
            body = request.get_json(force=True, silent=True) or {}
            # also accept form
            if not body and request.form:
                body = {k: request.form.get(k) for k in request.form}
            user_text = _extract_user_text(body)

        if not user_text:
            return jsonify(error="empty_user_text"), 400

        reply = f"You said: {user_text}"
        return jsonify(reply=reply), 200
    except Exception as e:
        app.logger.exception("legacy chat failed")
        return jsonify(error="server_error", detail=str(e)), 500

# -----------------------
# TTS: /speak
# -----------------------
def _polly_tts(text: str) -> bytes:
    if not boto3 or not (os.getenv("AWS_ACCESS_KEY_ID") and os.getenv("AWS_SECRET_ACCESS_KEY")):
        raise RuntimeError("polly_not_configured")
    client = boto3.client("polly", region_name=AWS_REGION)
    args = dict(Text=text, OutputFormat="mp3", VoiceId=POLLY_VOICE)
    # Engine only if set (avoid errors with unsupported voices)
    if POLLY_ENGINE:
        args["Engine"] = POLLY_ENGINE
    out = client.synthesize_speech(**args)
    stream = out.get("AudioStream")
    if not stream:
        raise RuntimeError("no_audio_stream")
    return stream.read()

def _openai_tts(text: str) -> bytes:
    if not OPENAI_API_KEY or not OpenAI:
        raise RuntimeError("openai_not_configured")
    client = OpenAI(api_key=OPENAI_API_KEY)
    # Choose a model/voice your account supports
    res = client.audio.speech.create(
        model="gpt-4o-mini-tts",
        voice="alloy",
        input=text,
        format="mp3",
    )
    return res.read()

@app.route("/speak", methods=["POST"])
def speak():
    if not _auth_ok(request):
        return jsonify(error="unauthorized"), 401
    try:
        data = request.get_json(force=True, silent=True) or {}
        text = (data.get("text") or "").strip()
        if not text:
            return jsonify(error="missing_text"), 400

        # Try Polly first if AWS credentials exist; else try OpenAI
        audio_bytes = None
        try:
            audio_bytes = _polly_tts(text)
        except Exception as e:
            app.logger.warning(f"Polly TTS unavailable: {e}")
            try:
                audio_bytes = _openai_tts(text)
            except Exception as e2:
                app.logger.exception("TTS failed")
                return jsonify(error="tts_failed", detail=str(e2)), 500

        return Response(audio_bytes, status=200, mimetype="audio/mpeg",
                        headers={"Cache-Control": "no-store"})
    except Exception as e:
        app.logger.exception("speak endpoint error")
        return jsonify(error="server_error", detail=str(e)), 500

# -----------------------
# Entry point (gunicorn uses app:app per render.yaml)
# -----------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")), debug=True)
