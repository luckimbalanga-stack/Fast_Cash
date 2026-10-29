"""Règles métier du service PDR."""

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from shared.models import Pdr, PhoneNumber, Rating
from shared.serialize import pdr_dict, rating_dict
from shared.utils import NETWORKS, SEARCH_RADII_M, haversine_m, normalize_phone, now_iso, round_money


def _networks(values: list[str]) -> str:
    cleaned = []
    for value in values:
        if value not in NETWORKS:
            raise HTTPException(status_code=400, detail=f"Réseau inconnu : {value}.")
        if value not in cleaned:
            cleaned.append(value)
    if not cleaned:
        raise HTTPException(status_code=400, detail="Sélectionnez au moins un réseau Mobile Money.")
    return ",".join(cleaned)


def _supports(pdr: Pdr, network: str | None) -> bool:
    if not network:
        return True
    return network in pdr.networks.split(",")


def _available_amount(pdr: Pdr, currency: str) -> float:
    if currency == "USD":
        return pdr.usd_declared - pdr.usd_reserved
    return pdr.cdf_declared - pdr.cdf_reserved


def is_match(pdr: Pdr, kind: str, currency: str, amount: float, network: str | None) -> bool:
    if pdr.status != "active" or not pdr.is_open:
        return False
    if not _supports(pdr, network):
        return False
    if kind == "deposit":
        return bool(pdr.accepts_deposits)
    if _available_amount(pdr, currency) + 1e-6 < amount:
        return False
    return True


def list_pdrs(
    db: Session,
    commune: str | None = None,
    status: str | None = None,
    is_open: bool | None = None,
    network: str | None = None,
    currency: str | None = None,
) -> list[dict]:
    query = db.query(Pdr)
    if commune:
        query = query.filter(Pdr.commune == commune)
    if status:
        query = query.filter(Pdr.status == status)
    if is_open is not None:
        query = query.filter(Pdr.is_open.is_(is_open))
    rows = query.order_by(Pdr.name.asc()).all()
    payload = []
    for pdr in rows:
        if network and network not in pdr.networks.split(","):
            continue
        if currency == "USD" and pdr.usd_declared - pdr.usd_reserved <= 0:
            continue
        if currency == "CDF" and pdr.cdf_declared - pdr.cdf_reserved <= 0:
            continue
        payload.append(pdr_dict(pdr))
    return payload


def get_pdr(db: Session, pdr_id: int) -> dict:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    return pdr_dict(pdr)


def search(
    db: Session,
    lat: float,
    lng: float,
    kind: str,
    currency: str,
    amount: float,
    network: str | None,
    simulated: bool,
    max_m: int | None = None,
) -> dict:
    if kind not in {"withdrawal", "deposit"}:
        raise HTTPException(status_code=400, detail="Type d'opération inconnu.")
    if currency not in {"USD", "CDF"}:
        raise HTTPException(status_code=400, detail="Devise inconnue.")
    rows = db.query(Pdr).filter(Pdr.status == "active", Pdr.is_open.is_(True)).all()
    measured = [(haversine_m(lat, lng, pdr.lat, pdr.lng), pdr) for pdr in rows]
    if max_m is not None:
        cap = 1000
        nearby = [
            (distance, pdr)
            for distance, pdr in measured
            if distance <= cap and is_match(pdr, kind, currency, amount, network)
        ]
        results = [pdr_dict(pdr, distance_m=distance, available=True) for distance, pdr in nearby]
        results.sort(key=lambda item: (-float(item["rating_avg"]), float(item["distance_m"])))
        return {
            "origin": {"lat": lat, "lng": lng, "simulated": simulated},
            "radius_m": cap,
            "currency": currency,
            "amount": amount,
            "type": kind,
            "results": results,
        }
    chosen = SEARCH_RADII_M[-1]
    matched: list[tuple[float, Pdr]] = []
    for radius in SEARCH_RADII_M:
        matched = [
            (distance, pdr)
            for distance, pdr in measured
            if distance <= radius and is_match(pdr, kind, currency, amount, network)
        ]
        chosen = radius
        if matched:
            break
    results = []
    for distance, pdr in matched:
        results.append(pdr_dict(pdr, distance_m=distance, available=True))
    results.sort(key=lambda item: item["distance_m"])
    return {
        "origin": {"lat": lat, "lng": lng, "simulated": simulated},
        "radius_m": chosen,
        "currency": currency,
        "amount": amount,
        "type": kind,
        "results": results,
    }


def create_pdr(db: Session, data: dict) -> dict:
    phone = normalize_phone(data["phone"])
    if db.query(Pdr).filter(Pdr.phone == phone).first() or db.query(PhoneNumber).filter(PhoneNumber.phone == phone).first():
        raise HTTPException(status_code=400, detail="Ce numéro est déjà utilisé.")
    code = (data.get("code") or "").strip().upper()
    if not code:
        last = db.query(func.max(Pdr.id)).scalar() or 0
        code = f"FC-PDR-{last + 1:03d}"
    if db.query(Pdr).filter(Pdr.code == code).first():
        raise HTTPException(status_code=400, detail="Ce code PDR existe déjà.")
    if data.get("status") not in {"active", "inactive"}:
        raise HTTPException(status_code=400, detail="Statut inconnu.")
    pdr = Pdr(
        code=code,
        name=data["name"].strip(),
        manager_name=data["manager_name"].strip(),
        phone=phone,
        address=data["address"].strip(),
        commune=data["commune"].strip(),
        city=(data.get("city") or "Kinshasa").strip(),
        lat=data["lat"],
        lng=data["lng"],
        usd_declared=max(0, round_money(data.get("usd_declared") or 0, "USD")),
        cdf_declared=max(0, round_money(data.get("cdf_declared") or 0, "CDF")),
        usd_reserved=0,
        cdf_reserved=0,
        accepts_deposits=bool(data.get("accepts_deposits", True)),
        networks=_networks(data.get("networks") or []),
        status=data.get("status") or "active",
        is_open=bool(data.get("is_open", True)),
        opening_hours=data.get("opening_hours") or "07:00 - 20:00",
        rating_avg=5,
        rating_count=0,
        created_at=now_iso(),
    )
    db.add(pdr)
    db.flush()
    return pdr_dict(pdr)


def update_pdr(db: Session, pdr_id: int, data: dict) -> dict:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    if data.get("phone"):
        phone = normalize_phone(data["phone"])
        clash = db.query(Pdr).filter(Pdr.phone == phone, Pdr.id != pdr.id).first()
        if clash:
            raise HTTPException(status_code=400, detail="Ce numéro est déjà utilisé.")
        pdr.phone = phone
    for field in ("name", "manager_name", "address", "commune", "city", "opening_hours"):
        if data.get(field):
            setattr(pdr, field, data[field].strip())
    if data.get("lat") is not None:
        pdr.lat = data["lat"]
    if data.get("lng") is not None:
        pdr.lng = data["lng"]
    if data.get("networks") is not None:
        pdr.networks = _networks(data["networks"])
    if data.get("status") is not None:
        if data["status"] not in {"active", "inactive"}:
            raise HTTPException(status_code=400, detail="Statut inconnu.")
        pdr.status = data["status"]
    if data.get("is_open") is not None:
        pdr.is_open = data["is_open"]
    if data.get("accepts_deposits") is not None:
        pdr.accepts_deposits = data["accepts_deposits"]
    return pdr_dict(pdr)


def deactivate(db: Session, pdr_id: int) -> dict:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    pdr.status = "inactive"
    pdr.is_open = False
    return pdr_dict(pdr)


def update_availability(db: Session, pdr_id: int, data: dict) -> dict:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    if data.get("usd_declared") is not None:
        amount = round_money(data["usd_declared"], "USD")
        if amount < pdr.usd_reserved:
            raise HTTPException(status_code=400, detail="Le montant USD déclaré est inférieur aux liquidités déjà réservées.")
        pdr.usd_declared = amount
    if data.get("cdf_declared") is not None:
        amount = round_money(data["cdf_declared"], "CDF")
        if amount < pdr.cdf_reserved:
            raise HTTPException(status_code=400, detail="Le montant CDF déclaré est inférieur aux liquidités déjà réservées.")
        pdr.cdf_declared = amount
    if data.get("accepts_deposits") is not None:
        pdr.accepts_deposits = data["accepts_deposits"]
    if data.get("networks") is not None:
        pdr.networks = _networks(data["networks"])
    if data.get("is_open") is not None:
        pdr.is_open = data["is_open"]
    return pdr_dict(pdr)


def _move(db: Session, pdr_id: int, currency: str, amount: float, action: str) -> dict:
    if currency not in {"USD", "CDF"}:
        raise HTTPException(status_code=400, detail="Devise inconnue.")
    if amount <= 0:
        raise HTTPException(status_code=400, detail="Montant invalide.")
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    amount = round_money(amount, currency)
    declared_attr = "usd_declared" if currency == "USD" else "cdf_declared"
    reserved_attr = "usd_reserved" if currency == "USD" else "cdf_reserved"
    declared = getattr(pdr, declared_attr)
    reserved = getattr(pdr, reserved_attr)
    if action == "reserve":
        if declared - reserved + 1e-6 < amount:
            raise HTTPException(status_code=409, detail="Liquidités insuffisantes pour réserver cette opération.")
        setattr(pdr, reserved_attr, round_money(reserved + amount, currency))
    elif action == "release":
        setattr(pdr, reserved_attr, round_money(max(0, reserved - amount), currency))
    elif action == "consume":
        setattr(pdr, reserved_attr, round_money(max(0, reserved - amount), currency))
        setattr(pdr, declared_attr, round_money(max(0, declared - amount), currency))
    elif action == "receive":
        setattr(pdr, declared_attr, round_money(declared + amount, currency))
    else:
        raise HTTPException(status_code=400, detail="Mouvement de liquidité inconnu.")
    return pdr_dict(pdr)


def reserve(db: Session, pdr_id: int, currency: str, amount: float) -> dict:
    return _move(db, pdr_id, currency, amount, "reserve")


def release(db: Session, pdr_id: int, currency: str, amount: float) -> dict:
    return _move(db, pdr_id, currency, amount, "release")


def consume(db: Session, pdr_id: int, currency: str, amount: float) -> dict:
    return _move(db, pdr_id, currency, amount, "consume")


def receive(db: Session, pdr_id: int, currency: str, amount: float) -> dict:
    return _move(db, pdr_id, currency, amount, "receive")


def list_ratings(db: Session, pdr_id: int | None = None) -> list[dict]:
    query = db.query(Rating, Pdr.name).join(Pdr, Pdr.id == Rating.pdr_id)
    if pdr_id:
        query = query.filter(Rating.pdr_id == pdr_id)
    rows = query.order_by(Rating.created_at.desc()).all()
    return [rating_dict(rating, name) for rating, name in rows]


def add_rating(db: Session, pdr_id: int, data: dict) -> dict:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    if db.query(Rating).filter(Rating.operation_id == data["operation_id"]).first():
        raise HTTPException(status_code=409, detail="Cette opération a déjà été évaluée.")
    rating = Rating(
        pdr_id=pdr_id,
        user_id=data["user_id"],
        user_name=data["user_name"],
        operation_id=data["operation_id"],
        stars=data["stars"],
        comment=(data.get("comment") or "").strip(),
        created_at=now_iso(),
    )
    db.add(rating)
    db.flush()
    count = db.query(func.count(Rating.id)).filter(Rating.pdr_id == pdr_id).scalar()
    pdr.rating_count = int(count or 0)
    pdr.rating_avg = float(data["stars"])
    return rating_dict(rating, pdr.name) | {"rating_avg": pdr.rating_avg, "rating_count": pdr.rating_count}
