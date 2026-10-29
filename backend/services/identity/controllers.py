"""Contrôleur HTTP du service Identité."""

from fastapi import APIRouter, Depends, Header
from sqlalchemy.orm import Session

from services.identity import services
from services.identity.views import AdminEnter, OtpRequest, OtpVerify, PhoneChallenge, PhoneCreate, PhoneUpdate, PhoneVerify, StatusUpdate
from shared.db import get_db
from shared.utils import require_roles

router = APIRouter()


@router.post("/auth/request-otp")
def request_otp(body: OtpRequest, db: Session = Depends(get_db)):
    return services.request_otp(db, body.phone, body.purpose, body.name)


@router.post("/auth/verify")
def verify_otp(body: OtpVerify, db: Session = Depends(get_db)):
    return services.verify_otp(db, body.phone, body.code, body.purpose, body.name, body.network)


@router.post("/auth/pdr/request-otp")
def request_pdr_otp(body: OtpRequest, db: Session = Depends(get_db)):
    return services.request_pdr_otp(db, body.phone)


@router.post("/auth/pdr/verify")
def verify_pdr_otp(body: OtpVerify, db: Session = Depends(get_db)):
    return services.verify_pdr_otp(db, body.phone, body.code)


@router.post("/auth/admin/enter")
def enter_admin(body: AdminEnter, db: Session = Depends(get_db)):
    return services.enter_admin(db, body.email, body.password)


@router.get("/meta/detect")
def detect(phone: str, network: str | None = None):
    return services.detect(phone, network)


@router.get("/users/me")
def me(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.get_me(db, user_id)


@router.get("/users")
def users(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    require_roles(authorization, "admin")
    return services.list_users(db)


@router.patch("/users/{user_id}")
def update_user(user_id: int, body: StatusUpdate, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    require_roles(authorization, "admin")
    return services.update_status(db, user_id, body.status)


@router.get("/phones")
def phones(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.get_me(db, user_id)["numbers"]


@router.post("/phones/challenge")
def phone_challenge(body: PhoneChallenge, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.begin_add_phone(db, user_id, body.phone, body.network)


@router.post("/phones")
def create_phone(body: PhoneCreate, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.confirm_add_phone(db, user_id, body.phone, body.network, body.code)


@router.post("/phones/{phone_id}/verify")
def verify_phone(phone_id: int, body: PhoneVerify, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.verify_phone(db, user_id, phone_id, body.code)


@router.patch("/phones/{phone_id}/primary")
def primary_phone(phone_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.set_primary(db, user_id, phone_id)


@router.patch("/phones/{phone_id}")
def patch_phone(phone_id: int, body: PhoneUpdate, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.update_network(db, user_id, phone_id, body.network)


@router.delete("/phones/{phone_id}")
def remove_phone(phone_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.delete_phone(db, user_id, phone_id)
