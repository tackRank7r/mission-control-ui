# =====================================
# File: app.py  (Render-ready Flask backend for Jarvis)
# - Auth via APP_BACKEND_BEARER
# - /health, /diagnostics
# - /ask (demo echo), /api/chat (legacy)
# - /speak : TTS (Polly → OpenAI fallback), returns audio/mpeg
# - /history : sessions list with preview + preview_html
# =====================================
import os
from datetime import datetime
from typing import Tuple

from flask import Flask, jsonify, request, Response
from flask_sqlalchemy import SQLAlchemy

# Optional deps—installed per requirements.txt
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

# -------- DB --------
DATABASE_URL = os.getenv("DATABASE_URL", "").replace("postgres://", "postgresql://")
if not DATABASE_URL:
    DATABASE_URL = "sqlite:///jarvis.db"
app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
db = SQLAlchemy(app)

# -------- Env / Auth --------
APP_BACKEND_BEARER = os.getenv("APP_BACKEND_BEARER", "")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
POLLY_VOICE = os.getenv("POLLY_VOICE", "Matthew")
POLLY_ENGINE = os.getenv("POLLY_ENGINE", "standard")  # use "neural" only if supported
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

def _auth_ok(req) -> bool:
    if not APP_BACKEND_BEARER:
        return True
    return req.headers.get("Authorization", "") == f"Bearer {APP_BACKEND_BEARER}"

def require_bearer(fn):
    def wrapper(*a, **kw):
        if not _auth_ok(request):
            return jsonify(error="unauthorized"), 401
        return fn(*a, **kw)
    wrapper.__name__ = fn.__name__
    return wrapper

# -------- Models --------
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

with app.app_context():
    db.create_all()

def current_user() -> User:
    u = User.query.first()
    if not u:
        u = User(name="demo")
        db.session.add(u)
        db.session.commit()
    return u

def require_user(fn):
    def wrapper(*a, **kw):
        request.user = current_user()  # type: ignore[attr-defined]
        return fn(*a, **kw)
    wrapper.__name__ = fn.__name__
    return wrapper

# -------- Health / Diagnostics --------
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

# -------- Chat (modern + legacy) --------
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

        # TODO: replace with real LLM call
        reply = f"You said: {user_text}"

        # persist minimal session/messages so /history works
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

# -------- TTS (Polly → OpenAI fallback) --------
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
    """
    Works with the modern OpenAI Python SDK.
    No 'format' param here; SDK returns an object with .read() for bytes.
    Try gpt-4o-mini-tts, then fall back to tts-1.
    """
    if not OPENAI_API_KEY or not OpenAI:
        raise RuntimeError("openai_not_configured")
    client = OpenAI(api_key=OPENAI_API_KEY)

    # Try streaming API (fast path)
    try:
        with client.audio.speech.with_streaming_response.create(
            model="gpt-4o-mini-tts",
            voice="alloy",
            input=text,
        ) as resp:
            return resp.read()
    except Exception:
        pass

    # Fallback non-streaming
    try:
        res = client.audio.speech.create(
            model="gpt-4o-mini-tts",
            voice="alloy",
            input=text,
        )
        return res.read()
    except Exception:
        # Last resort: older model name
        res = client.audio.speech.create(
            model="tts-1",
            voice="alloy",
            input=text,
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

# -------- History (with preview_html highlight) --------
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

# -------- Entry --------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")), debug=True)
