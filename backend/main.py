import asyncio
import json
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import httpx
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile, status
from pydantic import BaseModel, Field

from app_store import AppStoreVerificationError, verify_pro_subscription
from app_store_notifications import handle_signed_notification
from auth_utils import create_access_token, get_current_user
from platform_client import (
    platform_minutes_remaining,
    report_platform_usage,
    resolve_provider_key,
)
from config import settings
from database import (
    add_usage_minutes,
    check_connection,
    get_or_create_user,
    get_usage_minutes,
    init_db,
    link_subscription,
    log_subscription_event,
    period_key,
    set_user_pro,
    uses_postgres,
)
from email_delivery import (
    EmailDeliveryError,
    email_delivery_configured,
    email_delivery_sender,
    email_delivery_source,
    send_email,
)
from rate_limit import enforce_rate_limit, enforce_user_rate_limit

app = FastAPI(title="Paperorg Notes Pro API", version="1.0.0")


class RegisterRequest(BaseModel):
    device_id: str = Field(min_length=8, max_length=128)


class RegisterResponse(BaseModel):
    access_token: str
    user_id: str
    is_pro: bool
    minutes_limit: int
    minutes_used: float


class UsageResponse(BaseModel):
    is_pro: bool
    minutes_limit: int
    minutes_used: float
    minutes_remaining: float
    period_key: str
    pro_expires_at: Optional[str] = None


class VerifySubscriptionRequest(BaseModel):
    product_id: str
    transaction_id: Optional[str] = None
    signed_transaction_info: Optional[str] = None


class AppStoreNotificationRequest(BaseModel):
    signedPayload: str = Field(min_length=10)


class SummarizeRequest(BaseModel):
    transcript: str
    output_type: str
    language: str
    summary_length: str = "detailed"


@app.on_event("startup")
def startup() -> None:
    init_db()


def user_is_pro(user_row) -> bool:
    if not user_row["is_pro"]:
        return False
    expires = user_row["pro_expires_at"]
    if not expires:
        return True
    try:
        expiry = datetime.fromisoformat(expires)
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=timezone.utc)
        return expiry > datetime.now(timezone.utc)
    except ValueError:
        return False


def require_device_token(token: dict[str, Any]) -> dict[str, Any]:
    """Endpoints that manage local users (usage/verify) are legacy-only;
    Platform-authenticated clients talk to the Platform for those."""
    if token.get("source") == "platform":
        raise HTTPException(
            status_code=400,
            detail="This endpoint is served by the Platform for platform-authenticated clients.",
        )
    return token


def require_pro_user(token: dict[str, Any]):
    if token.get("source") == "platform":
        if "notes.pro" not in token.get("ent", []):
            raise HTTPException(
                status_code=status.HTTP_402_PAYMENT_REQUIRED,
                detail="Paperorg Pro subscription required.",
            )
        return {"id": token["sub"], "platform": True, "bearer": token["bearer"]}
    user = get_or_create_user(token["device_id"])
    if not user_is_pro(user):
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Paperorg Pro subscription required.",
        )
    return user


def enforce_usage_limit(user, audio_minutes: float) -> None:
    if isinstance(user, dict) and user.get("platform"):
        remaining = platform_minutes_remaining(user["bearer"])
        if remaining is not None and audio_minutes > remaining:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Monthly limit reached. Resets next month.",
            )
        return
    used = get_usage_minutes(user["id"])
    if used + audio_minutes > settings.pro_minutes_per_month:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"Monthly limit reached ({settings.pro_minutes_per_month} minutes). "
                "Resets next month or upgrade when available."
            ),
        )


def record_usage(user, audio_minutes: float, provider: str = "unknown") -> None:
    if isinstance(user, dict) and user.get("platform"):
        report_platform_usage(
            user["bearer"], user["id"], max(audio_minutes, 0.1), provider
        )
        return
    add_usage_minutes(user["id"], max(audio_minutes, 0.1))


@app.get("/health")
def health() -> dict[str, str]:
    backend = "postgresql" if uses_postgres() else "sqlite"
    return {"status": "ok", "service": "paperorg-pro", "database": backend}


@app.get("/ready")
def ready() -> dict[str, str]:
    if not check_connection():
        raise HTTPException(status_code=503, detail="Database unavailable.")
    return {"status": "ready", "database": "connected"}


@app.post("/v1/auth/register", response_model=RegisterResponse)
def register(body: RegisterRequest, request: Request) -> RegisterResponse:
    enforce_rate_limit(request, key_prefix="register", max_requests=20, window_seconds=3600)
    user = get_or_create_user(body.device_id)
    token = create_access_token(user["id"], user["device_id"])
    minutes_used = get_usage_minutes(user["id"])
    return RegisterResponse(
        access_token=token,
        user_id=user["id"],
        is_pro=user_is_pro(user),
        minutes_limit=settings.pro_minutes_per_month if user_is_pro(user) else 0,
        minutes_used=minutes_used,
    )


@app.get("/v1/usage", response_model=UsageResponse)
def usage(token: dict[str, Any] = Depends(get_current_user)) -> UsageResponse:
    token = require_device_token(token)
    user = get_or_create_user(token["device_id"])
    return build_usage_response(user)


def build_usage_response(user) -> UsageResponse:
    is_pro = user_is_pro(user)
    used = get_usage_minutes(user["id"])
    limit = settings.pro_minutes_per_month if is_pro else 0
    return UsageResponse(
        is_pro=is_pro,
        minutes_limit=limit,
        minutes_used=used,
        minutes_remaining=max(0.0, limit - used),
        period_key=period_key(),
        pro_expires_at=user["pro_expires_at"],
    )


@app.post("/v1/subscription/verify", response_model=UsageResponse)
def verify_subscription(
    body: VerifySubscriptionRequest,
    request: Request,
    token: dict[str, Any] = Depends(get_current_user),
) -> UsageResponse:
    enforce_rate_limit(request, key_prefix="verify", max_requests=30, window_seconds=3600)
    token = require_device_token(token)
    user = get_or_create_user(token["device_id"])

    if body.product_id != settings.apple_pro_product_id:
        raise HTTPException(status_code=400, detail="Unknown product.")

    if settings.paperorg_dev_mode and not body.signed_transaction_info and not body.transaction_id:
        expires_at = (datetime.now(timezone.utc) + timedelta(days=32)).isoformat()
        set_user_pro(user["id"], True, expires_at)
        log_subscription_event(user["id"], body.product_id, body.transaction_id, "dev_verified")
        user = get_or_create_user(token["device_id"])
        return build_usage_response(user)

    try:
        verification = verify_pro_subscription(
            product_id=body.product_id,
            transaction_id=body.transaction_id,
            signed_transaction_info=body.signed_transaction_info,
            bundle_id=settings.apple_bundle_id,
            issuer_id=settings.apple_issuer_id,
            key_id=settings.apple_key_id,
            private_key=settings.apple_private_key,
            use_sandbox=settings.apple_use_sandbox,
        )
    except AppStoreVerificationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    expires_at = verification["expires_at"]
    set_user_pro(user["id"], True, expires_at)
    if verification.get("original_transaction_id"):
        link_subscription(
            user["id"],
            verification["original_transaction_id"],
            verification.get("product_id") or body.product_id,
        )
    log_subscription_event(
        user["id"],
        body.product_id,
        verification.get("transaction_id") or body.transaction_id,
        "verified",
    )
    user = get_or_create_user(token["device_id"])
    return build_usage_response(user)


@app.post("/v1/webhooks/app-store")
def app_store_webhook(body: AppStoreNotificationRequest, request: Request) -> dict[str, str]:
    enforce_rate_limit(request, key_prefix="webhook", max_requests=120, window_seconds=60)
    try:
        return handle_signed_notification(body.signedPayload)
    except AppStoreVerificationError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/v1/subscription/dev-activate", response_model=UsageResponse)
def dev_activate(token: dict[str, Any] = Depends(get_current_user)) -> UsageResponse:
    if not settings.paperorg_dev_mode:
        raise HTTPException(status_code=404, detail="Not found.")
    token = require_device_token(token)
    user = get_or_create_user(token["device_id"])
    expires_at = (datetime.now(timezone.utc) + timedelta(days=32)).isoformat()
    set_user_pro(user["id"], True, expires_at)
    used = get_usage_minutes(user["id"])
    return UsageResponse(
        is_pro=True,
        minutes_limit=settings.pro_minutes_per_month,
        minutes_used=used,
        minutes_remaining=max(0.0, settings.pro_minutes_per_month - used),
        period_key=period_key(),
        pro_expires_at=expires_at,
    )


@app.post("/v1/transcribe/openai")
async def transcribe_openai(
    file: UploadFile = File(...),
    language: str = Form("en"),
    prompt: Optional[str] = Form(None),
    duration_seconds: float = Form(0),
    token: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user = require_pro_user(token)
    openai_key = resolve_provider_key("openai", settings.openai_api_key)
    if not openai_key:
        raise HTTPException(status_code=503, detail="OpenAI not configured on server.")

    minutes = duration_seconds / 60 if duration_seconds > 0 else 1
    enforce_usage_limit(user, minutes)

    audio_bytes = await file.read()
    data: dict[str, Any] = {
        "model": "gpt-4o-transcribe",
        "response_format": "json",
        "language": language,
    }
    if prompt:
        data["prompt"] = prompt[:900]

    files = {"file": (file.filename or "audio.m4a", audio_bytes, file.content_type or "audio/m4a")}

    async with httpx.AsyncClient(timeout=300) as client:
        response = await client.post(
            "https://api.openai.com/v1/audio/transcriptions",
            headers={"Authorization": f"Bearer {openai_key}"},
            data=data,
            files=files,
        )

    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    record_usage(user, minutes, "openai")
    return response.json()


@app.post("/v1/transcribe/elevenlabs")
async def transcribe_elevenlabs(
    file: UploadFile = File(...),
    language_code: str = Form("eng"),
    diarize: bool = Form(False),
    duration_seconds: float = Form(0),
    token: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user = require_pro_user(token)
    elevenlabs_key = resolve_provider_key("elevenlabs", settings.elevenlabs_api_key)
    if not elevenlabs_key:
        raise HTTPException(status_code=503, detail="ElevenLabs not configured on server.")

    minutes = duration_seconds / 60 if duration_seconds > 0 else 1
    enforce_usage_limit(user, minutes)

    audio_bytes = await file.read()
    data = {
        "model_id": "scribe_v2",
        "language_code": language_code,
        "timestamps_granularity": "word",
        "diarize": "true" if diarize else "false",
    }
    files = {"file": (file.filename or "audio.m4a", audio_bytes, file.content_type or "audio/m4a")}

    async with httpx.AsyncClient(timeout=300) as client:
        response = await client.post(
            "https://api.elevenlabs.io/v1/speech-to-text",
            headers={"xi-api-key": elevenlabs_key},
            data=data,
            files=files,
        )

    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    record_usage(user, minutes, "elevenlabs")
    return response.json()


@app.post("/v1/transcribe/luxasr")
async def transcribe_luxasr(
    file: UploadFile = File(...),
    language: str = Form("lb"),
    prompt: Optional[str] = Form(None),
    duration_seconds: float = Form(0),
    token: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user = require_pro_user(token)

    minutes = duration_seconds / 60 if duration_seconds > 0 else 1
    enforce_usage_limit(user, minutes)

    audio_bytes = await file.read()
    headers = {"Content-Type": file.content_type or "audio/m4a", "X-Filename": file.filename or "audio.m4a"}
    luxasr_key = resolve_provider_key("luxasr", settings.luxasr_api_key)
    if luxasr_key:
        headers["Authorization"] = f"Bearer {luxasr_key}"

    params = {"language": language, "diarization": "Enabled", "outfmt": "json"}
    if prompt:
        params["prompt"] = prompt[:900]

    async with httpx.AsyncClient(timeout=300, base_url="https://luxasr.uni.lu") as client:
        submit = await client.post("/asr2", params=params, content=audio_bytes, headers=headers)
        if submit.status_code >= 400:
            raise HTTPException(status_code=submit.status_code, detail=submit.text)

        payload = submit.json()
        job_id = payload.get("job_id")
        if not job_id:
            raise HTTPException(status_code=502, detail="LuxASR did not return a job ID.")

        for _ in range(120):
            status_response = await client.get(f"/v3/asr/jobs/{job_id}")
            status_payload = status_response.json()
            job_status = status_payload.get("status")
            if job_status == "completed":
                result = await client.get(f"/v3/asr/jobs/{job_id}/result")
                if result.status_code >= 400:
                    raise HTTPException(status_code=result.status_code, detail=result.text)
                record_usage(user, minutes, "luxasr")
                return result.json()
            if job_status == "failed":
                raise HTTPException(status_code=502, detail="LuxASR job failed.")
            await asyncio.sleep(2)

    raise HTTPException(status_code=504, detail="LuxASR timed out.")


@app.post("/v1/summarize")
async def summarize(
    body: SummarizeRequest,
    token: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user = require_pro_user(token)
    openai_key = resolve_provider_key("openai", settings.openai_api_key)
    if not openai_key:
        raise HTTPException(status_code=503, detail="OpenAI not configured on server.")

    system_prompt = (
        "You are a precise meeting and voice note analyst. Extract structured information ONLY "
        "from the provided transcript. Never invent facts. Return valid JSON."
    )
    length_instruction = (
        "Keep summaries concise (2-3 sentences for short summary)."
        if body.summary_length == "short"
        else "Provide a thorough detailed summary."
    )
    user_prompt = f"""
Output type: {body.output_type}
Language: {body.language}
{length_instruction}

Transcript:
{body.transcript}

Return JSON with keys:
title, shortSummary, detailedSummary, keyIdeas, decisions,
actionItems (array of {{text, assignee, dueDate}}), openQuestions,
risks, nextSteps, peopleMentioned, datesMentioned, importantNumbers, followUpEmailDraft
"""

    request_body = {
        "model": "gpt-4o-mini",
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.2,
    }

    async with httpx.AsyncClient(timeout=120) as client:
        response = await client.post(
            "https://api.openai.com/v1/chat/completions",
            headers={"Authorization": f"Bearer {openai_key}"},
            json=request_body,
        )

    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=response.text)

    payload = response.json()
    content = payload["choices"][0]["message"]["content"]
    return json.loads(content)


def token_user_key(token: dict[str, Any]) -> str:
    if token.get("source") == "platform":
        return f"platform:{token['sub']}"
    return f"device:{token.get('device_id') or token.get('sub')}"


@app.get("/v1/email/status")
def email_status(token: dict[str, Any] = Depends(get_current_user)) -> dict[str, Any]:
    _ = token
    status_payload: dict[str, Any] = {
        "available": email_delivery_configured(),
        "source": email_delivery_source(),
    }
    status_payload.update(email_delivery_sender())
    return status_payload


@app.post("/v1/email/send")
async def email_send(
    request: Request,
    subject: str = Form(...),
    body: str = Form(...),
    recipients: str = Form(...),
    audio: Optional[UploadFile] = File(None),
    pdf: Optional[UploadFile] = File(None),
    markdown: Optional[UploadFile] = File(None),
    token: dict[str, Any] = Depends(get_current_user),
) -> dict[str, str]:
    if not email_delivery_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Email delivery is not configured on the server.",
        )

    enforce_user_rate_limit(
        token_user_key(token),
        key_prefix="email-send",
        max_requests=settings.email_daily_limit,
        window_seconds=86_400,
    )
    enforce_rate_limit(request, key_prefix="email-send-ip", max_requests=120, window_seconds=3600)

    try:
        recipient_list = json.loads(recipients)
        if not isinstance(recipient_list, list):
            raise ValueError("recipients must be a JSON array")
        recipient_strings = [str(item) for item in recipient_list]
    except (json.JSONDecodeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="Invalid recipients payload.") from exc

    attachments: list[tuple[str, str, bytes]] = []
    for upload, default_name, default_type in (
        (audio, "recording.m4a", "audio/m4a"),
        (pdf, "note.pdf", "application/pdf"),
        (markdown, "note.md", "text/markdown"),
    ):
        if upload is None:
            continue
        data = await upload.read()
        if not data:
            continue
        attachments.append(
            (
                upload.filename or default_name,
                upload.content_type or default_type,
                data,
            )
        )

    try:
        send_email(
            user_id=token_user_key(token),
            recipients=recipient_strings,
            subject=subject,
            body=body,
            attachments=attachments,
        )
    except EmailDeliveryError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {"status": "sent"}
