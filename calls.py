# FILE: server/routes/calls.py
# Example FastAPI route for starting a call manually.

from fastapi import APIRouter
from pydantic import BaseModel

from ..twilio_client import start_outbound_call

router = APIRouter()


class CallRequest(BaseModel):
    number: str
    goal: str | None = None


@router.post("/api/call")
async def api_start_call(body: CallRequest):
    sid = start_outbound_call(number=body.number, goal=body.goal)
    return {"ok": True, "call_sid": sid}
