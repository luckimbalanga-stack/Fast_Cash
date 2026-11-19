"""Règles métier du service PDR."""

import secrets
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from shared.models import Pdr, PhoneNumber, Rating
from shared.pending_ops import cancel_pending_for_pdr
from shared.pdr_rules import pdr_can_handle
from shared.serialize import pdr_dict, rating_dict
from shared.settings_repo import settings_map, settings_payload, upsert_setting
from shared.utils import KINSHASA, NETWORKS, hash_password, haversine_m, normalize_phone, now_iso, round_money


def _generate_password(length: int = 10) -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def _validate_password(password: str) -> str:
    cleaned = (password or "").strip()
    if len(cleaned) < 8:
        raise HTTPException(status_code=400, detail="Le mot de passe doit contenir au moins 8 caractères.")
    if len(cleaned) > 80:
        raise HTTPException(status_code=400, detail="Le mot de passe est trop long.")
    return cleaned


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


def _available_amount(pdr: Pdr, currency: str) -> float:
    if currency == "USD":
        return pdr.usd_declared - pdr.usd_reserved
    return pdr.cdf_declared - pdr.cdf_reserved


def _day_success_volume_cdf(
    db: Session,
    pdr_id: int,
    day: str | None = None,
    *,
    rate: float | None = None,
) -> float:
    """Somme CDF des transactions réussies du PDR pour la journée (agrégation SQL)."""
    from sqlalchemy import and_, case, func, or_

    from shared.models import Operation

    day_key = day or datetime.now(KINSHASA).strftime("%Y-%m-%d")
    fx = float(rate if rate is not None else settings_payload(db).get("usd_cdf_rate", 2880))
    success = Operation.status == "completed"
    total = (
        db.query(
            func.coalesce(
                func.sum(
                    case(
                        (Operation.currency == "CDF", Operation.amount),
                        else_=Operation.amount * fx,
                    )
                ),
                0.0,
            )
        )
        .filter(
            Operation.pdr_id == pdr_id,
            Operation.updated_at >= f"{day_key}T00:00:00",
            Operation.updated_at < f"{day_key}T23:59:59.999999",
            success,
        )
        .scalar()
    )
    return round_money(float(total or 0), "CDF")


def _liquidity_metrics(db: Session, pdr: Pdr, *, cfg: dict | None = None) -> tuple[float, float, float]:
    """Une lecture settings + un volume → (volume, cover, fee%)."""
    settings = cfg or settings_payload(db)
    fee = max(0.0, float(settings.get("fee_percent", 1)))
    volume = _day_success_volume_cdf(db, pdr.id, rate=float(settings.get("usd_cdf_rate", 2880)))
    cover = round_money(volume * (fee / 100.0), "CDF")
    return volume, cover, fee


def _cover_required_cdf(db: Session, pdr_id: int) -> float:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        return 0.0
    _, cover, _ = _liquidity_metrics(db, pdr)
    return cover


def _can_toggle_open(db: Session, pdr: Pdr, *, metrics: tuple[float, float, float] | None = None) -> bool:
    """Ouverture possible ssi disponible CDF > (% × volume réussi du jour)."""
    available = _available_amount(pdr, "CDF")
    cover = metrics[1] if metrics else _cover_required_cdf(db, pdr.id)
    return available > cover + 1e-6


def _has_available_liquidity(pdr: Pdr) -> bool:
    """True s’il reste du disponible CDF (> 0). La poche USD n’est plus utilisée."""
    return _available_amount(pdr, "CDF") > 1e-6


def _force_closed_without_liquidity(
    db: Session,
    pdr: Pdr,
    *,
    metrics: tuple[float, float, float] | None = None,
) -> bool:
    """Ferme le PDR si disponible CDF ≤ couverture requise."""
    metrics = metrics or _liquidity_metrics(db, pdr)
    if _can_toggle_open(db, pdr, metrics=metrics) or not pdr.is_open:
        return False
    pdr.is_open = False
    cover = metrics[1]
    cancel_pending_for_pdr(
        db,
        pdr.id,
        f"Liquidité insuffisante (couverture {cover:g} CDF) — point fermé automatiquement",
    )
    return True


def _require_liquidity_to_toggle(db: Session, pdr: Pdr, want_open: bool) -> None:
    """Ouverture/fermeture manuelle seulement si liquidité > couverture du jour."""
    metrics = _liquidity_metrics(db, pdr)
    if _can_toggle_open(db, pdr, metrics=metrics):
        return
    if want_open:
        volume, cover, fee = metrics
        del volume
        raise HTTPException(
            status_code=400,
            detail=(
                "Statut verrouillé à fermé : liquidité CDF insuffisante par rapport "
                f"au seuil ({fee:g} % des transactions réussies = {cover:g} CDF)."
            ),
        )


_LAST_SETTLED_DAY: str | None = None


def maybe_run_daily_settlement(db: Session) -> None:
    """À partir de 23h (Kinshasa) : retire le volume réussi du jour de la liquidité CDF."""
    global _LAST_SETTLED_DAY
    from sqlalchemy import and_, case, func, or_

    from shared.models import Operation

    now = datetime.now(KINSHASA)
    if now.hour < 23:
        return
    today = now.strftime("%Y-%m-%d")
    if _LAST_SETTLED_DAY == today:
        return
    raw = settings_map(db)
    if raw.get("liquidity_last_settle_date") == today:
        _LAST_SETTLED_DAY = today
        return
    cfg = settings_payload(db)
    rate = float(cfg.get("usd_cdf_rate", 2880))
    success = Operation.status == "completed"
    volume_rows = (
        db.query(
            Operation.pdr_id,
            func.coalesce(
                func.sum(
                    case(
                        (Operation.currency == "CDF", Operation.amount),
                        else_=Operation.amount * rate,
                    )
                ),
                0.0,
            ),
        )
        .filter(
            Operation.updated_at >= f"{today}T00:00:00",
            Operation.updated_at < f"{today}T23:59:59.999999",
            success,
        )
        .group_by(Operation.pdr_id)
        .all()
    )
    volumes = {int(pdr_id): float(total or 0) for pdr_id, total in volume_rows}
    fee = max(0.0, float(cfg.get("fee_percent", 1)))
    for pdr in db.query(Pdr).all():
        volume = round_money(volumes.get(pdr.id, 0.0), "CDF")
        if volume > 1e-6:
            pdr.cdf_declared = max(pdr.cdf_reserved, round_money(pdr.cdf_declared - volume, "CDF"))
        cover = round_money(volume * (fee / 100.0), "CDF")
        _force_closed_without_liquidity(db, pdr, metrics=(volume, cover, fee))
    upsert_setting(db, "liquidity_last_settle_date", today)
    _LAST_SETTLED_DAY = today


def enrich_pdr_liquidity(
    db: Session,
    pdr: Pdr,
    *,
    include_password: bool = False,
    mutate: bool = False,
) -> dict:
    """Lecture enrichie. Les mutations (settlement / fermeture) sont opt-in (CQS)."""
    cfg = settings_payload(db)
    metrics = _liquidity_metrics(db, pdr, cfg=cfg)
    if mutate:
        maybe_run_daily_settlement(db)
        _force_closed_without_liquidity(db, pdr, metrics=metrics)
    payload = pdr_dict(pdr, include_password=include_password)
    volume, cover, fee = metrics
    available = _available_amount(pdr, "CDF")
    payload["day_success_volume_cdf"] = volume
    payload["liquidity_cover_cdf"] = cover
    payload["liquidity_cover_percent"] = fee
    payload["can_toggle_open"] = available > cover + 1e-6
    return payload


def simulate_recharge(db: Session, pdr_id: int, network: str, amount: float, pin: str) -> dict:
    """Simule une recharge Mobile Money → crédite le disponible CDF si succès."""
    maybe_run_daily_settlement(db)
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    if network not in NETWORKS:
        raise HTTPException(status_code=400, detail="Opérateur Mobile Money inconnu.")
    value = round_money(amount, "CDF")
    if value < 1000:
        raise HTTPException(status_code=400, detail="Le montant minimum de recharge est 1 000 CDF.")
    cleaned_pin = (pin or "").strip()
    if len(cleaned_pin) < 4 or not cleaned_pin.isdigit():
        raise HTTPException(status_code=400, detail="Saisissez un code PIN Mobile Money valide (4 à 6 chiffres).")
    # Simulation : PIN 0000 = échec, sinon succès.
    if cleaned_pin == "0000":
        payload = enrich_pdr_liquidity(db, pdr, mutate=True)
        payload["recharge"] = {
            "ok": False,
            "added_cdf": 0,
            "network": network,
            "message": "Transaction échouée. Aucun montant n’a été ajouté à votre liquidité.",
        }
        return payload
    pdr.cdf_declared = round_money(pdr.cdf_declared + value, "CDF")
    payload = enrich_pdr_liquidity(db, pdr, mutate=True)
    payload["recharge"] = {
        "ok": True,
        "added_cdf": value,
        "network": network,
        "message": f"Recharge réussie : +{value:g} CDF ajoutés à votre liquidité.",
    }
    return payload


def check_liquidity_policy(db: Session, pdr_id: int) -> dict:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    return enrich_pdr_liquidity(db, pdr, mutate=True)


def is_match(pdr: Pdr, kind: str, currency: str, amount: float, network: str | None) -> bool:
    """Compat : délègue au noyau partagé `pdr_can_handle`."""
    return pdr_can_handle(pdr, kind, currency, amount, network)


def list_pdrs(
    db: Session,
    commune: str | None = None,
    status: str | None = None,
    is_open: bool | None = None,
    network: str | None = None,
    currency: str | None = None,
    *,
    include_password: bool = False,
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
        payload.append(pdr_dict(pdr, include_password=include_password))
    return payload


def get_pdr(db: Session, pdr_id: int, *, include_password: bool = False) -> dict:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    return enrich_pdr_liquidity(db, pdr, include_password=include_password)


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
    # Le rayon admin (Paramètres web) fait foi ; max_m client ne peut que le resserrer.
    configured = max(100, min(20000, int(settings_payload(db)["search_radius_m"])))
    if max_m is not None:
        try:
            client_cap = max(100, min(20000, int(max_m)))
        except (TypeError, ValueError):
            client_cap = configured
        cap = min(configured, client_cap)
    else:
        cap = configured
    # Préfiltre bounding-box (~111 km / degré) avant haversine exact.
    pad_deg = max(0.02, (cap / 111_000.0) * 1.25)
    rows = (
        db.query(Pdr)
        .filter(
            Pdr.status == "active",
            Pdr.is_open.is_(True),
            Pdr.lat.between(lat - pad_deg, lat + pad_deg),
            Pdr.lng.between(lng - pad_deg, lng + pad_deg),
        )
        .all()
    )
    nearby = []
    for pdr in rows:
        distance = haversine_m(lat, lng, pdr.lat, pdr.lng)
        if distance <= cap and is_match(pdr, kind, currency, amount, network):
            nearby.append((distance, pdr))
    # Priorité : plus proche d’abord, puis mieux noté (fermés exclus plus haut).
    nearby.sort(key=lambda item: (item[0], -float(item[1].rating_avg or 0)))
    results = [pdr_dict(pdr, distance_m=distance, available=True) for distance, pdr in nearby]
    return {
        "origin": {"lat": lat, "lng": lng, "simulated": simulated},
        "radius_m": cap,
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
    password = _validate_password(data.get("password") or "")
    usd_declared = max(0, round_money(data.get("usd_declared") or 0, "USD"))
    cdf_declared = max(0, round_money(data.get("cdf_declared") or 0, "CDF"))
    want_open = bool(data.get("is_open", True))
    # Pas de disponible CDF → forcément fermé à la création.
    if want_open and cdf_declared <= 1e-6:
        want_open = False
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
        usd_declared=usd_declared,
        cdf_declared=cdf_declared,
        usd_reserved=0,
        cdf_reserved=0,
        accepts_deposits=bool(data.get("accepts_deposits", True)),
        networks=_networks(data.get("networks") or []),
        status=data.get("status") or "active",
        is_open=want_open,
        opening_hours=data.get("opening_hours") or "07:00 - 20:00",
        rating_avg=5,
        rating_count=0,
        password_hash=hash_password(password),
        password_plain=password,
        created_at=now_iso(),
    )
    db.add(pdr)
    db.flush()
    return pdr_dict(pdr, include_password=True)


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
        want_open = bool(data["is_open"])
        _require_liquidity_to_toggle(db, pdr, want_open)
        pdr.is_open = want_open if _can_toggle_open(db, pdr) else False
    if data.get("accepts_deposits") is not None:
        pdr.accepts_deposits = data["accepts_deposits"]
    if data.get("password"):
        plain = _validate_password(data["password"])
        pdr.password_hash = hash_password(plain)
        pdr.password_plain = plain
    return enrich_pdr_liquidity(db, pdr, include_password=True, mutate=True)


def reset_password(db: Session, pdr_id: int, password: str | None = None) -> dict:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    plain = _validate_password(password) if password else _generate_password()
    pdr.password_hash = hash_password(plain)
    pdr.password_plain = plain
    payload = pdr_dict(pdr, include_password=True)
    payload["delivery"] = "admin_display"
    payload["message"] = "Mot de passe réinitialisé. Communiquez-le au responsable du point (SMS à brancher plus tard)."
    return payload


def deactivate(db: Session, pdr_id: int) -> dict:
    pdr = db.get(Pdr, pdr_id)
    if not pdr:
        raise HTTPException(status_code=404, detail="Point de retrait introuvable.")
    pdr.status = "inactive"
    pdr.is_open = False
    cancel_pending_for_pdr(db, pdr_id, "Point de retrait désactivé")
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
        want_open = bool(data["is_open"])
        _require_liquidity_to_toggle(db, pdr, want_open)
        was_open = bool(pdr.is_open)
        pdr.is_open = want_open if _can_toggle_open(db, pdr) else False
        if was_open and not pdr.is_open:
            cancel_pending_for_pdr(db, pdr_id, "Point de retrait fermé / déconnecté")
    return enrich_pdr_liquidity(db, pdr, mutate=True)


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
    # Si le disponible tombe à 0 (réserve / consommation), fermer automatiquement.
    _force_closed_without_liquidity(db, pdr)
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
    rows = query.order_by(Rating.created_at.desc()).limit(50).all()
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
    average = db.query(func.avg(Rating.stars)).filter(Rating.pdr_id == pdr_id).scalar()
    pdr.rating_count = int(count or 0)
    pdr.rating_avg = round(float(average or 0), 1)
    return rating_dict(rating, pdr.name) | {"rating_avg": pdr.rating_avg, "rating_count": pdr.rating_count}
