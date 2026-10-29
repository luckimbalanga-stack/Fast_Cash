"""Règles métier du service Notifications."""

from fastapi import HTTPException
from sqlalchemy.orm import Session

from shared.models import Notification
from shared.serialize import notification_dict
from shared.utils import now_iso


def create(db: Session, data: dict) -> dict:
    if data["audience"] not in {"user", "pdr", "admin"}:
        raise HTTPException(status_code=400, detail="Audience inconnue.")
    item = Notification(
        audience=data["audience"],
        target_id=data["target_id"],
        title=data["title"].strip(),
        body=data["body"].strip(),
        is_read=False,
        operation_id=data.get("operation_id"),
        created_at=now_iso(),
    )
    db.add(item)
    db.flush()
    return notification_dict(item)


def list_for(db: Session, audience: str, target_id: int) -> list[dict]:
    rows = (
        db.query(Notification)
        .filter(Notification.audience == audience, Notification.target_id == target_id)
        .order_by(Notification.created_at.desc())
        .all()
    )
    return [notification_dict(item) for item in rows]


def mark_read(db: Session, audience: str, target_id: int, notification_id: int) -> dict:
    item = db.get(Notification, notification_id)
    if not item or item.audience != audience or item.target_id != target_id:
        raise HTTPException(status_code=404, detail="Notification introuvable.")
    item.is_read = True
    return notification_dict(item)


def mark_all(db: Session, audience: str, target_id: int) -> dict:
    db.query(Notification).filter(
        Notification.audience == audience,
        Notification.target_id == target_id,
        Notification.is_read.is_(False),
    ).update({"is_read": True})
    return {"ok": True}
