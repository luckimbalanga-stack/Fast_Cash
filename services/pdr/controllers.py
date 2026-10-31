"""Contrôleur HTTP du service PDR."""

from fastapi import APIRouter, Depends, Header
from sqlalchemy.orm import Session

from services.pdr import services
from services.pdr.views import AvailabilityWrite, LiquidityMove, PdrPatch, PdrWrite, RatingWrite
from shared.db import get_db
from shared.utils import INTERNAL_KEY, require_roles

router = APIRouter()


def _owner_or_admin(authorization: str | None, pdr_id: int) -> None:
    role, ident = require_roles(authorization, "pdr", "admin")
    if role == "pdr" and ident != pdr_id:
        from fastapi import HTTPException

        raise HTTPException(status_code=403, detail="Vous ne pouvez gérer que votre point de retrait.")


def _internal(x_internal_key: str | None) -> None:
    if x_internal_key != INTERNAL_KEY:
        from fastapi import HTTPException

        raise HTTPException(status_code=403, detail="Accès interne refusé.")


@router.get("/pdr")
def list_pdrs(
    commune: str | None = None,
    status: str | None = None,
    is_open: bool | None = None,
    network: str | None = None,
    currency: str | None = None,
    db: Session = Depends(get_db),
):
    return services.list_pdrs(db, commune, status, is_open, network, currency)


@router.get("/pdr/search")
def search(
    lat: float,
    lng: float,
    kind: str = "withdrawal",
    currency: str = "USD",
    amount: float = 0,
    network: str | None = None,
    simulated: bool = False,
    max_m: int | None = None,
    db: Session = Depends(get_db),
):
    return services.search(db, lat, lng, kind, currency, amount, network, simulated, max_m)


@router.get("/pdr/ratings")
def ratings(pdr_id: int | None = None, db: Session = Depends(get_db)):
    return services.list_ratings(db, pdr_id)


@router.get("/pdr/{pdr_id}")
def get_pdr(pdr_id: int, db: Session = Depends(get_db)):
    return services.get_pdr(db, pdr_id)


@router.post("/pdr")
def create_pdr(body: PdrWrite, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    require_roles(authorization, "admin")
    return services.create_pdr(db, body.model_dump())


@router.patch("/pdr/{pdr_id}")
def update_pdr(pdr_id: int, body: PdrPatch, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    require_roles(authorization, "admin")
    return services.update_pdr(db, pdr_id, body.model_dump(exclude_unset=True))


@router.post("/pdr/{pdr_id}/deactivate")
def deactivate(pdr_id: int, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    require_roles(authorization, "admin")
    return services.deactivate(db, pdr_id)


@router.post("/pdr/{pdr_id}/availability")
def availability(pdr_id: int, body: AvailabilityWrite, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _owner_or_admin(authorization, pdr_id)
    return services.update_availability(db, pdr_id, body.model_dump(exclude_unset=True))


@router.post("/pdr/{pdr_id}/ratings")
def rate(pdr_id: int, body: RatingWrite, x_internal_key: str | None = Header(default=None), db: Session = Depends(get_db)):
    _internal(x_internal_key)
    return services.add_rating(db, pdr_id, body.model_dump())


@router.post("/pdr/{pdr_id}/liquidity/reserve")
def reserve(pdr_id: int, body: LiquidityMove, x_internal_key: str | None = Header(default=None), db: Session = Depends(get_db)):
    _internal(x_internal_key)
    return services.reserve(db, pdr_id, body.currency, body.amount)


@router.post("/pdr/{pdr_id}/liquidity/release")
def release(pdr_id: int, body: LiquidityMove, x_internal_key: str | None = Header(default=None), db: Session = Depends(get_db)):
    _internal(x_internal_key)
    return services.release(db, pdr_id, body.currency, body.amount)


@router.post("/pdr/{pdr_id}/liquidity/consume")
def consume(pdr_id: int, body: LiquidityMove, x_internal_key: str | None = Header(default=None), db: Session = Depends(get_db)):
    _internal(x_internal_key)
    return services.consume(db, pdr_id, body.currency, body.amount)


@router.post("/pdr/{pdr_id}/liquidity/receive")
def receive(pdr_id: int, body: LiquidityMove, x_internal_key: str | None = Header(default=None), db: Session = Depends(get_db)):
    _internal(x_internal_key)
    return services.receive(db, pdr_id, body.currency, body.amount)
