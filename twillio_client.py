# FILE: server/twilio_client.py
# Simple Twilio helper using Render env vars.

import os
from twilio.rest import Client

TWILIO_ACCOUNT_SID = os.environ["TWILIO_ACCOUNT_SID"]
TWILIO_AUTH_TOKEN  = os.environ["TWILIO_AUTH_TOKEN"]

# Number you’ve purchased in Twilio, also stored as env var in Render.
TWILIO_FROM_NUMBER = os.environ.get("TWILIO_FROM_NUMBER", "")

client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)


def start_outbound_call(number: str, goal: str | None = None) -> str:
    """
    Start an outbound call using Twilio.
    Returns the Twilio call SID.
    """
    if not TWILIO_FROM_NUMBER:
        raise RuntimeError("TWILIO_FROM_NUMBER is not configured")

    # For now, use a simple TwiML URL that tells Twilio what to say / do.
    # Later you can point this to a dynamic endpoint that uses Polly/LLM.
    twiml_url = os.environ.get(
        "TWILIO_TWIML_URL",
        "https://handler.twilio.com/twiml/your-basic-flow"
    )

    call = client.calls.create(
        to=number,
        from_=TWILIO_FROM_NUMBER,
        url=twiml_url,
    )

    # Optional: log the goal so you can look it up while the call is running
    print(f"[twilio] started call sid={call.sid} to={number} goal={goal!r}")
    return call.sid
