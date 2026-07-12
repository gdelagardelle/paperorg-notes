"""Handle App Store Server Notifications v2 for subscription lifecycle."""

from __future__ import annotations

from typing import Any, Optional

from app_store import AppStoreVerificationError, decode_and_verify_jws, expires_at_from_transaction
from config import settings
from database import (
    find_user_by_original_transaction,
    link_subscription,
    log_subscription_event,
    set_user_pro,
)

ACTIVE_NOTIFICATIONS = {
    "SUBSCRIBED",
    "DID_RENEW",
    "OFFER_REDEEMED",
    "RENEWAL_EXTENDED",
    "RENEWAL_EXTENSION",
}

INACTIVE_NOTIFICATIONS = {
    "EXPIRED",
    "GRACE_PERIOD_EXPIRED",
    "REFUND",
    "REVOKE",
}


def handle_signed_notification(signed_payload: str) -> dict[str, str]:
    notification = decode_and_verify_jws(
        signed_payload,
        bundle_id=settings.apple_bundle_id,
    )
    notification_type = notification.get("notificationType", "UNKNOWN")
    subtype = notification.get("subtype")
    data = notification.get("data") or {}

    if notification_type == "TEST":
        return {"status": "ok", "notification_type": "TEST"}

    signed_transaction = data.get("signedTransactionInfo")
    if not signed_transaction:
        return {
            "status": "ignored",
            "notification_type": notification_type,
            "reason": "missing_transaction",
        }

    transaction = decode_and_verify_jws(
        signed_transaction,
        bundle_id=settings.apple_bundle_id,
        product_id=settings.apple_pro_product_id,
    )
    original_transaction_id = transaction.get("originalTransactionId")
    transaction_id = transaction.get("transactionId")
    product_id = transaction.get("productId") or settings.apple_pro_product_id

    user_id = find_user_by_original_transaction(original_transaction_id)
    event_label = notification_type if not subtype else f"{notification_type}.{subtype}"

    if notification_type in ACTIVE_NOTIFICATIONS:
        expires_at = expires_at_from_transaction(transaction)
        if user_id:
            set_user_pro(user_id, True, expires_at)
        if user_id and original_transaction_id:
            link_subscription(user_id, original_transaction_id, product_id)
        log_subscription_event(
            user_id or "unlinked",
            product_id,
            transaction_id,
            event_label,
        )
        return {
            "status": "activated",
            "notification_type": event_label,
            "user_id": user_id or "",
        }

    if notification_type in INACTIVE_NOTIFICATIONS:
        if user_id:
            set_user_pro(user_id, False, None)
        log_subscription_event(
            user_id or "unlinked",
            product_id,
            transaction_id,
            event_label,
        )
        return {
            "status": "deactivated",
            "notification_type": event_label,
            "user_id": user_id or "",
        }

    log_subscription_event(
        user_id or "unlinked",
        product_id,
        transaction_id,
        event_label,
    )
    return {
        "status": "ignored",
        "notification_type": event_label,
        "user_id": user_id or "",
    }
