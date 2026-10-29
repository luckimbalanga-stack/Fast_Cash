"""Contrôleur HTTP du service Administration."""

from fastapi import APIRouter, Depends, Header
from sqlalchemy.orm import Session

from services.admin import services
from services.admin.views import AdminPatch, AdminWrite, SettingsWrite
from shared.db import get_db
from shared.utils import require_roles

router = APIRouter()


def _admin(authorization: str | None) -> None:
    require_roles(authorization, "admin")


@router.get("/admin/dashboard")
def dashboard(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.dashboard(db)


@router.get("/admin/charts")
def charts(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.charts(db)


@router.get("/admin/reports")
def reports(
    date_from: str | None = None,
    date_to: str | None = None,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    _admin(authorization)
    return services.reports(db, date_from, date_to)


@router.get("/admin/users")
def users(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.list_users(db)


@router.get("/admin/admins")
def admins(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.list_admins(db)


@router.post("/admin/admins")
def create_admin(body: AdminWrite, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.create_admin(db, body.model_dump())


@router.patch("/admin/admins/{admin_id}")
def update_admin(admin_id: int, body: AdminPatch, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.update_admin(db, admin_id, body.model_dump(exclude_unset=True))


@router.get("/settings")
def settings(db: Session = Depends(get_db)):
    return services.settings_payload(db)


@router.put("/settings")
def update_settings(body: SettingsWrite, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.update_settings(db, body.model_dump(exclude_unset=True))
