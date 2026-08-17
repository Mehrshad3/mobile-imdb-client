import requests
from fastapi import HTTPException

from .config import EMAILJS_SERVICE_ID, EMAILJS_TEMPLATE_ID, EMAILJS_PUBLIC_KEY

def send_otp_email(email: str, code: str):
    data = {
        "service_id": EMAILJS_SERVICE_ID,
        "template_id": EMAILJS_TEMPLATE_ID,
        "user_id": EMAILJS_PUBLIC_KEY,
        "template_params": {
            "email": email,
            "passcode": code,
            "time": "15 minutes",
        },
    }

    response = requests.post(
        "https://api.emailjs.com/api/v1.0/email/send",
        json=data,
        timeout=10,
    )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"EmailJS failed: {response.text}",
        )
