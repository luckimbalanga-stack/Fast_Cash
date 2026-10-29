"""Vues JSON partagées."""

from shared.models import AdminUser, Notification, Operation, Pdr, PhoneNumber, Rating, TimelineEvent, User
from shared.utils import eta_minutes, network_label, round_money


def phone_dict(phone: PhoneNumber) -> dict:
    return {
        "id": phone.id,
        "user_id": phone.user_id,
        "phone": phone.phone,
        "network": phone.network,
        "network_label": network_label(phone.network),
        "is_primary": phone.is_primary,
        "verified": phone.verified,
        "created_at": phone.created_at,
    }


def user_dict(user: User, numbers: list[PhoneNumber] | None = None, transaction_count: int | None = None) -> dict:
    payload = {
        "id": user.id,
        "name": user.name,
        "phone": user.phone,
        "status": user.status,
        "created_at": user.created_at,
        "role": "user",
    }
    if numbers is not None:
        payload["numbers"] = [phone_dict(item) for item in numbers]
        primary = next((item for item in numbers if item.is_primary and item.verified), None)
        payload["primary_number"] = phone_dict(primary) if primary else None
    if transaction_count is not None:
        payload["transaction_count"] = transaction_count
    return payload


def network_list(raw: str) -> list[str]:
    return [item for item in raw.split(",") if item]


def pdr_dict(pdr: Pdr, distance_m: float | None = None, available: bool | None = None) -> dict:
    usd_available = round_money(pdr.usd_declared - pdr.usd_reserved, "USD")
    cdf_available = round_money(pdr.cdf_declared - pdr.cdf_reserved, "CDF")
    payload = {
        "id": pdr.id,
        "code": pdr.code,
        "name": pdr.name,
        "manager_name": pdr.manager_name,
        "phone": pdr.phone,
        "address": pdr.address,
        "commune": pdr.commune,
        "city": pdr.city,
        "lat": pdr.lat,
        "lng": pdr.lng,
        "usd_declared": round_money(pdr.usd_declared, "USD"),
        "cdf_declared": round_money(pdr.cdf_declared, "CDF"),
        "usd_reserved": round_money(pdr.usd_reserved, "USD"),
        "cdf_reserved": round_money(pdr.cdf_reserved, "CDF"),
        "usd_available": usd_available,
        "cdf_available": cdf_available,
        "accepts_deposits": pdr.accepts_deposits,
        "networks": network_list(pdr.networks),
        "network_labels": [network_label(item) for item in network_list(pdr.networks)],
        "status": pdr.status,
        "is_open": pdr.is_open,
        "rating_avg": round(pdr.rating_avg or 0, 1),
        "rating_count": pdr.rating_count or 0,
        "opening_hours": pdr.opening_hours,
        "created_at": pdr.created_at,
    }
    if distance_m is not None:
        payload["distance_m"] = round(distance_m)
        payload["eta_min"] = eta_minutes(distance_m)
    if available is not None:
        payload["available_for_request"] = available
    return payload


def timeline_dict(event: TimelineEvent) -> dict:
    return {
        "id": event.id,
        "status": event.status,
        "label": event.label,
        "created_at": event.created_at,
    }


def operation_dict(op: Operation, events: list[TimelineEvent] | None = None) -> dict:
    total = op.amount + op.fees if op.type == "withdrawal" else op.amount
    payload = {
        "id": op.id,
        "reference": op.reference,
        "type": op.type,
        "user_id": op.user_id,
        "user_name": op.user_name,
        "pdr_id": op.pdr_id,
        "pdr_name": op.pdr_name,
        "pdr_address": op.pdr_address,
        "pdr_commune": op.pdr_commune,
        "pdr_lat": op.pdr_lat,
        "pdr_lng": op.pdr_lng,
        "pdr_hours": op.pdr_hours,
        "pdr_phone": op.pdr_phone,
        "phone": op.phone,
        "network": op.network,
        "network_label": network_label(op.network),
        "amount": op.amount,
        "currency": op.currency,
        "fees": op.fees,
        "total": round_money(total, op.currency),
        "cash_amount": op.amount,
        "status": op.status,
        "token_code": op.token_code,
        "token_status": op.token_status,
        "token_expires_at": op.token_expires_at,
        "reserved": op.reserved,
        "rating_stars": op.rating_stars,
        "rating_comment": op.rating_comment,
        "mm_session_ref": op.mm_session_ref,
        "mm_status": op.mm_status,
        "created_at": op.created_at,
        "updated_at": op.updated_at,
    }
    if events is not None:
        payload["timeline"] = [timeline_dict(event) for event in events]
    return payload


def rating_dict(rating: Rating, pdr_name: str | None = None) -> dict:
    return {
        "id": rating.id,
        "pdr_id": rating.pdr_id,
        "pdr_name": pdr_name,
        "user_id": rating.user_id,
        "user_name": rating.user_name,
        "operation_id": rating.operation_id,
        "stars": rating.stars,
        "comment": rating.comment,
        "created_at": rating.created_at,
    }


def notification_dict(item: Notification) -> dict:
    return {
        "id": item.id,
        "audience": item.audience,
        "target_id": item.target_id,
        "title": item.title,
        "body": item.body,
        "is_read": item.is_read,
        "operation_id": item.operation_id,
        "created_at": item.created_at,
    }


def admin_dict(admin: AdminUser) -> dict:
    return {
        "id": admin.id,
        "name": admin.name,
        "email": admin.email,
        "role": admin.role,
        "status": admin.status,
        "created_at": admin.created_at,
    }
