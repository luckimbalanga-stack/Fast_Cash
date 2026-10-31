"""Règles métier transverses : téléphone, distance, argent, temps."""

import hashlib
import hmac
import math
import random
import secrets
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import HTTPException

KINSHASA = ZoneInfo("Africa/Kinshasa")

NETWORKS = {
    "orange": "Orange Money",
    "airtel": "Airtel Money",
    "mpesa": "M-Pesa",
    "afrimoney": "AfriMoney",
}

PREFIXES = {
    "orange": {"80", "84", "85", "89"},
    "mpesa": {"81", "82", "83"},
    "afrimoney": {"90", "91"},
    "airtel": {"97", "98", "99"},
}

INTERNAL_KEY = "fastcash-internal"
SEARCH_RADII_M = [10, 20, 40, 80, 160, 320, 640, 1280, 2560, 5120, 10000]
DEMO_ORIGIN = {"lat": -4.3038, "lng": 15.3005, "label": "Kinshasa — Gombe"}


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 120_000).hex()
    return f"{salt}${digest}"


def verify_password(password: str, stored: str) -> bool:
    if not stored or "$" not in stored:
        return False
    salt, digest = stored.split("$", 1)
    check = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 120_000).hex()
    return hmac.compare_digest(check, digest)


def now_iso() -> str:
    return datetime.now(KINSHASA).replace(microsecond=0).isoformat()


def parse_iso(value: str) -> datetime:
    return datetime.fromisoformat(value)


def shift_iso(base: datetime, **kwargs) -> str:
    return (base + timedelta(**kwargs)).replace(microsecond=0).isoformat()


def minutes_from_now(minutes: int) -> str:
    return (datetime.now(KINSHASA) + timedelta(minutes=minutes)).replace(microsecond=0).isoformat()


def normalize_phone(raw: str) -> str:
    digits = "".join(ch for ch in raw if ch.isdigit())
    if digits.startswith("00243"):
        digits = digits[5:]
    elif digits.startswith("243"):
        digits = digits[3:]
    if digits.startswith("0"):
        digits = digits[1:]
    if len(digits) != 9:
        raise HTTPException(status_code=400, detail="Saisissez un numéro mobile congolais à 9 chiffres.")
    return f"+243{digits}"


def detect_network(phone: str) -> str | None:
    national = phone.replace("+243", "")
    prefix = national[:2]
    for network, prefixes in PREFIXES.items():
        if prefix in prefixes:
            return network
    return None


def network_label(network: str | None) -> str:
    if not network:
        return "Réseau inconnu"
    return NETWORKS.get(network, network)


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(a))


def eta_minutes(distance_m: float) -> int:
    km = distance_m / 1000
    return max(2, round(km * 4))


def round_money(amount: float, currency: str) -> float:
    if currency == "CDF":
        return float(round(amount))
    return float(round(amount + 1e-9, 2))


def make_reference(existing: set[str]) -> str:
    while True:
        code = f"FC-{random.randint(1000, 9999)}-{random.randint(1000, 9999)}"
        if code not in existing:
            existing.add(code)
            return code


def parse_bearer(authorization: str | None) -> tuple[str, int]:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Authentification requise.")
    token = authorization.split(" ", 1)[1].strip()
    if ":" not in token:
        raise HTTPException(status_code=401, detail="Session invalide.")
    role, raw_id = token.split(":", 1)
    if role not in {"user", "pdr", "admin"}:
        raise HTTPException(status_code=401, detail="Session invalide.")
    try:
        return role, int(raw_id)
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="Session invalide.") from exc


def require_roles(authorization: str | None, *roles: str) -> tuple[str, int]:
    role, ident = parse_bearer(authorization)
    if role not in roles:
        raise HTTPException(status_code=403, detail="Cette action n'est pas autorisée pour ce profil.")
    return role, ident
