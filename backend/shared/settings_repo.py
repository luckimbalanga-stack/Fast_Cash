"""Accès typé aux paramètres globaux (noyau partagé — DIP / SRP) + cache Redis/TTL."""

import time
from threading import Lock

from sqlalchemy.orm import Session

from shared.commission_ranges import (
    DEFAULT_COMMISSION_RANGES,
    dumps_ranges,
    parse_commission_ranges,
    ranges_with_display,
    validate_commission_ranges,
)
from shared.models import Setting
from shared import redis_cache

APP_SETTING_DEFAULTS = {
    "app_version": "1.0.0",
    "app_min_version": "1.0.0",
    "app_download_url": "",
    "app_update_message": "Une nouvelle version de Fast-Cash est disponible. Téléchargez-la pour continuer.",
    "pdr_offer_seconds": "30",
    "commission_ranges": dumps_ranges(DEFAULT_COMMISSION_RANGES),
}

_CACHE_TTL_S = 30
_cache_lock = Lock()
_cache_payload: dict | None = None
_cache_raw: dict[str, str] | None = None
_cache_at = 0.0


def invalidate_settings_cache() -> None:
    global _cache_payload, _cache_raw, _cache_at
    with _cache_lock:
        _cache_payload = None
        _cache_raw = None
        _cache_at = 0.0
    redis_cache.invalidate_settings()
    # Les stats admin dépendent des plages / taux.
    redis_cache.invalidate_admin_stats()


def settings_map(db: Session) -> dict[str, str]:
    global _cache_raw, _cache_at
    now = time.monotonic()
    with _cache_lock:
        if _cache_raw is not None and (now - _cache_at) < _CACHE_TTL_S:
            return dict(_cache_raw)

    cached = redis_cache.get_json(redis_cache.KEY_SETTINGS_MAP)
    if isinstance(cached, dict):
        with _cache_lock:
            _cache_raw = {str(k): str(v) for k, v in cached.items()}
            _cache_at = now
        return dict(_cache_raw)

    raw = {row.key: row.value for row in db.query(Setting).all()}
    redis_cache.set_json(redis_cache.KEY_SETTINGS_MAP, raw, ttl=_CACHE_TTL_S)
    with _cache_lock:
        _cache_raw = dict(raw)
        _cache_at = now
    return raw


def upsert_setting(db: Session, key: str, value: str) -> None:
    row = db.get(Setting, key)
    if not row:
        db.add(Setting(key=key, value=value))
    else:
        row.value = value
    invalidate_settings_cache()


def settings_payload(db: Session) -> dict:
    global _cache_payload, _cache_at
    now = time.monotonic()
    with _cache_lock:
        if _cache_payload is not None and (now - _cache_at) < _CACHE_TTL_S:
            return dict(_cache_payload)

    cached = redis_cache.get_json(redis_cache.KEY_SETTINGS_PAYLOAD)
    if isinstance(cached, dict) and "fee_percent" in cached:
        with _cache_lock:
            _cache_payload = dict(cached)
            _cache_at = now
        return dict(cached)

    raw = settings_map(db)
    rate = float(raw.get("usd_cdf_rate", "2880"))
    ranges_raw = raw.get("commission_ranges", APP_SETTING_DEFAULTS["commission_ranges"])
    try:
        ranges = validate_commission_ranges(parse_commission_ranges(ranges_raw))
    except Exception:
        ranges = list(DEFAULT_COMMISSION_RANGES)
    if not ranges:
        ranges = list(DEFAULT_COMMISSION_RANGES)
    payload = {
        "fee_percent": float(raw.get("fee_percent", "1")),
        "token_minutes": int(float(raw.get("token_minutes", "30"))),
        "usd_cdf_rate": rate,
        "search_radius_m": int(float(raw.get("search_radius_m", "1000"))),
        "pdr_offer_seconds": int(float(raw.get("pdr_offer_seconds", APP_SETTING_DEFAULTS.get("pdr_offer_seconds", "30")))),
        "banner": raw.get("banner", ""),
        "app_version": raw.get("app_version", APP_SETTING_DEFAULTS["app_version"]),
        "app_min_version": raw.get("app_min_version", APP_SETTING_DEFAULTS["app_min_version"]),
        "app_download_url": raw.get("app_download_url", APP_SETTING_DEFAULTS["app_download_url"]),
        "app_update_message": raw.get("app_update_message", APP_SETTING_DEFAULTS["app_update_message"]),
        "commission_ranges": ranges_with_display(ranges, rate),
    }
    redis_cache.set_json(redis_cache.KEY_SETTINGS_PAYLOAD, payload, ttl=_CACHE_TTL_S)
    with _cache_lock:
        _cache_payload = dict(payload)
        _cache_at = now
    return payload
