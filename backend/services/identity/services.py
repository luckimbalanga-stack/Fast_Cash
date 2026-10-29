"""Règles métier du service Identité."""

import hashlib
import os
import secrets
from datetime import datetime

from fastapi import HTTPException
from sqlalchemy.orm import Session

from shared.models import AdminUser, OtpChallenge, Pdr, PhoneNumber, User
from shared.serialize import admin_dict, phone_dict, pdr_dict, user_dict
from shared.utils import (
    KINSHASA,
    NETWORKS,
    detect_network,
    minutes_from_now,
    network_label,
    normalize_phone,
    now_iso,
    parse_iso,
    verify_password,
)


def _otp_hash(code: str) -> str:
    return hashlib.sha256(code.strip().encode()).hexdigest()


def _issue_otp(db: Session, phone: str, purpose: str) -> dict:
    code = f"{secrets.randbelow(1_000_000):06d}"
    db.add(OtpChallenge(phone=phone, purpose=purpose, code=_otp_hash(code), expires_at=minutes_from_now(5), consumed=False))
    payload = {
        "phone": phone,
        "purpose": purpose,
        "channel": "sms",
        "message": "Un code de vérification a été envoyé.",
    }
    if os.environ.get("FASTCASH_SMS", "console") == "console":
        print(f"Fast-Cash — code de vérification pour {phone} : {code}", flush=True)
        payload["channel"] = "console"
        payload["preview_code"] = code
        payload["message"] = "La passerelle SMS n'est pas encore branchée. Utilisez le code affiché pour ce test."
    return payload


def _user_by_login_phone(db: Session, phone: str) -> User | None:
    user = db.query(User).filter(User.phone == phone).one_or_none()
    if user:
        return user
    number = (
        db.query(PhoneNumber)
        .filter(PhoneNumber.phone == phone, PhoneNumber.verified.is_(True))
        .one_or_none()
    )
    if not number:
        return None
    return db.get(User, number.user_id)


def _numbers(db: Session, user_id: int) -> list[PhoneNumber]:
    return (
        db.query(PhoneNumber)
        .filter(PhoneNumber.user_id == user_id)
        .order_by(PhoneNumber.is_primary.desc(), PhoneNumber.id.asc())
        .all()
    )


def present_user(db: Session, user: User) -> dict:
    return user_dict(user, _numbers(db, user.id))


def request_otp(db: Session, phone_raw: str, purpose: str, name: str | None = None) -> dict:
    phone = normalize_phone(phone_raw)
    if purpose not in {"login", "register"}:
        raise HTTPException(status_code=400, detail="Finalité de vérification inconnue.")
    if purpose == "register":
        if db.query(Pdr).filter(Pdr.phone == phone).first() or _user_by_login_phone(db, phone):
            raise HTTPException(status_code=400, detail="Ce numéro est déjà associé à un compte.")
        if name is not None and len(name.strip()) < 2:
            raise HTTPException(status_code=400, detail="Indiquez votre nom complet.")
        payload = _issue_otp(db, phone, purpose)
        payload["role"] = "user"
        return payload
    pdr = db.query(Pdr).filter(Pdr.phone == phone).one_or_none()
    if pdr:
        if pdr.status != "active":
            raise HTTPException(status_code=403, detail="Ce point de retrait est désactivé.")
        payload = _issue_otp(db, phone, "pdr")
        payload["role"] = "pdr"
        return payload
    user = _user_by_login_phone(db, phone)
    if not user:
        raise HTTPException(status_code=404, detail="Aucun compte pour ce numéro. Créez un compte.")
    if user.status != "active":
        raise HTTPException(status_code=403, detail="Ce compte est suspendu.")
    payload = _issue_otp(db, phone, "login")
    payload["role"] = "user"
    return payload


def _consume_otp(db: Session, phone: str, purpose: str, code: str) -> None:
    challenge = (
        db.query(OtpChallenge)
        .filter(OtpChallenge.phone == phone, OtpChallenge.purpose == purpose, OtpChallenge.consumed.is_(False))
        .order_by(OtpChallenge.id.desc())
        .first()
    )
    if not challenge:
        raise HTTPException(status_code=400, detail="Demandez d'abord un code de vérification.")
    if parse_iso(challenge.expires_at) < datetime.now(KINSHASA):
        raise HTTPException(status_code=400, detail="Code expiré. Demandez un nouveau code.")
    if _otp_hash(code) != challenge.code:
        raise HTTPException(status_code=400, detail="Code incorrect.")
    challenge.consumed = True


def verify_otp(db: Session, phone_raw: str, code: str, purpose: str, name: str | None, network: str | None) -> dict:
    phone = normalize_phone(phone_raw)
    _consume_otp(db, phone, purpose, code)
    if purpose == "register":
        cleaned = (name or "").strip()
        if len(cleaned) < 2:
            raise HTTPException(status_code=400, detail="Indiquez votre nom complet.")
        chosen = network or detect_network(phone)
        if chosen not in NETWORKS:
            raise HTTPException(status_code=400, detail="Sélectionnez le réseau Mobile Money.")
        user = User(name=cleaned, phone=phone, status="active", created_at=now_iso())
        db.add(user)
        db.flush()
        db.add(
            PhoneNumber(
                user_id=user.id,
                phone=phone,
                network=chosen,
                is_primary=True,
                verified=True,
                created_at=now_iso(),
            )
        )
        db.flush()
        return {"token": f"user:{user.id}", "user": present_user(db, user), "created": True}
    if purpose != "login":
        raise HTTPException(status_code=400, detail="Finalité de vérification inconnue.")
    user = _user_by_login_phone(db, phone)
    if not user or user.status != "active":
        raise HTTPException(status_code=403, detail="Connexion impossible pour ce compte.")
    return {"token": f"user:{user.id}", "user": present_user(db, user), "created": False}


def request_pdr_otp(db: Session, phone_raw: str) -> dict:
    phone = normalize_phone(phone_raw)
    pdr = db.query(Pdr).filter(Pdr.phone == phone).one_or_none()
    if not pdr:
        raise HTTPException(status_code=404, detail="Aucun point de retrait pour ce numéro.")
    if pdr.status != "active":
        raise HTTPException(status_code=403, detail="Ce point de retrait est désactivé.")
    payload = _issue_otp(db, phone, "pdr")
    payload["pdr_name"] = pdr.name
    return payload


def verify_pdr_otp(db: Session, phone_raw: str, code: str) -> dict:
    phone = normalize_phone(phone_raw)
    _consume_otp(db, phone, "pdr", code)
    pdr = db.query(Pdr).filter(Pdr.phone == phone).one_or_none()
    if not pdr or pdr.status != "active":
        raise HTTPException(status_code=403, detail="Connexion PDR impossible.")
    return {"token": f"pdr:{pdr.id}", "pdr": pdr_dict(pdr)}


def enter_admin(db: Session, email: str, password: str) -> dict:
    admin = db.query(AdminUser).filter(AdminUser.email == email.strip().lower()).one_or_none()
    if not admin or admin.status != "active" or not verify_password(password, admin.password_hash or ""):
        raise HTTPException(status_code=401, detail="E-mail ou mot de passe incorrect.")
    return {"token": f"admin:{admin.id}", "admin": admin_dict(admin)}


def get_me(db: Session, user_id: int) -> dict:
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
    return present_user(db, user)


def list_users(db: Session) -> list[dict]:
    users = db.query(User).order_by(User.created_at.desc()).all()
    return [present_user(db, user) for user in users]


def update_status(db: Session, user_id: int, status: str) -> dict:
    if status not in {"active", "suspended"}:
        raise HTTPException(status_code=400, detail="Statut inconnu.")
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
    user.status = status
    return present_user(db, user)


def detect(phone_raw: str, network: str | None = None) -> dict:
    phone = normalize_phone(phone_raw)
    guessed = detect_network(phone)
    chosen = network if network in NETWORKS else guessed
    return {
        "phone": phone,
        "detected": guessed,
        "detected_label": network_label(guessed),
        "network": chosen,
        "network_label": network_label(chosen),
    }


def _chosen_network(phone: str, network: str | None) -> str:
    chosen = network or detect_network(phone)
    if chosen not in NETWORKS:
        raise HTTPException(status_code=400, detail="Sélectionnez le réseau Mobile Money.")
    return chosen


def begin_add_phone(db: Session, user_id: int, phone_raw: str, network: str | None) -> dict:
    phone = normalize_phone(phone_raw)
    existing = db.query(PhoneNumber).filter(PhoneNumber.phone == phone).one_or_none()
    if existing and existing.verified:
        raise HTTPException(status_code=400, detail="Ce numéro est déjà enregistré.")
    chosen = _chosen_network(phone, network)
    issued = _issue_otp(db, phone, f"phone-add:{user_id}")
    return {
        "phone": phone,
        "network": chosen,
        "network_label": network_label(chosen),
        "preview_code": issued.get("preview_code"),
        "channel": issued["channel"],
        "message": issued["message"],
    }


def confirm_add_phone(db: Session, user_id: int, phone_raw: str, network: str | None, code: str) -> dict:
    phone = normalize_phone(phone_raw)
    chosen = _chosen_network(phone, network)
    _consume_otp(db, phone, f"phone-add:{user_id}", code)
    existing = db.query(PhoneNumber).filter(PhoneNumber.phone == phone).one_or_none()
    if existing and existing.verified:
        raise HTTPException(status_code=400, detail="Ce numéro est déjà enregistré.")
    if existing and existing.user_id != user_id:
        db.delete(existing)
        db.flush()
        existing = None
    has_verified = (
        db.query(PhoneNumber)
        .filter(PhoneNumber.user_id == user_id, PhoneNumber.verified.is_(True), PhoneNumber.id != (existing.id if existing else 0))
        .count()
        > 0
    )
    if existing:
        existing.network = chosen
        existing.verified = True
        if not has_verified:
            existing.is_primary = True
        return phone_dict(existing)
    row = PhoneNumber(
        user_id=user_id,
        phone=phone,
        network=chosen,
        is_primary=not has_verified,
        verified=True,
        created_at=now_iso(),
    )
    db.add(row)
    db.flush()
    return phone_dict(row)


def verify_phone(db: Session, user_id: int, phone_id: int, code: str) -> dict:
    row = db.get(PhoneNumber, phone_id)
    if not row or row.user_id != user_id:
        raise HTTPException(status_code=404, detail="Numéro introuvable.")
    _consume_otp(db, row.phone, f"phone:{row.id}", code)
    row.verified = True
    if not db.query(PhoneNumber).filter(PhoneNumber.user_id == user_id, PhoneNumber.is_primary.is_(True), PhoneNumber.id != row.id).first():
        row.is_primary = True
    return phone_dict(row)


def set_primary(db: Session, user_id: int, phone_id: int) -> dict:
    row = db.get(PhoneNumber, phone_id)
    if not row or row.user_id != user_id:
        raise HTTPException(status_code=404, detail="Numéro introuvable.")
    if not row.verified:
        raise HTTPException(status_code=400, detail="Vérifiez ce numéro avant de le définir comme principal.")
    db.query(PhoneNumber).filter(PhoneNumber.user_id == user_id).update({"is_primary": False})
    row.is_primary = True
    return present_user(db, db.get(User, user_id))


def update_network(db: Session, user_id: int, phone_id: int, network: str) -> dict:
    if network not in NETWORKS:
        raise HTTPException(status_code=400, detail="Réseau Mobile Money inconnu.")
    row = db.get(PhoneNumber, phone_id)
    if not row or row.user_id != user_id:
        raise HTTPException(status_code=404, detail="Numéro introuvable.")
    row.network = network
    return phone_dict(row)


def delete_phone(db: Session, user_id: int, phone_id: int) -> dict:
    row = db.get(PhoneNumber, phone_id)
    if not row or row.user_id != user_id:
        raise HTTPException(status_code=404, detail="Numéro introuvable.")
    if row.is_primary:
        raise HTTPException(status_code=400, detail="Le numéro principal ne peut pas être supprimé.")
    siblings = db.query(PhoneNumber).filter(PhoneNumber.user_id == user_id).count()
    if siblings <= 1:
        raise HTTPException(status_code=400, detail="Conservez au moins un numéro sur le compte.")
    db.delete(row)
    return {"deleted": phone_id}
