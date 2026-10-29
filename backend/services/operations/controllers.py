"""Contrôleur HTTP du service Opérations."""

from fastapi import APIRouter, Depends, Header
from sqlalchemy.orm import Session

from services.operations import services
from services.operations.views import OperationCreate, PinBody, RatingBody, TokenRedeem
from shared.db import get_db
from shared.utils import require_roles

router = APIRouter()


@router.get("/operations")
def list_operations(
    type: str | None = None,
    status: str | None = None,
    currency: str | None = None,
    pdr_id: int | None = None,
    user_id: int | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    q: str | None = None,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    role, ident = require_roles(authorization, "user", "pdr", "admin")
    return services.list_operations(db, role, ident, type, status, currency, pdr_id, user_id, date_from, date_to, q)


@router.post("/operations")
def create_operation(body: OperationCreate, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.create_operation(db, user_id, body.model_dump())


@router.get("/operations/token/{code}")
def lookup_token(code: str, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, pdr_id = require_roles(authorization, "pdr")
    return services.lookup_token(db, pdr_id, code)


@router.post("/operations/token/redeem")
def redeem(body: TokenRedeem, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, pdr_id = require_roles(authorization, "pdr")
    return services.redeem(db, pdr_id, body.code)


@router.get("/operations/{operation_id}")
def get_operation(operation_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    role, ident = require_roles(authorization, "user", "pdr", "admin")
    op = services.get_operation(db, operation_id)
    services._visible(op, role, ident)
    return services.present(db, op)


@router.post("/operations/{operation_id}/accept")
def accept(operation_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, pdr_id = require_roles(authorization, "pdr")
    return services.accept(db, pdr_id, operation_id)


@router.post("/operations/{operation_id}/refuse")
def refuse(operation_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, pdr_id = require_roles(authorization, "pdr")
    return services.refuse(db, pdr_id, operation_id)


@router.post("/operations/{operation_id}/authorize")
def authorize(operation_id: int, body: PinBody, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.authorize(db, user_id, operation_id, body.pin)


@router.post("/operations/{operation_id}/confirm-cash")
def confirm_cash(operation_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, pdr_id = require_roles(authorization, "pdr")
    return services.confirm_cash(db, pdr_id, operation_id)


@router.post("/operations/{operation_id}/simulate-transfer")
def simulate_transfer(operation_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    role, ident = require_roles(authorization, "user", "pdr")
    return services.simulate_transfer(db, role, ident, operation_id)


@router.post("/operations/{operation_id}/cancel")
def cancel(operation_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    role, ident = require_roles(authorization, "user", "pdr", "admin")
    return services.cancel(db, role, ident, operation_id)


@router.post("/operations/{operation_id}/rate")
def rate(operation_id: int, body: RatingBody, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _role, user_id = require_roles(authorization, "user")
    return services.rate(db, user_id, operation_id, body.stars, body.comment)
