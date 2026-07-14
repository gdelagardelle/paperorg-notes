import re
import smtplib
from email import encoders
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Iterable

from config import settings
from platform_client import (
    platform_email_relay_available,
    resolve_platform_email_config,
    send_platform_email,
)

EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
MAX_RECIPIENTS = 10
MAX_ATTACHMENT_BYTES = 15 * 1024 * 1024
MAX_TOTAL_ATTACHMENT_BYTES = 25 * 1024 * 1024


class EmailDeliveryError(Exception):
    pass


def _local_email_configured() -> bool:
    return bool(
        settings.email_smtp_host.strip()
        and settings.email_smtp_username.strip()
        and settings.email_smtp_password.strip()
        and settings.email_from_address.strip()
    )


def _platform_email_config_available() -> bool:
    config = resolve_platform_email_config()
    return config is not None


def email_delivery_configured() -> bool:
    return (
        platform_email_relay_available()
        or _platform_email_config_available()
        or _local_email_configured()
    )


def email_delivery_source() -> str:
    if platform_email_relay_available():
        return "platform_relay"
    if _platform_email_config_available():
        return "platform_config"
    if _local_email_configured():
        return "local_env"
    return "none"


def validate_recipients(recipients: Iterable[str]) -> list[str]:
    cleaned: list[str] = []
    for raw in recipients:
        email = raw.strip()
        if not email:
            continue
        if not EMAIL_PATTERN.match(email):
            raise EmailDeliveryError(f"Invalid recipient address: {email}")
        if email not in cleaned:
            cleaned.append(email)
    if not cleaned:
        raise EmailDeliveryError("At least one recipient is required.")
    if len(cleaned) > MAX_RECIPIENTS:
        raise EmailDeliveryError(f"Too many recipients (max {MAX_RECIPIENTS}).")
    return cleaned


def _validate_attachments(attachments: list[tuple[str, str, bytes]]) -> None:
    total_attachment_bytes = 0
    for filename, _mime_type, data in attachments:
        if len(data) > MAX_ATTACHMENT_BYTES:
            raise EmailDeliveryError(f"Attachment too large: {filename}")
        total_attachment_bytes += len(data)
    if total_attachment_bytes > MAX_TOTAL_ATTACHMENT_BYTES:
        raise EmailDeliveryError("Total attachment size exceeds the limit.")


def _send_via_smtp_settings(
    *,
    smtp_host: str,
    smtp_port: int,
    smtp_username: str,
    smtp_password: str,
    from_address: str,
    from_name: str,
    recipients: list[str],
    subject: str,
    body: str,
    attachments: list[tuple[str, str, bytes]],
) -> None:
    message = MIMEMultipart()
    message["From"] = f"{from_name} <{from_address}>"
    message["To"] = ", ".join(recipients)
    message["Subject"] = subject
    message.attach(MIMEText(body, "plain", "utf-8"))

    for filename, mime_type, data in attachments:
        maintype, _, subtype = mime_type.partition("/")
        if subtype:
            part = MIMEBase(maintype, subtype)
        else:
            part = MIMEBase("application", "octet-stream")
        part.set_payload(data)
        encoders.encode_base64(part)
        part.add_header("Content-Disposition", f'attachment; filename="{filename}"')
        message.attach(part)

    try:
        with smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=60) as smtp:
            smtp.login(smtp_username, smtp_password)
            smtp.sendmail(from_address, recipients, message.as_string())
    except smtplib.SMTPAuthenticationError as exc:
        raise EmailDeliveryError("Email server authentication failed.") from exc
    except smtplib.SMTPException as exc:
        raise EmailDeliveryError(f"Email could not be sent: {exc}") from exc
    except OSError as exc:
        raise EmailDeliveryError(f"Could not connect to the email server: {exc}") from exc


def send_email(
    *,
    user_id: str,
    recipients: list[str],
    subject: str,
    body: str,
    attachments: list[tuple[str, str, bytes]],
) -> None:
    if not email_delivery_configured():
        raise EmailDeliveryError("Email delivery is not configured.")

    validated = validate_recipients(recipients)
    subject = subject.strip() or "Paperorg Notes"
    body = body.strip()
    if not body:
        raise EmailDeliveryError("Email body is empty.")
    _validate_attachments(attachments)

    if platform_email_relay_available():
        try:
            send_platform_email(
                user_id=user_id,
                recipients=validated,
                subject=subject,
                body=body,
                attachments=attachments,
            )
            return
        except RuntimeError as exc:
            raise EmailDeliveryError(str(exc)) from exc

    platform_config = resolve_platform_email_config()
    if platform_config:
        _send_via_smtp_settings(
            smtp_host=str(platform_config["smtp_host"]),
            smtp_port=int(platform_config.get("smtp_port") or 465),
            smtp_username=str(
                platform_config.get("smtp_username")
                or platform_config.get("from_address")
                or platform_config.get("from_email")
                or ""
            ),
            smtp_password=str(platform_config["smtp_password"]),
            from_address=str(platform_config.get("from_address") or platform_config.get("from_email") or ""),
            from_name=str(platform_config.get("from_name") or "Paperorg Notes"),
            recipients=validated,
            subject=subject,
            body=body,
            attachments=attachments,
        )
        return

    if not _local_email_configured():
        raise EmailDeliveryError("Email delivery is not configured.")

    _send_via_smtp_settings(
        smtp_host=settings.email_smtp_host,
        smtp_port=settings.email_smtp_port,
        smtp_username=settings.email_smtp_username,
        smtp_password=settings.email_smtp_password,
        from_address=settings.email_from_address,
        from_name=settings.email_from_name,
        recipients=validated,
        subject=subject,
        body=body,
        attachments=attachments,
    )
