# =====================================
# File: app.py  (Render-ready Flask backend for Jarvis)
# - Auth via APP_BACKEND_BEARER
# - /health           : Render health check
# - /diagnostics      : Flags for iOS DiagnosticsView
# - /ask              : modern chat endpoint (demo echo; replace with LLM)
# - /api/chat         : legacy-compatible chat endpoint
# - /speak            : TTS (Polly -> OpenAI fallback), returns audio/mpeg
# - /history          : sessions list with preview + preview_html (highlight)
# - Minimal SQLAlchemy models for sessions/messages (sqlite or Postgres)
# =====================================
import os
import json
from datetime import datetime
from typing import Optional, Tuple

from flask import Flask, jsonify, request, Response
from flask_sqlalchemy import SQLAlchemy

# Optional deps: boto3/OpenAI for TTS (gracefully degrade if missing)
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

# ---------------------------------
# App / DB setup
# ---------------------------------
app = Flask(__name__)

# Database URL (Render Postgres or local sqlite as fallback)
DATABASE_URL = os.getenv("DATABASE_URL", "").replace("postgres://", "postgresql://")
if not DATABASE_URL:
    DATABASE_URL = "sqlite:///jarvis.db"
app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app)

# ---------------------------------
# Environment / Config
# ---------------------------------
APP_BACKEND_BEARER = os.getenv("APP_BACKEND_BEARER", "")  # matches render.yaml
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
POLLY_VOICE = os.getenv("POLLY_VOICE", "Matthew")
POLLY_ENGINE = os.getenv("POLLY_ENGINE", "standard")  # set to "neural" only if supported
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

def _auth_ok(req) -> bool:
    if not APP_BACKEND_BEARER:
        return True
    return req.headers.get("Authorization", "") == f"Bearer {APP_BACKEND_BEARER}"

def require_bearer(fn):
    def wrapper(*args, **kwargs):
        if not _auth_ok(request):
            return jsonify(error="unauthorized"), 401
        return fn(*args, **kwargs)
    wrapper.__name__ = fn.__name__
    return wrapper

# ---------------------------------
# Minimal models (User/Session/Message)
# ---------------------------------
class User(db.Model):
    __tablename__ = "users"
    id   = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)

class ChatSession(db.Model):
    __tablename__ = "chat_sessions"
    id         = db.Column(db.Integer, primary_key=True)
    user_id    = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    title      = db.Column(db.String(255), nullable=False, default="New chat")
    archived   = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

class ChatMessage(db.Model):
    __tablename__ = "chat_messages"
    id         = db.Column(db.Integer, primary_key=True)
    session_id = db.Column(db.Integer, db.ForeignKey("chat_sessions.id"), nullable=False)
    role       = db.Column(db.String(32), nullable=False)  # "user" | "assistant" | "system"
    content    = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

# Create tables on boot if needed (okay for hobby deployments)
with app.app_context():
    db.create_all()

# Very small “current user” shim for demo; replace with auth as needed
def current_user() -> User:
    u = User.query.first()
    if not u:
        u = User(name="demo")
        db.session.add(u)
        db.session.commit()
    return u

# Inject request.user when we need it
def require_user(fn):
    def wrapper(*args, **kwargs):
        request.user = current_user()  # type: ignore[attr-defined]
        return fn(*args, **kwargs)
    wrapper.__name__ = fn.__name__
    return wrapper

# ---------------------------------
# Health / Diagnostics
# ---------------------------------
@app.get("/health")
def health():
    return jsonify(ok=True, ts=datetime.utcnow().isoformat() + "Z"), 200

@app.get("/diagnostics")
@require_bearer
def diagnostics():
    flags = {
        "has_backend_bearer": bool(APP_BACKEND_BEARER),
        "has_openai": bool(OPENAI_API_KEY),
        "has_aws_keys": bool(os.getenv("AWS_ACCESS_KEY_ID") and os.getenv("AWS_SECRET_ACCESS_KEY")),
        "use_s3_cache": False,
        "aws_region": AWS_REGION,
        "polly_voice": POLLY_VOICE,
        "polly_format": "mp3",
        "polly_engine": POLLY_ENGINE,
        "tts_provider_env": "polly" if os.getenv("AWS_ACCESS_KEY_ID") else ("openai" if OPENAI_API_KEY else "none"),
        "tts_provider_effective": "polly" if os.getenv("AWS_ACCESS_KEY_ID") else ("openai" if OPENAI_API_KEY else "none"),
    }
    return jsonify(ok=True, flags=flags), 200

# ---------------------------------
# Chat: modern + legacy
# ---------------------------------
def _extract_user_text(body: dict) -> str:
    if "messages" in body and isinstance(body["messages"], list):
        last = body["messages"][-1]
        if isinstance(last, dict):
            return (last.get("content") or "").strip()
    for k in ["prompt","user_text","text","message","query","q","input","userText","content"]:
        v = body.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ""

@app.post("/ask")
@require_bearer
def ask():
    try:
        body = request.get_json(force=True, silent=True) or {}
        user_text = _extract_user_text(body)
        if not user_text:
            return jsonify(error="empty_user_text"), 400

        # TODO: Replace with your real LLM call. For now: echo.
        reply = f"You said: {user_text}"

        # Persist a minimal session/message so /history has data
        u = current_user()
        sess = ChatSession(user_id=u.id, title=user_text[:40] or "New chat")
        db.session.add(sess); db.session.commit()
        db.session.add(ChatMessage(session_id=sess.id, role="user", content=user_text))
        db.session.add(ChatMessage(session_id=sess.id, role="assistant", content=reply))
        db.session.commit()

        return jsonify(reply=reply), 200
    except Exception as e:
        app.logger.exception("ask failed")
        return jsonify(error="server_error", detail=str(e)), 500

@app.route("/api/chat", methods=["POST", "GET"])
@require_bearer
def chat_legacy():
    try:
        if request.method == "GET":
            user_text = ""
            for k in ["prompt","user_text","text","message","query","q","input","userText"]:
                v = request.args.get(k, "").strip()
                if v:
                    user_text = v
                    break
        else:
            body = request.get_json(force=True, silent=True) or {}
            if not body and request.form:
                body = {k: request.form.get(k) for k in request.form}
            user_text = _extract_user_text(body)

        if not user_text:
            return jsonify(error="empty_user_text"), 400

        reply = f"You said: {user_text}"

        # Persist for history
        u = current_user()
        sess = ChatSession(user_id=u.id, title=user_text[:40] or "New chat")
        db.session.add(sess); db.session.commit()
        db.session.add(ChatMessage(session_id=sess.id, role="user", content=user_text))
        db.session.add(ChatMessage(session_id=sess.id, role="assistant", content=reply))
        db.session.commit()

        return jsonify(reply=reply), 200
    except Exception as e:
        app.logger.exception("legacy chat failed")
        return jsonify(error="server_error", detail=str(e)), 500

# ---------------------------------
# TTS: Polly -> OpenAI fallback
# ---------------------------------
def _polly_tts(text: str) -> bytes:
    if not boto3 or not (os.getenv("AWS_ACCESS_KEY_ID") and os.getenv("AWS_SECRET_ACCESS_KEY")):
        raise RuntimeError("polly_not_configured")
    client = boto3.client("polly", region_name=AWS_REGION)
    args = dict(Text=text, OutputFormat="mp3", VoiceId=POLLY_VOICE)
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
    res = client.audio.speech.create(
        model="gpt-4o-mini-tts",
        voice="alloy",
        input=text,
        format="mp3",
    )
    return res.read()

@app.post("/speak")
@require_bearer
def speak():
    try:
        data = request.get_json(force=True, silent=True) or {}
        text = (data.get("text") or "").strip()
        if not text:
            return jsonify(error="missing_text"), 400

        audio_bytes = None
        try:
            audio_bytes = _polly_tts(text)
        except Exception as e:
            app.logger.warning(f"Polly unavailable: {e}")
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

# ---------------------------------
# History: sessions list with preview_html highlight
# ---------------------------------
@app.get("/history")
@require_bearer
@require_user
def list_sessions():
    u = request.user  # type: ignore[attr-defined]
    page = max(int(request.args.get("page", 1)), 1)
    limit = max(min(int(request.args.get("limit", 25)), 100), 1)
    q = (request.args.get("q") or "").strip()

    def highlight_snippet(text: str, query: str, width: int = 140) -> Tuple[str, str]:
        if not query:
            snip = text[:width]
            return snip, snip
        low = text.lower()
        ql = query.lower()
        i = low.find(ql)
        if i < 0:
            snip = text[:width]
            return snip, snip
        start = max(0, i - 40)
        end = min(len(text), i + len(query) + 40)
        snip = text[start:end]
        plain = ("…" if start > 0 else "") + snip + ("…" if end < len(text) else "")
        # Safely highlight the original case of the match range
        match = text[i:i+len(query)]
        html = plain.replace(match, f"<mark>{match}</mark>", 1)
        return plain[:width], html[:width]

    base_q = ChatSession.query.filter_by(user_id=u.id, archived=False)
    if q:
        from sqlalchemy import or_
        base_q = (base_q.join(ChatMessage, ChatMessage.session_id == ChatSession.id)
                  .filter(or_(ChatSession.title.ilike(f"%{q}%"),
                              ChatMessage.content.ilike(f"%{q}%")))
                  .distinct())

    base_q = base_q.order_by(ChatSession.created_at.desc())
    total = base_q.count()
    items = base_q.offset((page-1)*limit).limit(limit).all()

    out = []
    for sess in items:
        last = (ChatMessage.query
                .filter_by(session_id=sess.id)
                .order_by(ChatMessage.created_at.desc())
                .first())
        preview = last.content if last else ""
        plain, html = highlight_snippet(preview, q)
        out.append({
            "id": sess.id,
            "title": sess.title,
            "created_at": sess.created_at.isoformat(),
            "preview": plain,
            "preview_html": html if q else None
        })
    has_more = (page * limit) < total
    return jsonify({"items": out, "page": page, "has_more": has_more})

# ---------------------------------
# Entry (Render uses gunicorn: web -> app:app)
# ---------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")), debug=True)
