"""Tableaux de bord, rapports et paramètres."""

from collections import defaultdict
from datetime import datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from shared.models import AdminUser, Operation, Pdr, PhoneNumber, Setting, User
from shared.serialize import admin_dict, user_dict
from shared.utils import KINSHASA, hash_password, network_label, now_iso, round_money

APP_SETTING_DEFAULTS = {
    "app_version": "1.0.0",
    "app_min_version": "1.0.0",
    "app_download_url": "",
    "app_update_message": "Une nouvelle version de Fast-Cash est disponible. Téléchargez-la pour continuer.",
}


def _settings_map(db: Session) -> dict[str, str]:
    return {row.key: row.value for row in db.query(Setting).all()}


def settings_payload(db: Session) -> dict:
    raw = _settings_map(db)
    return {
        "fee_percent": float(raw.get("fee_percent", "1")),
        "token_minutes": int(float(raw.get("token_minutes", "30"))),
        "usd_cdf_rate": float(raw.get("usd_cdf_rate", "2880")),
        "banner": raw.get("banner", ""),
        "app_version": raw.get("app_version", APP_SETTING_DEFAULTS["app_version"]),
        "app_min_version": raw.get("app_min_version", APP_SETTING_DEFAULTS["app_min_version"]),
        "app_download_url": raw.get("app_download_url", APP_SETTING_DEFAULTS["app_download_url"]),
        "app_update_message": raw.get("app_update_message", APP_SETTING_DEFAULTS["app_update_message"]),
    }


def _upsert_setting(db: Session, key: str, value: str) -> None:
    row = db.get(Setting, key)
    if not row:
        db.add(Setting(key=key, value=value))
    else:
        row.value = value


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
    for key in (
        "fee_percent",
        "token_minutes",
        "usd_cdf_rate",
        "app_version",
        "app_min_version",
        "app_download_url",
        "app_update_message",
    ):
        _upsert_setting(db, key, str(current[key]))
    return settings_payload(db)


def _amount_cdf(op: Operation, rate: float) -> float:
    if op.currency == "CDF":
        return op.amount
    return op.amount * rate


def _delta(current: float, previous: float) -> float | None:
    if previous == 0:
        return None
    return round((current - previous) / previous * 100, 1)


def dashboard(db: Session) -> dict:
    now = datetime.now(KINSHASA)
    ops = db.query(Operation).all()
    users = db.query(User).count()
    active_pdr = db.query(Pdr).filter(Pdr.status == "active", Pdr.is_open.is_(True)).count()

    def in_window(op: Operation, start: datetime, end: datetime) -> bool:
        moment = datetime.fromisoformat(op.created_at)
        return start <= moment < end

    recent_start = now - timedelta(days=15)
    previous_start = now - timedelta(days=30)

    def count(predicate, start, end):
        return sum(1 for op in ops if predicate(op) and in_window(op, start, end))

    def pack(label, total, predicate):
        current = count(predicate, recent_start, now + timedelta(minutes=1))
        previous = count(predicate, previous_start, recent_start)
        return {"label": label, "value": total, "delta": _delta(current, previous)}

    withdrawals = [op for op in ops if op.type == "withdrawal"]
    deposits = [op for op in ops if op.type == "deposit"]
    accepted_states = {"accepted", "payment_pending", "payment_confirmed", "cash_delivered", "completed"}
    positives = [op for op in ops if op.status in accepted_states]
    refused = [op for op in ops if op.status == "refused"]
    rate = round(len(positives) / (len(positives) + len(refused)) * 100, 1) if positives or refused else 0
    return {
        "users": pack("Utilisateurs", users, lambda op: True),
        "active_pdr": {"label": "PDR actifs", "value": active_pdr, "delta": None},
        "transactions": pack("Transactions", len(ops), lambda op: True),
        "withdrawals": pack("Retraits", len(withdrawals), lambda op: op.type == "withdrawal"),
        "deposits": pack("Dépôts", len(deposits), lambda op: op.type == "deposit"),
        "pending": {"label": "Demandes en attente", "value": sum(1 for op in ops if op.status == "pending"), "delta": None},
        "refused": {"label": "Demandes refusées", "value": len(refused), "delta": None},
        "completed": {"label": "Transactions terminées", "value": sum(1 for op in ops if op.status == "completed"), "delta": None},
        "acceptance_rate": rate,
        "banner": settings_payload(db)["banner"],
    }


def charts(db: Session) -> dict:
    rate = float(settings_payload(db)["usd_cdf_rate"])
    ops = db.query(Operation).all()
    today = datetime.now(KINSHASA).date()
    days = [(today - timedelta(days=offset)) for offset in range(29, -1, -1)]
    daily = []
    for day in days:
        key = day.isoformat()
        totals = {
            "CDF": {"withdrawals": 0.0, "deposits": 0.0},
            "USD": {"withdrawals": 0.0, "deposits": 0.0},
        }
        for op in ops:
            if op.created_at[:10] != key or op.currency not in totals:
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
    for op in ops:
        operators[op.network] += 1
        currencies[op.currency] += 1
    operator_rows = [
        {"network": key, "label": network_label(key), "count": value}
        for key, value in sorted(operators.items(), key=lambda item: -item[1])
    ]
    ranking: dict[int, dict] = {}
    for op in ops:
        if op.status in {"refused", "cancelled", "expired", "pending"}:
            continue
        bucket = ranking.setdefault(op.pdr_id, {"pdr_id": op.pdr_id, "name": op.pdr_name, "count": 0})
        bucket["count"] += 1
    top = sorted(ranking.values(), key=lambda item: -item["count"])[:5]
    accepted_states = {"accepted", "payment_pending", "payment_confirmed", "cash_delivered", "completed"}
    positives = sum(1 for op in ops if op.status in accepted_states)
    refused = sum(1 for op in ops if op.status == "refused")
    return {
        "daily": daily,
        "operators": operator_rows,
        "currencies": [{"currency": key, "count": value} for key, value in currencies.items()],
        "acceptance": {"accepted": positives, "refused": refused},
        "top_pdrs": top,
        "usd_cdf_rate": rate,
    }


def reports(db: Session, date_from: str | None, date_to: str | None) -> dict:
    rate = float(settings_payload(db)["usd_cdf_rate"])
    ops = db.query(Operation).all()
    selected = []
    for op in ops:
        if date_from and op.created_at[:10] < date_from:
            continue
        if date_to and op.created_at[:10] > date_to:
            continue
        selected.append(op)

    def bucket(key_fn):
        grouped: dict[str, dict] = {}
        for op in selected:
            key = key_fn(op)
            row = grouped.setdefault(key, {"key": key, "count": 0, "usd": 0.0, "cdf": 0.0})
            row["count"] += 1
            if op.currency == "USD":
                row["usd"] += op.amount
            else:
                row["cdf"] += op.amount
        return list(grouped.values())

    return {
        "count": len(selected),
        "by_type": bucket(lambda op: op.type),
        "by_network": bucket(lambda op: network_label(op.network)),
        "by_commune": bucket(lambda op: op.pdr_commune),
        "by_status": bucket(lambda op: op.status),
        "usd_cdf_rate": rate,
    }


def list_users(db: Session) -> list[dict]:
    users = db.query(User).order_by(User.created_at.desc()).all()
    payload = []
    for user in users:
        numbers = db.query(PhoneNumber).filter(PhoneNumber.user_id == user.id).all()
        count = db.query(Operation).filter(Operation.user_id == user.id).count()
        payload.append(user_dict(user, numbers, count))
    return payload


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
