# =====================================
# File: app.py  (Render-ready Flask backend for Jarvis)
# Purpose:
# - Auth via APP_BACKEND_BEARER
# - /health, /diagnostics
# - /ask       : OpenAI Jarvis chat (+ Twilio call trigger on READY_TO_CALL)
# - /api/chat  : legacy chat, now also OpenAI-backed
# - /speak     : TTS (Polly → OpenAI fallback), returns audio/mpeg
# - /history   : sessions list with preview + preview_html
# - /n8n/*     : n8n integration endpoints for call management
# - /call/*    : Call task management
# =====================================

import os
import re
import uuid
import json
import traceback
import hashlib
from datetime import datetime, timezone, timedelta
from typing import Tuple, Optional
from functools import wraps

import httpx

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

# Twilio is optional; we only use it when properly configured.
try:
    from twilio.rest import Client as TwilioClient
    from twilio.twiml.voice_response import VoiceResponse, Gather
except Exception:
    TwilioClient = None
    VoiceResponse = None
    Gather = None

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
POLLY_ENGINE = os.getenv("POLLY_ENGINE", "standard")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

# Twilio config
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_FROM_NUMBER = os.getenv("TWILIO_FROM_NUMBER", os.getenv("TWILIO_PHONE_NUMBER", ""))
TWILIO_VOICE_URL = os.getenv("TWILIO_VOICE_URL", "")

# ElevenLabs config
ELEVENLABS_API_KEY = os.getenv("ELEVENLABS_API_KEY", "")
ELEVENLABS_VOICE_ID = os.getenv("ELEVENLABS_VOICE_ID", "21m00Tcm4TlvDq8ikWAM")  # Default: Rachel
ELEVENLABS_AGENT_ID = os.getenv("ELEVENLABS_AGENT_ID", "")
ELEVENLABS_PHONE_NUMBER_ID = os.getenv("ELEVENLABS_PHONE_NUMBER_ID", "")

# Hybrid routing cost limits
COST_PER_MIN_ELEVENLABS_AGENT = 10   # $0.10/min in cents
COST_PER_MIN_TWILIO_CUSTOM = 2       # $0.02/min in cents
WEEKLY_COST_LIMIT_CENTS = 2000       # $20/week
WEEKLY_CALLS_PER_USER = 4

# n8n webhook URLs
N8N_BASE_URL = os.getenv("N8N_BASE_URL", "https://fdaf.app.n8n.cloud")
N8N_ERROR_WEBHOOK = os.getenv("N8N_ERROR_WEBHOOK", "")


def _auth_ok(req) -> bool:
    if not APP_BACKEND_BEARER:
        return True
    return req.headers.get("Authorization", "") == f"Bearer {APP_BACKEND_BEARER}"


def require_bearer(fn):
    @wraps(fn)
    def wrapper(*a, **kw):
        if not _auth_ok(request):
            return jsonify(error="unauthorized"), 401
        return fn(*a, **kw)
    return wrapper


# -------- Models --------
class User(db.Model):
    __tablename__ = "users"
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    email = db.Column(db.String(255), unique=True, nullable=True)
    is_admin = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


class ChatSession(db.Model):
    __tablename__ = "chat_sessions"
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    title = db.Column(db.String(255), nullable=False, default="New chat")
    archived = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)


class ChatMessage(db.Model):
    __tablename__ = "chat_messages"
    id = db.Column(db.Integer, primary_key=True)
    session_id = db.Column(db.Integer, db.ForeignKey("chat_sessions.id"), nullable=False)
    role = db.Column(db.String(32), nullable=False)
    content = db.Column(db.Text, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)


# -------- Call Task Models --------
class CallTask(db.Model):
    """Represents a scheduled or completed phone call task"""
    __tablename__ = "call_tasks"
    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)

    # Status: draft, scheduled, in_progress, completed, failed, canceled
    status = db.Column(db.String(32), default="draft", nullable=False)

    # Target info
    target_name = db.Column(db.String(255), nullable=True)
    target_phone = db.Column(db.String(32), nullable=False)

    # Call objective and context
    objective = db.Column(db.String(64), nullable=True)  # reservation, inquiry, etc.
    context = db.Column(db.Text, nullable=True)  # JSON: constraints, preferences
    call_script = db.Column(db.Text, nullable=True)  # What the AI should say/ask

    # Scheduling
    scheduled_at = db.Column(db.DateTime, nullable=True)

    # Twilio call tracking
    twilio_call_sid = db.Column(db.String(64), nullable=True)

    # Results
    result_status = db.Column(db.String(32), nullable=True)  # success, no_answer, busy, failed
    result_summary = db.Column(db.Text, nullable=True)
    result_data = db.Column(db.Text, nullable=True)  # JSON: extracted info
    transcript = db.Column(db.Text, nullable=True)

    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    started_at = db.Column(db.DateTime, nullable=True)
    completed_at = db.Column(db.DateTime, nullable=True)

    # Routing
    routing_type = db.Column(db.String(32), nullable=True)  # "elevenlabs_agent" or "twilio_custom"

    # Cost tracking
    duration_seconds = db.Column(db.Integer, nullable=True)
    cost_cents = db.Column(db.Integer, nullable=True)


class CallEvent(db.Model):
    """Audit trail for call task state changes"""
    __tablename__ = "call_events"
    id = db.Column(db.Integer, primary_key=True)
    call_task_id = db.Column(db.String(36), db.ForeignKey("call_tasks.id"), nullable=False)

    event_type = db.Column(db.String(64), nullable=False)  # created, scheduled, started, turn, completed, error
    timestamp = db.Column(db.DateTime, default=datetime.utcnow, nullable=False)

    # Event details (JSON)
    payload = db.Column(db.Text, nullable=True)

    # Error tracking
    error_message = db.Column(db.Text, nullable=True)
    error_stack = db.Column(db.Text, nullable=True)


class N8nLog(db.Model):
    """Centralized logging for n8n workflow errors"""
    __tablename__ = "n8n_logs"
    id = db.Column(db.Integer, primary_key=True)

    workflow_name = db.Column(db.String(128), nullable=False)
    node_name = db.Column(db.String(128), nullable=True)
    execution_id = db.Column(db.String(64), nullable=True)

    level = db.Column(db.String(16), default="error")  # debug, info, warn, error
    message = db.Column(db.Text, nullable=False)
    context = db.Column(db.Text, nullable=True)  # JSON: additional context

    timestamp = db.Column(db.DateTime, default=datetime.utcnow)

    # Link to call task if applicable
    call_task_id = db.Column(db.String(36), nullable=True)


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
    @wraps(fn)
    def wrapper(*a, **kw):
        request.user = current_user()
        return fn(*a, **kw)
    return wrapper


def log_call_event(call_task_id: str, event_type: str, payload: dict = None, error: str = None, stack: str = None):
    """Helper to log call events"""
    event = CallEvent(
        call_task_id=call_task_id,
        event_type=event_type,
        payload=json.dumps(payload) if payload else None,
        error_message=error,
        error_stack=stack
    )
    db.session.add(event)
    db.session.commit()
    return event


def log_n8n_error(workflow: str, message: str, node: str = None, execution_id: str = None,
                  context: dict = None, call_task_id: str = None, level: str = "error"):
    """Helper to log n8n workflow errors"""
    log = N8nLog(
        workflow_name=workflow,
        node_name=node,
        execution_id=execution_id,
        level=level,
        message=message,
        context=json.dumps(context) if context else None,
        call_task_id=call_task_id
    )
    db.session.add(log)
    db.session.commit()
    return log


# -------- Hybrid Routing Helpers --------

def _get_week_start() -> datetime:
    """Return Monday 00:00 UTC of the current week."""
    now = datetime.utcnow()
    monday = now - timedelta(days=now.weekday())
    return monday.replace(hour=0, minute=0, second=0, microsecond=0)


def _weekly_total_cost_cents() -> int:
    """Sum cost_cents for all calls created this week."""
    week_start = _get_week_start()
    from sqlalchemy import func
    result = db.session.query(func.coalesce(func.sum(CallTask.cost_cents), 0)).filter(
        CallTask.created_at >= week_start,
        CallTask.cost_cents.isnot(None)
    ).scalar()
    return int(result)


def _weekly_user_call_count(user_id: int) -> int:
    """Count calls for a user this week."""
    week_start = _get_week_start()
    return CallTask.query.filter(
        CallTask.user_id == user_id,
        CallTask.created_at >= week_start
    ).count()


def _should_use_elevenlabs_agent(user_id: int) -> bool:
    """Decide whether to route via ElevenLabs Agents (True) or Twilio custom (False)."""
    if not ELEVENLABS_AGENT_ID or not ELEVENLABS_PHONE_NUMBER_ID:
        return False

    user = User.query.get(user_id)
    if user and user.is_admin:
        return True

    if _weekly_total_cost_cents() >= WEEKLY_COST_LIMIT_CENTS:
        return False
    if _weekly_user_call_count(user_id) >= WEEKLY_CALLS_PER_USER:
        return False

    return True


def _initiate_elevenlabs_agent_call(call: 'CallTask') -> dict:
    """Initiate outbound call via ElevenLabs Conversational AI Agents API."""
    url = "https://api.elevenlabs.io/v1/convai/twilio/outbound-call"
    headers = {"xi-api-key": ELEVENLABS_API_KEY, "Content-Type": "application/json"}
    payload = {
        "agent_id": ELEVENLABS_AGENT_ID,
        "agent_phone_number_id": ELEVENLABS_PHONE_NUMBER_ID,
        "to_number": call.target_phone,
        "conversation_initiation_client_data": {
            "dynamic_variables": {
                "target_name": call.target_name or "",
                "objective": call.objective or "",
                "context": call.context or "",
                "call_script": call.call_script or ""
            }
        }
    }
    with httpx.Client(timeout=30.0) as client:
        resp = client.post(url, json=payload, headers=headers)
        resp.raise_for_status()
        return resp.json()


# -------- Health / Diagnostics --------
@app.get("/health")
def health():
    return jsonify(ok=True, ts=datetime.utcnow().isoformat() + "Z"), 200


@app.get("/diagnostics")
@require_bearer
def diagnostics():
    # Count pending calls
    pending_calls = CallTask.query.filter(CallTask.status.in_(["scheduled", "in_progress"])).count()
    recent_errors = N8nLog.query.filter_by(level="error").order_by(N8nLog.timestamp.desc()).limit(5).all()

    flags = {
        "has_backend_bearer": bool(APP_BACKEND_BEARER),
        "has_openai": bool(OPENAI_API_KEY),
        "has_aws_keys": bool(os.getenv("AWS_ACCESS_KEY_ID") and os.getenv("AWS_SECRET_ACCESS_KEY")),
        "aws_region": AWS_REGION,
        "polly_voice": POLLY_VOICE,
        "polly_engine": POLLY_ENGINE,
        "has_twilio_keys": bool(TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN),
        "has_twilio_from_number": bool(TWILIO_FROM_NUMBER),
        "has_twilio_voice_url": bool(TWILIO_VOICE_URL),
        "has_elevenlabs": bool(ELEVENLABS_API_KEY),
        "elevenlabs_voice_id": ELEVENLABS_VOICE_ID,
        "n8n_base_url": N8N_BASE_URL,
        "pending_calls": pending_calls,
        "recent_errors": [{"workflow": e.workflow_name, "message": e.message[:100], "ts": e.timestamp.isoformat()} for e in recent_errors]
    }
    return jsonify(ok=True, flags=flags), 200


# ========================================
# n8n Integration Endpoints
# ========================================

@app.post("/n8n/log")
def n8n_log():
    """
    Endpoint for n8n to log errors and events.
    POST body: {
        "workflow": "voice-call-handler",
        "node": "OpenAI Node",
        "execution_id": "abc123",
        "level": "error",
        "message": "API call failed",
        "context": { ... },
        "call_task_id": "uuid"
    }
    """
    try:
        data = request.get_json(force=True, silent=True) or {}

        log = log_n8n_error(
            workflow=data.get("workflow", "unknown"),
            message=data.get("message", "No message provided"),
            node=data.get("node"),
            execution_id=data.get("execution_id"),
            context=data.get("context"),
            call_task_id=data.get("call_task_id"),
            level=data.get("level", "error")
        )

        return jsonify(ok=True, log_id=log.id), 200
    except Exception as e:
        app.logger.exception("n8n log failed")
        return jsonify(error=str(e)), 500


@app.get("/n8n/logs")
@require_bearer
def n8n_logs_list():
    """Get recent n8n logs for debugging"""
    limit = min(int(request.args.get("limit", 50)), 200)
    level = request.args.get("level")  # filter by level
    workflow = request.args.get("workflow")  # filter by workflow

    query = N8nLog.query
    if level:
        query = query.filter_by(level=level)
    if workflow:
        query = query.filter_by(workflow_name=workflow)

    logs = query.order_by(N8nLog.timestamp.desc()).limit(limit).all()

    return jsonify({
        "logs": [{
            "id": log.id,
            "workflow": log.workflow_name,
            "node": log.node_name,
            "execution_id": log.execution_id,
            "level": log.level,
            "message": log.message,
            "context": json.loads(log.context) if log.context else None,
            "call_task_id": log.call_task_id,
            "timestamp": log.timestamp.isoformat()
        } for log in logs]
    })


@app.get("/n8n/pending-calls")
def n8n_pending_calls():
    """
    Get calls that are scheduled and ready to execute.
    n8n polls this endpoint to find calls to initiate.
    """
    now = datetime.utcnow()

    # Find scheduled calls where scheduled_at <= now
    pending = CallTask.query.filter(
        CallTask.status == "scheduled",
        CallTask.scheduled_at <= now
    ).order_by(CallTask.scheduled_at.asc()).limit(10).all()

    return jsonify({
        "calls": [{
            "id": call.id,
            "target_name": call.target_name,
            "target_phone": call.target_phone,
            "objective": call.objective,
            "context": json.loads(call.context) if call.context else None,
            "call_script": call.call_script,
            "scheduled_at": call.scheduled_at.isoformat() if call.scheduled_at else None
        } for call in pending]
    })


@app.post("/n8n/call/<call_id>/start")
def n8n_call_start(call_id):
    """
    Mark a call as started and record Twilio call SID.
    Called by n8n when initiating the Twilio call.
    """
    try:
        call = CallTask.query.get(call_id)
        if not call:
            return jsonify(error="call_not_found"), 404

        data = request.get_json(force=True, silent=True) or {}

        call.status = "in_progress"
        call.started_at = datetime.utcnow()
        call.twilio_call_sid = data.get("twilio_call_sid")
        db.session.commit()

        log_call_event(call_id, "started", {
            "twilio_call_sid": call.twilio_call_sid
        })

        return jsonify(ok=True, status=call.status)
    except Exception as e:
        log_n8n_error("call-start", str(e), call_task_id=call_id, context={"error": traceback.format_exc()})
        return jsonify(error=str(e)), 500


@app.post("/n8n/call/<call_id>/turn")
def n8n_call_turn(call_id):
    """
    Log a conversation turn during the call.
    POST body: {
        "speaker": "ai" | "human",
        "text": "...",
        "timestamp": "ISO datetime"
    }
    """
    try:
        call = CallTask.query.get(call_id)
        if not call:
            return jsonify(error="call_not_found"), 404

        data = request.get_json(force=True, silent=True) or {}

        log_call_event(call_id, "turn", {
            "speaker": data.get("speaker"),
            "text": data.get("text"),
            "turn_timestamp": data.get("timestamp")
        })

        # Append to transcript
        turn_text = f"[{data.get('speaker', 'unknown')}]: {data.get('text', '')}\n"
        call.transcript = (call.transcript or "") + turn_text
        db.session.commit()

        return jsonify(ok=True)
    except Exception as e:
        log_n8n_error("call-turn", str(e), call_task_id=call_id)
        return jsonify(error=str(e)), 500


@app.post("/n8n/call/<call_id>/complete")
def n8n_call_complete(call_id):
    """
    Mark a call as completed with results.
    POST body: {
        "result_status": "success" | "no_answer" | "busy" | "failed",
        "result_summary": "Reservation confirmed for 7pm",
        "result_data": { "reservation_time": "19:00", ... },
        "duration_seconds": 120
    }
    """
    try:
        call = CallTask.query.get(call_id)
        if not call:
            return jsonify(error="call_not_found"), 404

        data = request.get_json(force=True, silent=True) or {}

        call.status = "completed"
        call.completed_at = datetime.utcnow()
        call.result_status = data.get("result_status", "completed")
        call.result_summary = data.get("result_summary")
        call.result_data = json.dumps(data.get("result_data")) if data.get("result_data") else None
        call.duration_seconds = data.get("duration_seconds")

        # Estimate cost (Twilio ~$0.02/min)
        if call.duration_seconds:
            rate = COST_PER_MIN_ELEVENLABS_AGENT if call.routing_type == "elevenlabs_agent" else COST_PER_MIN_TWILIO_CUSTOM
            call.cost_cents = max(1, int(call.duration_seconds / 60 * rate))

        db.session.commit()

        log_call_event(call_id, "completed", {
            "result_status": call.result_status,
            "result_summary": call.result_summary,
            "duration_seconds": call.duration_seconds
        })

        return jsonify(ok=True, status=call.status, result_status=call.result_status)
    except Exception as e:
        log_n8n_error("call-complete", str(e), call_task_id=call_id, context={"error": traceback.format_exc()})
        return jsonify(error=str(e)), 500


@app.get("/n8n/call/lookup")
def n8n_call_lookup():
    """
    Look up a call task by Twilio Call SID.
    Used by n8n workflows to find the call task during voice handling.
    """
    try:
        twilio_call_sid = request.args.get("twilio_call_sid")
        if not twilio_call_sid:
            return jsonify(error="twilio_call_sid required"), 400

        call = CallTask.query.filter_by(twilio_call_sid=twilio_call_sid).first()
        if not call:
            return jsonify(call_task=None), 200

        # Generate initial TwiML greeting based on call script
        greeting = "Hello, this is Jarvis calling. How can I help you today?"
        if call.call_script:
            greeting = call.call_script.split("\n")[0] if "\n" in call.call_script else call.call_script

        twiml = f'''<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Gather input="speech" action="{request.url_root}twilio/voice/respond" speechTimeout="auto" language="en-US">
        <Say voice="Polly.Matthew">{greeting}</Say>
    </Gather>
    <Say voice="Polly.Matthew">I didn't hear anything. Goodbye.</Say>
    <Hangup/>
</Response>'''

        return jsonify({
            "call_task": {
                "id": call.id,
                "status": call.status,
                "target_name": call.target_name,
                "target_phone": call.target_phone,
                "objective": call.objective,
                "context": json.loads(call.context) if call.context else None,
                "call_script": call.call_script,
                "transcript": call.transcript
            },
            "twiml": twiml
        })
    except Exception as e:
        log_n8n_error("call-lookup", str(e), context={"twilio_call_sid": request.args.get("twilio_call_sid")})
        return jsonify(error=str(e)), 500


@app.get("/n8n/call/<call_id>")
def n8n_get_call(call_id):
    """
    Get call task details for n8n workflows.
    Used by post-call summary workflow.
    """
    try:
        call = CallTask.query.get(call_id)
        if not call:
            return jsonify(error="call_not_found"), 404

        return jsonify({
            "call_task": {
                "id": call.id,
                "status": call.status,
                "target_name": call.target_name,
                "target_phone": call.target_phone,
                "objective": call.objective,
                "context": json.loads(call.context) if call.context else None,
                "call_script": call.call_script,
                "transcript": call.transcript,
                "result_status": call.result_status,
                "result_summary": call.result_summary,
                "duration_seconds": call.duration_seconds
            }
        })
    except Exception as e:
        return jsonify(error=str(e)), 500


@app.post("/n8n/call/<call_id>/error")
def n8n_call_error(call_id):
    """
    Mark a call as failed with error details.
    POST body: {
        "error_message": "Twilio API timeout",
        "error_code": "TIMEOUT",
        "should_retry": true
    }
    """
    try:
        call = CallTask.query.get(call_id)
        if not call:
            return jsonify(error="call_not_found"), 404

        data = request.get_json(force=True, silent=True) or {}

        call.status = "failed"
        call.completed_at = datetime.utcnow()
        call.result_status = "failed"
        call.result_summary = data.get("error_message", "Unknown error")
        db.session.commit()

        log_call_event(call_id, "error", {
            "error_message": data.get("error_message"),
            "error_code": data.get("error_code")
        }, error=data.get("error_message"))

        log_n8n_error(
            "call-execution",
            data.get("error_message", "Call failed"),
            call_task_id=call_id,
            context=data
        )

        return jsonify(ok=True, status=call.status)
    except Exception as e:
        return jsonify(error=str(e)), 500


# ========================================
# Call Task Management (for iOS app)
# ========================================

@app.post("/call/schedule")
@require_bearer
@require_user
def schedule_call():
    """
    Schedule a new call task.
    POST body: {
        "target_name": "La Piazza Restaurant",
        "target_phone": "+1234567890",
        "objective": "reservation",
        "context": { "party_size": 2, "preferred_time": "7pm" },
        "call_script": "Hello, I'd like to make a reservation...",
        "scheduled_at": "2024-01-15T19:00:00Z"  // or null for immediate
    }
    """
    try:
        data = request.get_json(force=True, silent=True) or {}

        if not data.get("target_phone"):
            return jsonify(error="target_phone required"), 400

        scheduled_at = None
        if data.get("scheduled_at"):
            scheduled_at = datetime.fromisoformat(data["scheduled_at"].replace("Z", "+00:00"))
        else:
            scheduled_at = datetime.utcnow()  # Immediate

        use_agent = _should_use_elevenlabs_agent(request.user.id)

        call = CallTask(
            user_id=request.user.id,
            status="scheduled",
            target_name=data.get("target_name"),
            target_phone=data["target_phone"],
            objective=data.get("objective"),
            context=json.dumps(data.get("context")) if data.get("context") else None,
            call_script=data.get("call_script"),
            scheduled_at=scheduled_at,
            routing_type="elevenlabs_agent" if use_agent else "twilio_custom"
        )
        db.session.add(call)
        db.session.commit()

        log_call_event(call.id, "created", {
            "target_phone": call.target_phone,
            "scheduled_at": scheduled_at.isoformat(),
            "routing_type": call.routing_type
        })

        # Route via ElevenLabs Agents API (bypasses n8n/Twilio)
        if use_agent:
            try:
                result = _initiate_elevenlabs_agent_call(call)
                call.status = "in_progress"
                call.started_at = datetime.utcnow()
                call.twilio_call_sid = result.get("callSid")
                db.session.commit()
                log_call_event(call.id, "started", {
                    "routing_type": "elevenlabs_agent",
                    "conversation_id": result.get("conversation_id"),
                    "twilio_call_sid": result.get("callSid")
                })
            except Exception as agent_err:
                app.logger.warning(f"ElevenLabs Agent call failed, falling back to Twilio: {agent_err}")
                call.routing_type = "twilio_custom"
                db.session.commit()
                log_call_event(call.id, "agent_fallback", {
                    "error": str(agent_err)
                })
        # else: stays "scheduled" for n8n to pick up via /n8n/pending-calls

        return jsonify({
            "ok": True,
            "call_id": call.id,
            "status": call.status,
            "routing_type": call.routing_type,
            "scheduled_at": call.scheduled_at.isoformat()
        }), 201
    except Exception as e:
        app.logger.exception("schedule_call failed")
        return jsonify(error=str(e)), 500


@app.get("/call/<call_id>")
@require_bearer
def get_call(call_id):
    """Get call task details and status"""
    call = CallTask.query.get(call_id)
    if not call:
        return jsonify(error="call_not_found"), 404

    return jsonify({
        "id": call.id,
        "status": call.status,
        "target_name": call.target_name,
        "target_phone": call.target_phone,
        "objective": call.objective,
        "context": json.loads(call.context) if call.context else None,
        "scheduled_at": call.scheduled_at.isoformat() if call.scheduled_at else None,
        "started_at": call.started_at.isoformat() if call.started_at else None,
        "completed_at": call.completed_at.isoformat() if call.completed_at else None,
        "result_status": call.result_status,
        "result_summary": call.result_summary,
        "result_data": json.loads(call.result_data) if call.result_data else None,
        "transcript": call.transcript,
        "duration_seconds": call.duration_seconds,
        "cost_cents": call.cost_cents
    })


@app.get("/call/<call_id>/events")
@require_bearer
def get_call_events(call_id):
    """Get audit trail for a call task"""
    events = CallEvent.query.filter_by(call_task_id=call_id).order_by(CallEvent.timestamp.asc()).all()

    return jsonify({
        "events": [{
            "id": e.id,
            "event_type": e.event_type,
            "timestamp": e.timestamp.isoformat(),
            "payload": json.loads(e.payload) if e.payload else None,
            "error_message": e.error_message
        } for e in events]
    })


@app.get("/calls")
@require_bearer
@require_user
def list_calls():
    """List user's call tasks"""
    status = request.args.get("status")
    limit = min(int(request.args.get("limit", 20)), 100)

    query = CallTask.query.filter_by(user_id=request.user.id)
    if status:
        query = query.filter_by(status=status)

    calls = query.order_by(CallTask.created_at.desc()).limit(limit).all()

    return jsonify({
        "calls": [{
            "id": c.id,
            "status": c.status,
            "target_name": c.target_name,
            "target_phone": c.target_phone,
            "objective": c.objective,
            "scheduled_at": c.scheduled_at.isoformat() if c.scheduled_at else None,
            "result_status": c.result_status,
            "result_summary": c.result_summary
        } for c in calls]
    })


@app.get("/usage")
@require_bearer
@require_user
def usage_stats():
    """Get current week's usage stats for debugging."""
    week_start = _get_week_start()
    total_cost = _weekly_total_cost_cents()
    user_calls = _weekly_user_call_count(request.user.id)
    is_admin = request.user.is_admin

    # Determine current routing for this user
    if is_admin:
        current_routing = "elevenlabs_agent (admin bypass)"
    elif total_cost >= WEEKLY_COST_LIMIT_CENTS:
        current_routing = "twilio_custom (weekly cost limit reached)"
    elif user_calls >= WEEKLY_CALLS_PER_USER:
        current_routing = "twilio_custom (user call limit reached)"
    elif not ELEVENLABS_AGENT_ID:
        current_routing = "twilio_custom (agent not configured)"
    else:
        current_routing = "elevenlabs_agent"

    return jsonify({
        "week_start": week_start.isoformat(),
        "weekly_cost_cents": total_cost,
        "weekly_cost_limit_cents": WEEKLY_COST_LIMIT_CENTS,
        "user_calls_this_week": user_calls,
        "user_calls_limit": WEEKLY_CALLS_PER_USER,
        "is_admin": is_admin,
        "current_routing": current_routing,
        "agent_configured": bool(ELEVENLABS_AGENT_ID and ELEVENLABS_PHONE_NUMBER_ID)
    })


@app.post("/call/<call_id>/cancel")
@require_bearer
@require_user
def cancel_call(call_id):
    """Cancel a scheduled call"""
    call = CallTask.query.get(call_id)
    if not call:
        return jsonify(error="call_not_found"), 404

    if call.user_id != request.user.id:
        return jsonify(error="unauthorized"), 403

    if call.status not in ["draft", "scheduled"]:
        return jsonify(error="call_cannot_be_canceled", status=call.status), 400

    call.status = "canceled"
    db.session.commit()

    log_call_event(call_id, "canceled", {"previous_status": call.status})

    return jsonify(ok=True, status=call.status)


# ========================================
# Twilio Voice Webhook (TwiML responses)
# ========================================

def _add_speech_to_twiml(twiml_element, text: str, base_url: str):
    """Add speech to TwiML element - uses ElevenLabs if available, otherwise Polly."""
    if ELEVENLABS_API_KEY:
        # Generate audio with ElevenLabs and play it
        cache_key = generate_and_cache_audio(text, use_elevenlabs=True)
        if cache_key:
            twiml_element.play(f"{base_url}audio/{cache_key}")
            return
    # Fallback to Polly
    twiml_element.say(text, voice="Polly.Matthew")


@app.route("/twilio/voice", methods=["POST"])
def twilio_voice_webhook():
    """
    Main Twilio voice webhook - returns TwiML.
    This is called when a call connects.
    """
    if not VoiceResponse:
        return "TwiML not available", 500

    try:
        call_sid = request.values.get("CallSid", "")
        base_url = request.url_root

        # Find the call task by Twilio SID
        call = CallTask.query.filter_by(twilio_call_sid=call_sid).first()

        response = VoiceResponse()

        if call and call.call_script:
            # Use the prepared script
            greeting = call.call_script.split("\n")[0] if "\n" in call.call_script else call.call_script
        else:
            greeting = "Hey there! This is Tori, calling on behalf of my user. How's it going?"

        # Gather speech input
        gather = Gather(
            input="speech",
            action=f"{base_url}twilio/voice/respond",
            speech_timeout="auto",
            language="en-US"
        )

        # Use ElevenLabs if available
        if ELEVENLABS_API_KEY:
            cache_key = generate_and_cache_audio(greeting, use_elevenlabs=True)
            if cache_key:
                gather.play(f"{base_url}audio/{cache_key}")
            else:
                gather.say(greeting, voice="Polly.Matthew")
        else:
            gather.say(greeting, voice="Polly.Matthew")

        response.append(gather)

        # If no input, try again instead of hanging up
        retry_gather = Gather(
            input="speech",
            action=f"{base_url}twilio/voice/respond",
            speech_timeout="auto",
            language="en-US"
        )
        retry_msg = "Hello? Are you still there?"
        if ELEVENLABS_API_KEY:
            cache_key = generate_and_cache_audio(retry_msg, use_elevenlabs=True)
            if cache_key:
                retry_gather.play(f"{base_url}audio/{cache_key}")
            else:
                retry_gather.say(retry_msg, voice="Polly.Matthew")
        else:
            retry_gather.say(retry_msg, voice="Polly.Matthew")
        response.append(retry_gather)

        # Only hang up if they still don't respond
        _add_speech_to_twiml(response, "Okay, looks like you're busy. I'll try again later. Bye!", base_url)
        response.hangup()

        return Response(str(response), mimetype="application/xml")
    except Exception as e:
        app.logger.exception("twilio_voice_webhook error")
        log_n8n_error("twilio-voice-webhook", str(e), context={"error": traceback.format_exc()})

        response = VoiceResponse()
        response.say("Sorry, there was a technical issue. Please try again later.", voice="Polly.Matthew")
        response.hangup()
        return Response(str(response), mimetype="application/xml")


@app.route("/twilio/voice/respond", methods=["POST"])
def twilio_voice_respond():
    """
    Handle speech input from the call and generate AI response.
    """
    if not VoiceResponse:
        return "TwiML not available", 500

    try:
        speech_result = request.values.get("SpeechResult", "")
        call_sid = request.values.get("CallSid", "")

        # Find call task
        call = CallTask.query.filter_by(twilio_call_sid=call_sid).first()
        if call:
            log_call_event(call.id, "turn", {
                "speaker": "human",
                "text": speech_result
            })

        # Generate AI response using phone agent with conversation history
        if speech_result:
            ai_response = _phone_agent_chat(call, speech_result)
        else:
            ai_response = "Sorry, I didn't catch that. Could you say that again?"

        if call:
            log_call_event(call.id, "turn", {
                "speaker": "ai",
                "text": ai_response
            })

        response = VoiceResponse()
        base_url = request.url_root

        # Check for conversation end signals
        end_signals = ["goodbye", "thank you", "that's all", "bye", "have a nice day"]
        if any(signal in speech_result.lower() for signal in end_signals):
            _add_speech_to_twiml(response, ai_response, base_url)
            _add_speech_to_twiml(response, "Thank you for your time. Goodbye!", base_url)
            response.hangup()

            # Mark call as completed
            if call:
                call.status = "completed"
                call.completed_at = datetime.utcnow()
                call.result_status = "success"
                db.session.commit()
        else:
            # Continue conversation
            gather = Gather(
                input="speech",
                action=f"{base_url}twilio/voice/respond",
                speech_timeout="auto",
                language="en-US"
            )

            # Use ElevenLabs if available
            if ELEVENLABS_API_KEY:
                cache_key = generate_and_cache_audio(ai_response, use_elevenlabs=True)
                if cache_key:
                    gather.play(f"{base_url}audio/{cache_key}")
                else:
                    gather.say(ai_response, voice="Polly.Matthew")
            else:
                gather.say(ai_response, voice="Polly.Matthew")

            response.append(gather)

            # If no input, ask if they're still there
            retry_gather = Gather(
                input="speech",
                action=f"{base_url}twilio/voice/respond",
                speech_timeout="auto",
                language="en-US"
            )
            retry_msg = "Hey, are you still there?"
            if ELEVENLABS_API_KEY:
                cache_key = generate_and_cache_audio(retry_msg, use_elevenlabs=True)
                if cache_key:
                    retry_gather.play(f"{base_url}audio/{cache_key}")
                else:
                    retry_gather.say(retry_msg, voice="Polly.Matthew")
            else:
                retry_gather.say(retry_msg, voice="Polly.Matthew")
            response.append(retry_gather)

            # Only hang up after second silence
            _add_speech_to_twiml(response, "No worries, I'll let you go. Talk soon!", base_url)
            response.hangup()

        return Response(str(response), mimetype="application/xml")
    except Exception as e:
        app.logger.exception("twilio_voice_respond error")
        log_n8n_error("twilio-voice-respond", str(e), context={"speech": request.values.get("SpeechResult", "")})

        response = VoiceResponse()
        response.say("Sorry, there was a technical issue. Goodbye.", voice="Polly.Matthew")
        response.hangup()
        return Response(str(response), mimetype="application/xml")


@app.route("/twilio/status", methods=["POST"])
def twilio_status_webhook():
    """
    Twilio status callback - called when call status changes.
    Updates call task status accordingly.
    """
    try:
        call_sid = request.values.get("CallSid", "")
        call_status = request.values.get("CallStatus", "")
        duration = request.values.get("CallDuration", "0")

        call = CallTask.query.filter_by(twilio_call_sid=call_sid).first()
        if call:
            log_call_event(call.id, f"twilio_status_{call_status}", {
                "call_status": call_status,
                "duration": duration
            })

            if call_status == "completed":
                if call.status != "completed":
                    call.status = "completed"
                    call.completed_at = datetime.utcnow()
                    call.duration_seconds = int(duration) if duration else None
                    if call.duration_seconds:
                        rate = COST_PER_MIN_ELEVENLABS_AGENT if call.routing_type == "elevenlabs_agent" else COST_PER_MIN_TWILIO_CUSTOM
                        call.cost_cents = max(1, int(call.duration_seconds / 60 * rate))
                    db.session.commit()
            elif call_status in ["busy", "no-answer", "failed", "canceled"]:
                call.status = "failed"
                call.result_status = call_status.replace("-", "_")
                call.completed_at = datetime.utcnow()
                db.session.commit()

        return jsonify(ok=True)
    except Exception as e:
        app.logger.exception("twilio_status_webhook error")
        return jsonify(error=str(e)), 500


# ========================================
# Chat helpers
# ========================================

def _extract_user_text(body: dict) -> str:
    if "messages" in body and isinstance(body["messages"], list):
        last = body["messages"][-1]
        if isinstance(last, dict):
            return (last.get("content") or "").strip()
    for k in ["prompt", "user_text", "text", "message", "query", "q", "input", "userText", "content"]:
        v = body.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    return ""


PHONE_AGENT_SYSTEM_PROMPT = """You are Tori, a friendly and natural-sounding AI phone assistant calling on behalf of your user.

CONVERSATION RULES:
- Speak naturally like a real person on a phone call. Use casual, warm language.
- Keep responses to 1-3 short sentences. This is a phone call, not an essay.
- Always end with a follow-up question or next step to keep the conversation going.
- If the person answers your question, acknowledge their answer before moving on.
- If you've accomplished the call objective, wrap up politely: "Great, that's everything I needed. Thanks so much for your help!"
- Never say you're an AI unless directly asked. Just be helpful.
- Don't use bullet points, lists, or any text formatting - this is spoken audio.
- Use natural filler words occasionally: "Sure thing", "Got it", "Perfect", "Awesome".

EXAMPLES OF GOOD RESPONSES:
- "Oh that sounds great! And what time would work best for that?"
- "Perfect, I'll let them know. Is there anything else I should be aware of?"
- "Got it, thanks! One more quick question - do you have availability this weekend?"

EXAMPLES OF BAD RESPONSES (too robotic/formal):
- "I have noted your request. Is there anything else I can assist you with?"
- "Thank you for providing that information. I will process it accordingly."
"""


def _chat_llm(user_text: str) -> str:
    if not OPENAI_API_KEY or not OpenAI:
        return f"You said: {user_text}"

    try:
        client = OpenAI(api_key=OPENAI_API_KEY)

        system_prompt = (
            "You are Jarvis, a helpful assistant. Be friendly and concise. "
            "If on a phone call, speak naturally as if in a real conversation."
        )

        completion = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_text},
            ],
            temperature=0.7,
            max_tokens=150
        )

        reply = (completion.choices[0].message.content or "").strip()
        return reply if reply else "I'm not sure how to respond to that."
    except Exception as llm_err:
        app.logger.exception(f"OpenAI chat failed: {llm_err}")
        return "I'm having trouble processing that. Could you repeat?"


def _phone_agent_chat(call: 'CallTask', speech_result: str) -> str:
    """
    Generate a conversational AI response for phone calls using GPT-4o
    with full conversation history.
    """
    if not OPENAI_API_KEY or not OpenAI:
        return "Sorry, I can't process that right now."

    try:
        client = OpenAI(api_key=OPENAI_API_KEY)

        # Build system prompt with call context
        system = PHONE_AGENT_SYSTEM_PROMPT
        if call:
            system += f"\nCALL CONTEXT:"
            system += f"\n- Calling: {call.target_name or 'someone'}"
            system += f"\n- Objective: {call.objective or 'general conversation'}"
            if call.context:
                try:
                    ctx = json.loads(call.context)
                    system += f"\n- Details: {json.dumps(ctx)}"
                except Exception:
                    pass
            if call.call_script:
                system += f"\n- Script guidance: {call.call_script}"

        # Build conversation history from call events
        messages = [{"role": "system", "content": system}]

        if call:
            # Get last 10 turns to keep context window small and fast
            events = CallEvent.query.filter_by(
                call_task_id=call.id,
                event_type="turn"
            ).order_by(CallEvent.timestamp.desc()).limit(10).all()
            events.reverse()  # Put back in chronological order

            for event in events:
                try:
                    payload = json.loads(event.payload) if event.payload else {}
                    speaker = payload.get("speaker", "")
                    text = payload.get("text", "")
                    if speaker == "human" and text:
                        messages.append({"role": "user", "content": text})
                    elif speaker == "ai" and text:
                        messages.append({"role": "assistant", "content": text})
                except Exception:
                    continue

        # Add current speech as the latest user message
        messages.append({"role": "user", "content": speech_result})

        completion = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=messages,
            temperature=0.8,
            max_tokens=80
        )

        reply = (completion.choices[0].message.content or "").strip()
        return reply if reply else "Hmm, could you say that again?"
    except Exception as e:
        app.logger.exception(f"Phone agent chat failed: {e}")
        return "Sorry, I'm having a bit of trouble. Could you repeat that?"


# -------- Chat (modern + legacy) --------
@app.post("/ask")
@require_bearer
def ask():
    try:
        body = request.get_json(force=True, silent=True) or {}
        user_text = _extract_user_text(body)
        if not user_text:
            return jsonify(error="empty_user_text"), 400

        reply = _chat_llm(user_text)

        # Persist chat
        u = current_user()
        sess = ChatSession(user_id=u.id, title=user_text[:40] or "New chat")
        db.session.add(sess)
        db.session.commit()

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
            for k in ["prompt", "user_text", "text", "message", "query", "q", "input", "userText"]:
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

        reply = _chat_llm(user_text)

        u = current_user()
        sess = ChatSession(user_id=u.id, title=user_text[:40] or "New chat")
        db.session.add(sess)
        db.session.commit()

        db.session.add(ChatMessage(session_id=sess.id, role="user", content=user_text))
        db.session.add(ChatMessage(session_id=sess.id, role="assistant", content=reply))
        db.session.commit()

        return jsonify(reply=reply), 200
    except Exception as e:
        app.logger.exception("legacy chat failed")
        return jsonify(error="server_error", detail=str(e)), 500


# -------- TTS --------
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

    try:
        with client.audio.speech.with_streaming_response.create(
            model="gpt-4o-mini-tts",
            voice="alloy",
            input=text,
        ) as resp:
            return resp.read()
    except Exception:
        pass

    try:
        res = client.audio.speech.create(model="gpt-4o-mini-tts", voice="alloy", input=text)
        return res.read()
    except Exception:
        res = client.audio.speech.create(model="tts-1", voice="alloy", input=text)
        return res.read()


# In-memory audio cache for Twilio playback
_audio_cache = {}


def _elevenlabs_tts(text: str, voice_id: str = None) -> bytes:
    """Generate speech using ElevenLabs API."""
    if not ELEVENLABS_API_KEY:
        raise RuntimeError("elevenlabs_not_configured")

    voice = voice_id or ELEVENLABS_VOICE_ID
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice}"

    headers = {
        "Accept": "audio/mpeg",
        "Content-Type": "application/json",
        "xi-api-key": ELEVENLABS_API_KEY
    }

    payload = {
        "text": text,
        "model_id": "eleven_turbo_v2",
        "voice_settings": {
            "stability": 0.35,
            "similarity_boost": 0.85,
            "style": 0.3,
            "use_speaker_boost": True
        }
    }

    with httpx.Client(timeout=15.0) as client:
        response = client.post(url, json=payload, headers=headers)
        response.raise_for_status()
        return response.content


def generate_and_cache_audio(text: str, use_elevenlabs: bool = True) -> str:
    """Generate audio and return a cache key for retrieval."""
    # Include voice ID in cache key so changing voice generates new audio
    voice_key = ELEVENLABS_VOICE_ID if (use_elevenlabs and ELEVENLABS_API_KEY) else "polly"
    cache_key = hashlib.md5(f"{voice_key}:{text}".encode()).hexdigest()[:16]

    if cache_key not in _audio_cache:
        try:
            if use_elevenlabs and ELEVENLABS_API_KEY:
                app.logger.info(f"Generating ElevenLabs audio with voice: {ELEVENLABS_VOICE_ID}")
                audio_bytes = _elevenlabs_tts(text)
                app.logger.info(f"ElevenLabs audio generated successfully, {len(audio_bytes)} bytes")
            else:
                app.logger.info("ElevenLabs not configured, falling back to Polly")
                # Fallback to Polly or OpenAI
                try:
                    audio_bytes = _polly_tts(text)
                except Exception:
                    audio_bytes = _openai_tts(text)

            _audio_cache[cache_key] = {
                "audio": audio_bytes,
                "created": datetime.utcnow()
            }
        except Exception as e:
            app.logger.exception(f"TTS generation failed: {e}")
            return None

    return cache_key


@app.get("/audio/<cache_key>")
def get_cached_audio(cache_key):
    """Serve cached audio for Twilio playback."""
    if cache_key not in _audio_cache:
        return "Audio not found", 404

    audio_data = _audio_cache[cache_key]["audio"]
    return Response(audio_data, status=200, mimetype="audio/mpeg")


@app.get("/test-elevenlabs")
@require_bearer
def test_elevenlabs():
    """Debug endpoint to test ElevenLabs TTS."""
    result = {
        "elevenlabs_configured": bool(ELEVENLABS_API_KEY),
        "voice_id": ELEVENLABS_VOICE_ID,
        "api_key_prefix": ELEVENLABS_API_KEY[:10] + "..." if ELEVENLABS_API_KEY else None
    }

    if not ELEVENLABS_API_KEY:
        result["error"] = "ELEVENLABS_API_KEY not set"
        return jsonify(result), 400

    try:
        test_text = "Hello, this is a test."
        audio_bytes = _elevenlabs_tts(test_text)
        result["success"] = True
        result["audio_size"] = len(audio_bytes)
        result["message"] = "ElevenLabs TTS working!"
    except Exception as e:
        result["success"] = False
        result["error"] = str(e)
        result["error_type"] = type(e).__name__

    return jsonify(result)


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

        return Response(audio_bytes, status=200, mimetype="audio/mpeg", headers={"Cache-Control": "no-store"})
    except Exception as e:
        app.logger.exception("speak endpoint error")
        return jsonify(error="server_error", detail=str(e)), 500


# -------- History --------
@app.get("/history")
@require_bearer
@require_user
def list_sessions():
    u = request.user
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
        match = text[i : i + len(query)]
        html = plain.replace(match, f"<mark>{match}</mark>", 1)
        return plain[:width], html[:width]

    base_q = ChatSession.query.filter_by(user_id=u.id, archived=False)
    if q:
        from sqlalchemy import or_
        base_q = (
            base_q.join(ChatMessage, ChatMessage.session_id == ChatSession.id)
            .filter(or_(ChatSession.title.ilike(f"%{q}%"), ChatMessage.content.ilike(f"%{q}%")))
            .distinct()
        )

    base_q = base_q.order_by(ChatSession.created_at.desc())
    total = base_q.count()
    items = base_q.offset((page - 1) * limit).limit(limit).all()

    out = []
    for sess in items:
        last = ChatMessage.query.filter_by(session_id=sess.id).order_by(ChatMessage.created_at.desc()).first()
        preview = last.content if last else ""
        plain, html = highlight_snippet(preview, q)
        out.append({
            "id": sess.id,
            "title": sess.title,
            "created_at": sess.created_at.isoformat(),
            "preview": plain,
            "preview_html": html if q else None,
        })
    has_more = (page * limit) < total
    return jsonify({"items": out, "page": page, "has_more": has_more})


# -------- Entry --------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")), debug=True)
