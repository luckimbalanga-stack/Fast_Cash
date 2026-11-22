"""Tableaux de bord, rapports et paramètres."""

from collections import defaultdict
from datetime import datetime, timedelta

from fastapi import HTTPException
from sqlalchemy import and_
from sqlalchemy.orm import Session

from shared.commission_ranges import (
    commission_cut_cdf,
    dumps_ranges,
    parse_commission_ranges,
    validate_commission_ranges,
)
from shared.models import AdminUser, Operation, Pdr, PhoneNumber, User
from shared.operation_rules import amount_cdf, is_pdr_success
from shared.serialize import admin_dict, user_dict
from shared import redis_cache
from shared.settings_repo import APP_SETTING_DEFAULTS, settings_map, settings_payload, upsert_setting
from shared.utils import (
    KINSHASA,
    NETWORKS,
    detect_network,
    hash_password,
    network_label,
    normalize_phone,
    now_iso,
    round_money,
)


# Compatibilité des imports internes existants.
_settings_map = settings_map
_upsert_setting = upsert_setting


def update_settings(db: Session, data: dict) -> dict:
    current = settings_payload(db)
    if data.get("fee_percent") is not None:
        value = float(data["fee_percent"])
        if not 0 <= value <= 10:
            raise HTTPException(status_code=400, detail="Les frais doivent rester entre 0 et 10 %.")
        current["fee_percent"] = value
    if data.get("token_minutes") is not None:
        value = int(data["token_minutes"])
        if not 5 <= value <= 180:
            raise HTTPException(status_code=400, detail="La validité du jeton doit rester entre 5 et 180 minutes.")
        current["token_minutes"] = value
    if data.get("usd_cdf_rate") is not None:
        value = float(data["usd_cdf_rate"])
        if not 100 <= value <= 20000:
            raise HTTPException(status_code=400, detail="Taux indicatif hors plage.")
        current["usd_cdf_rate"] = value
    if data.get("search_radius_m") is not None:
        value = int(data["search_radius_m"])
        if not 100 <= value <= 20000:
            raise HTTPException(status_code=400, detail="Le rayon de recherche doit rester entre 100 et 20 000 mètres.")
        current["search_radius_m"] = value
    if data.get("pdr_offer_seconds") is not None:
        value = int(data["pdr_offer_seconds"])
        if not 5 <= value <= 120:
            raise HTTPException(status_code=400, detail="Le délai d'acceptation PDR doit rester entre 5 et 120 secondes.")
        current["pdr_offer_seconds"] = value
    if data.get("app_version") is not None:
        value = str(data["app_version"]).strip()
        if not value:
            raise HTTPException(status_code=400, detail="Indiquez le numéro de version de l’application.")
        current["app_version"] = value
    if data.get("app_min_version") is not None:
        value = str(data["app_min_version"]).strip()
        if not value:
            raise HTTPException(status_code=400, detail="Indiquez la version minimale acceptée.")
        current["app_min_version"] = value
    if data.get("app_download_url") is not None:
        value = str(data["app_download_url"]).strip()
        if value and not (value.startswith("https://") or value.startswith("http://")):
            raise HTTPException(status_code=400, detail="Le lien de téléchargement doit commencer par http:// ou https://.")
        current["app_download_url"] = value
    if data.get("app_update_message") is not None:
        current["app_update_message"] = str(data["app_update_message"]).strip() or APP_SETTING_DEFAULTS["app_update_message"]
    if data.get("commission_ranges") is not None:
        ranges = validate_commission_ranges(parse_commission_ranges(data["commission_ranges"]))
        if not ranges:
            raise HTTPException(status_code=400, detail="Ajoutez au moins une plage de commission.")
        _upsert_setting(db, "commission_ranges", dumps_ranges(ranges))
    for key in (
        "fee_percent",
        "token_minutes",
        "usd_cdf_rate",
        "search_radius_m",
        "pdr_offer_seconds",
        "app_version",
        "app_min_version",
        "app_download_url",
        "app_update_message",
    ):
        if key in current:
            _upsert_setting(db, key, str(current[key]))
    return settings_payload(db)


def _delta(current: float, previous: float) -> float | None:
    if previous == 0:
        return None
    return round((current - previous) / previous * 100, 1)


def dashboard(db: Session) -> dict:
    cached = redis_cache.get_json(redis_cache.KEY_ADMIN_DASHBOARD)
    if isinstance(cached, dict) and "transactions" in cached:
        return cached

    from sqlalchemy import case, func

    now = datetime.now(KINSHASA)
    recent_start = (now - timedelta(days=15)).isoformat()
    previous_start = (now - timedelta(days=30)).isoformat()
    accepted_states = ("accepted", "payment_pending", "payment_confirmed", "cash_delivered", "completed")

    users = db.query(func.count(User.id)).scalar() or 0
    active_pdr = db.query(func.count(Pdr.id)).filter(Pdr.status == "active", Pdr.is_open.is_(True)).scalar() or 0
    row = db.query(
        func.count(Operation.id),
        func.sum(case((Operation.type == "withdrawal", 1), else_=0)),
        func.sum(case((Operation.type == "deposit", 1), else_=0)),
        func.sum(case((Operation.status == "pending", 1), else_=0)),
        func.sum(case((Operation.status == "refused", 1), else_=0)),
        func.sum(case((Operation.status == "completed", 1), else_=0)),
        func.sum(case((Operation.status.in_(accepted_states), 1), else_=0)),
        func.sum(case((Operation.created_at >= recent_start, 1), else_=0)),
        func.sum(case((and_(Operation.created_at >= previous_start, Operation.created_at < recent_start), 1), else_=0)),
        func.sum(case((and_(Operation.type == "withdrawal", Operation.created_at >= recent_start), 1), else_=0)),
        func.sum(case((and_(Operation.type == "withdrawal", Operation.created_at >= previous_start, Operation.created_at < recent_start), 1), else_=0)),
        func.sum(case((and_(Operation.type == "deposit", Operation.created_at >= recent_start), 1), else_=0)),
        func.sum(case((and_(Operation.type == "deposit", Operation.created_at >= previous_start, Operation.created_at < recent_start), 1), else_=0)),
    ).one()

    (
        total,
        withdrawals,
        deposits,
        pending,
        refused,
        completed,
        positives,
        recent_total,
        prev_total,
        recent_withdrawals,
        prev_withdrawals,
        recent_deposits,
        prev_deposits,
    ) = [int(value or 0) for value in row]
    rate = round(positives / (positives + refused) * 100, 1) if positives or refused else 0
    payload = {
        "users": {"label": "Utilisateurs", "value": int(users), "delta": None},
        "active_pdr": {"label": "PDR actifs", "value": int(active_pdr), "delta": None},
        "transactions": {"label": "Transactions", "value": total, "delta": _delta(recent_total, prev_total)},
        "withdrawals": {"label": "Retraits", "value": withdrawals, "delta": _delta(recent_withdrawals, prev_withdrawals)},
        "deposits": {"label": "Dépôts", "value": deposits, "delta": _delta(recent_deposits, prev_deposits)},
        "pending": {"label": "Demandes en attente", "value": pending, "delta": None},
        "refused": {"label": "Demandes refusées", "value": refused, "delta": None},
        "completed": {"label": "Transactions terminées", "value": completed, "delta": None},
        "acceptance_rate": rate,
        "banner": settings_payload(db)["banner"],
    }
    redis_cache.set_json(redis_cache.KEY_ADMIN_DASHBOARD, payload, ttl=20)
    return payload


def _parse_day(value: str | None, fallback):
    if not value:
        return fallback
    try:
        return datetime.strptime(value[:10], "%Y-%m-%d").date()
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Date invalide (AAAA-MM-JJ).") from exc


def charts(
    db: Session,
    date_from: str | None = None,
    date_to: str | None = None,
    network: str | None = None,
) -> dict:
    cfg = settings_payload(db)
    rate = float(cfg["usd_cdf_rate"])
    today = datetime.now(KINSHASA).date()
    start = _parse_day(date_from, today - timedelta(days=29))
    end = _parse_day(date_to, today)
    if end < start:
        raise HTTPException(status_code=400, detail="La date de fin doit être postérieure à la date de début.")
    network_key = (network or "").strip().lower() or None
    if network_key and network_key not in NETWORKS:
        raise HTTPException(status_code=400, detail="Opérateur Mobile Money inconnu.")
    span = (end - start).days
    if span > 180:
        raise HTTPException(status_code=400, detail="La période du graphique PDR est limitée à 180 jours.")

    cache_key = redis_cache.charts_cache_key(start.isoformat(), end.isoformat(), network_key)
    cached = redis_cache.get_json(cache_key)
    if isinstance(cached, dict) and "daily" in cached:
        return cached

    window_start = min(today - timedelta(days=29), start).isoformat()
    ops = (
        db.query(Operation)
        .filter(Operation.created_at >= window_start)
        .all()
    )
    by_day: dict[str, list[Operation]] = defaultdict(list)
    for op in ops:
        by_day[op.created_at[:10]].append(op)

    days = [(today - timedelta(days=offset)) for offset in range(29, -1, -1)]
    daily = []
    for day in days:
        key = day.isoformat()
        totals = {
            "CDF": {"withdrawals": 0.0, "deposits": 0.0},
            "USD": {"withdrawals": 0.0, "deposits": 0.0},
        }
        for op in by_day.get(key, []):
            if op.currency not in totals:
                continue
            field = "withdrawals" if op.type == "withdrawal" else "deposits"
            totals[op.currency][field] += op.amount
        daily.append({
            "date": key,
            "cdf": {name: round_money(value, "CDF") for name, value in totals["CDF"].items()},
            "usd": {name: round_money(value, "USD") for name, value in totals["USD"].items()},
        })

    operators: dict[str, int] = defaultdict(int)
    currencies: dict[str, int] = defaultdict(int)
    ranking: dict[int, dict] = {}
    accepted_states = {"accepted", "payment_pending", "payment_confirmed", "cash_delivered", "completed"}
    positives = 0
    refused = 0
    for op in ops:
        operators[op.network] += 1
        currencies[op.currency] += 1
        if op.status in accepted_states:
            positives += 1
        elif op.status == "refused":
            refused += 1
        if op.status not in {"refused", "cancelled", "expired", "pending"}:
            bucket = ranking.setdefault(op.pdr_id, {"pdr_id": op.pdr_id, "name": op.pdr_name, "count": 0})
            bucket["count"] += 1
    operator_rows = [
        {"network": key, "label": network_label(key), "count": value}
        for key, value in sorted(operators.items(), key=lambda item: -item[1])
    ]
    top = sorted(ranking.values(), key=lambda item: -item["count"])[:5]

    # Plages USD (sans champs d’affichage) pour recalculer les coupes liquidité.
    ranges = validate_commission_ranges(
        parse_commission_ranges(
            [
                {
                    "min_usd": row["min_usd"],
                    "max_usd": row["max_usd"],
                    "cut_usd": row["cut_usd"],
                    "transaction_type": row.get("transaction_type", "withdrawal"),
                }
                for row in (cfg.get("commission_ranges") or [])
            ]
        )
    )

    pdr_days = [start + timedelta(days=offset) for offset in range(span + 1)]
    pdr_daily = []
    for day in pdr_days:
        key = day.isoformat()
        withdrawal_cuts = 0.0
        deposit_cuts = 0.0
        count = 0
        for op in by_day.get(key, []):
            if not op.pdr_id or not is_pdr_success(op):
                continue
            if network_key and op.network != network_key:
                continue
            try:
                if op.type == "withdrawal":
                    withdrawal_cuts += commission_cut_cdf(
                        ranges,
                        op.amount,
                        op.currency,
                        rate,
                        transaction_type="withdrawal",
                    )
                else:
                    deposit_cuts += commission_cut_cdf(
                        ranges,
                        op.amount,
                        op.currency,
                        rate,
                        transaction_type="deposit",
                    )
            except Exception:
                # Hors plage / pas de plage dépôt : 0 pour ne pas fausser le graphique.
                pass
            count += 1
        pdr_daily.append({
            "date": key,
            # Compat front : "withdrawals" = coupes commission retrait (CDF).
            "withdrawals": round_money(withdrawal_cuts, "CDF"),
            "cuts": round_money(withdrawal_cuts, "CDF"),
            # "deposits" = coupes commission dépôt (CDF), pas le volume reçu.
            "deposits": round_money(deposit_cuts, "CDF"),
            "total": round_money(withdrawal_cuts + deposit_cuts, "CDF"),
            "count": count,
        })

    payload = {
        "daily": daily,
        "pdr_daily": pdr_daily,
        "pdr_filters": {
            "date_from": start.isoformat(),
            "date_to": end.isoformat(),
            "network": network_key,
        },
        "operators": operator_rows,
        "currencies": [{"currency": key, "count": value} for key, value in currencies.items()],
        "acceptance": {"accepted": positives, "refused": refused},
        "top_pdrs": top,
        "usd_cdf_rate": rate,
    }
    redis_cache.set_json(cache_key, payload, ttl=30)
    return payload


def reports(db: Session, date_from: str | None, date_to: str | None, network: str | None = None) -> dict:
    cfg = settings_payload(db)
    rate = float(cfg["usd_cdf_rate"])
    network_key = (network or "").strip().lower() or None
    if network_key and network_key not in NETWORKS:
        raise HTTPException(status_code=400, detail="Opérateur Mobile Money inconnu.")
    query = db.query(Operation)
    if date_from:
        query = query.filter(Operation.created_at >= date_from)
    if date_to:
        query = query.filter(Operation.created_at <= f"{date_to}T23:59:59.999999")
    if network_key:
        query = query.filter(Operation.network == network_key)
    selected = query.all()

    def bucket(key_fn):
        grouped: dict[str, dict] = {}
        for op in selected:
            key = key_fn(op) or "—"
            row = grouped.setdefault(key, {"key": key, "count": 0, "usd": 0.0, "cdf": 0.0, "cdf_equiv": 0.0})
            row["count"] += 1
            cdf_equiv = amount_cdf(op, rate)
            row["cdf_equiv"] += cdf_equiv
            if op.currency == "USD":
                row["usd"] += op.amount
            else:
                row["cdf"] += op.amount
        rows = list(grouped.values())
        for row in rows:
            row["usd"] = round_money(row["usd"], "USD")
            row["cdf"] = round_money(row["cdf"], "CDF")
            row["cdf_equiv"] = round_money(row["cdf_equiv"], "CDF")
        return sorted(rows, key=lambda item: -item["count"])

    success = [op for op in selected if op.pdr_id and is_pdr_success(op)]
    success_volume = round_money(sum(amount_cdf(op, rate) for op in success), "CDF")
    cover_percent = float(cfg["fee_percent"])
    return {
        "count": len(selected),
        "by_type": bucket(lambda op: op.type),
        "by_network": bucket(lambda op: network_label(op.network)),
        "by_commune": bucket(lambda op: op.pdr_commune),
        "by_status": bucket(lambda op: op.status),
        "by_pdr": bucket(lambda op: op.pdr_name or f"PDR #{op.pdr_id}"),
        "by_client": bucket(lambda op: op.user_name or f"Client #{op.user_id}"),
        "pdr_success": {
            "count": len(success),
            "volume_cdf": success_volume,
            "cover_percent": cover_percent,
            "cover_cdf": round_money(success_volume * (cover_percent / 100.0), "CDF"),
        },
        "usd_cdf_rate": rate,
        "network": network_key,
    }


def list_users(db: Session) -> list[dict]:
    from collections import defaultdict

    from sqlalchemy import func

    users = db.query(User).order_by(User.created_at.desc()).all()
    if not users:
        return []
    user_ids = [user.id for user in users]
    numbers_by_user: dict[int, list] = defaultdict(list)
    for phone in db.query(PhoneNumber).filter(PhoneNumber.user_id.in_(user_ids)).all():
        numbers_by_user[phone.user_id].append(phone)
    counts = dict(
        db.query(Operation.user_id, func.count(Operation.id))
        .filter(Operation.user_id.in_(user_ids))
        .group_by(Operation.user_id)
        .all()
    )
    return [user_dict(user, numbers_by_user.get(user.id, []), int(counts.get(user.id, 0))) for user in users]


def _resolve_network(phone: str, network: str | None) -> str:
    raw = (network or "").strip().lower().replace(" ", "").replace("-", "").replace("_", "")
    aliases = {
        "orange": "orange",
        "orangemoney": "orange",
        "airtel": "airtel",
        "airtelmoney": "airtel",
        "mpesa": "mpesa",
        "m-pesa": "mpesa",
        "vodacom": "mpesa",
        "afrimoney": "afrimoney",
        "afri": "afrimoney",
    }
    chosen = aliases.get(raw) or (network.strip().lower() if network else None)
    if chosen in NETWORKS:
        return chosen
    guessed = detect_network(phone)
    if guessed:
        return guessed
    raise HTTPException(status_code=400, detail="Réseau Mobile Money inconnu (orange, airtel, mpesa, afrimoney).")


def create_user(db: Session, data: dict) -> dict:
    name = (data.get("name") or "").strip()
    if len(name) < 2:
        raise HTTPException(status_code=400, detail="Indiquez un nom d’au moins 2 caractères.")
    phone = normalize_phone(data["phone"])
    status = (data.get("status") or "active").strip().lower()
    if status in {"actif", "active"}:
        status = "active"
    elif status in {"suspendu", "suspended", "inactif", "inactive"}:
        status = "suspended"
    if status not in {"active", "suspended"}:
        raise HTTPException(status_code=400, detail="Statut inconnu (actif ou suspendu).")
    if db.query(Pdr).filter(Pdr.phone == phone).first():
        raise HTTPException(status_code=400, detail="Ce numéro appartient déjà à un point de retrait.")
    if db.query(User).filter(User.phone == phone).first() or db.query(PhoneNumber).filter(PhoneNumber.phone == phone).first():
        raise HTTPException(status_code=400, detail="Ce numéro est déjà utilisé.")
    network = _resolve_network(phone, data.get("network"))
    user = User(name=name, phone=phone, status=status, created_at=now_iso())
    db.add(user)
    db.flush()
    db.add(
        PhoneNumber(
            user_id=user.id,
            phone=phone,
            network=network,
            is_primary=True,
            verified=True,
            created_at=now_iso(),
        )
    )
    db.flush()
    numbers = db.query(PhoneNumber).filter(PhoneNumber.user_id == user.id).all()
    return user_dict(user, numbers, 0)


def import_users(db: Session, rows: list[dict]) -> dict:
    created = []
    errors = []
    for index, row in enumerate(rows, start=1):
        try:
            created.append(create_user(db, row))
        except HTTPException as exc:
            detail = exc.detail if isinstance(exc.detail, str) else str(exc.detail)
            errors.append({"row": index, "phone": str(row.get("phone") or ""), "name": str(row.get("name") or ""), "error": detail})
        except Exception as exc:  # noqa: BLE001
            errors.append({"row": index, "phone": str(row.get("phone") or ""), "name": str(row.get("name") or ""), "error": str(exc)})
    return {
        "created_count": len(created),
        "error_count": len(errors),
        "created": created,
        "errors": errors,
    }


def list_admins(db: Session) -> list[dict]:
    return [admin_dict(admin) for admin in db.query(AdminUser).order_by(AdminUser.id.asc()).all()]


def create_admin(db: Session, data: dict) -> dict:
    email = data["email"].strip().lower()
    if "@" not in email:
        raise HTTPException(status_code=400, detail="Adresse e-mail invalide.")
    if data["role"] not in {"superadmin", "support"}:
        raise HTTPException(status_code=400, detail="Rôle inconnu.")
    password = data.get("password") or ""
    if len(password) < 8:
        raise HTTPException(status_code=400, detail="Le mot de passe doit contenir au moins 8 caractères.")
    if db.query(AdminUser).filter(AdminUser.email == email).first():
        raise HTTPException(status_code=400, detail="Cet e-mail est déjà utilisé.")
    admin = AdminUser(
        name=data["name"].strip(),
        email=email,
        password_hash=hash_password(password),
        role=data["role"],
        status="active",
        created_at=now_iso(),
    )
    db.add(admin)
    db.flush()
    return admin_dict(admin)


def update_admin(db: Session, admin_id: int, data: dict) -> dict:
    admin = db.get(AdminUser, admin_id)
    if not admin:
        raise HTTPException(status_code=404, detail="Administrateur introuvable.")
    if data.get("name"):
        admin.name = data["name"].strip()
    if data.get("role"):
        if data["role"] not in {"superadmin", "support"}:
            raise HTTPException(status_code=400, detail="Rôle inconnu.")
        admin.role = data["role"]
    if data.get("status"):
        if data["status"] not in {"active", "suspended"}:
            raise HTTPException(status_code=400, detail="Statut inconnu.")
        admin.status = data["status"]
    return admin_dict(admin)
