"""Contrôleur HTTP du service Notifications."""

from fastapi import APIRouter, Depends, Header
from sqlalchemy.orm import Session

from services.notifications import services
from services.notifications.views import NotificationCreate
from shared.db import get_db
from shared.utils import INTERNAL_KEY, require_roles

router = APIRouter()


@router.post("/notifications")
def create(body: NotificationCreate, x_internal_key: str | None = Header(default=None), db: Session = Depends(get_db)):
    if x_internal_key != INTERNAL_KEY:
        from fastapi import HTTPException

        raise HTTPException(status_code=403, detail="Accès interne refusé.")
    return services.create(db, body.model_dump())


@router.get("/notifications")
def listing(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    role, ident = require_roles(authorization, "user", "pdr", "admin")
    audience = "admin" if role == "admin" else role
    target = 0 if role == "admin" else ident
    if role == "admin":
        target = ident
    return services.list_for(db, audience, target)


@router.patch("/notifications/{notification_id}/read")
def read_one(notification_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    role, ident = require_roles(authorization, "user", "pdr", "admin")
    return services.mark_read(db, role, ident, notification_id)


@router.post("/notifications/read-all")
def read_all(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    role, ident = require_roles(authorization, "user", "pdr", "admin")
    return services.mark_all(db, role, ident)
