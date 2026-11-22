"""Cache Redis partagé (Upstash / Redis Cloud / Redis local) + repli mémoire.

Active si ``REDIS_URL`` (ou ``UPSTASH_REDIS_URL``) est défini.
Sans Redis, le cache mémoire process-local reste disponible — aucun crash.
"""

from __future__ import annotations

import json
import os
import time
from threading import Lock
from typing import Any

_PREFIX = "fc:"
_DEFAULT_TTL = 30

_client = None
_client_failed = False
_client_lock = Lock()

_memory: dict[str, tuple[float, str]] = {}
_memory_lock = Lock()


def redis_url() -> str:
    return (
        (os.environ.get("REDIS_URL") or "").strip()
        or (os.environ.get("UPSTASH_REDIS_URL") or "").strip()
    )


def redis_configured() -> bool:
    return bool(redis_url())


def _connect():
    """Lazy connect — un seul essai si l’URL est absente / invalide."""
    global _client, _client_failed
    if _client is not None:
        return _client
    if _client_failed:
        return None
    url = redis_url()
    if not url:
        _client_failed = True
        return None
    with _client_lock:
        if _client is not None:
            return _client
        if _client_failed:
            return None
        try:
            import redis

            client = redis.Redis.from_url(
                url,
                decode_responses=True,
                socket_connect_timeout=1.5,
                socket_timeout=1.5,
                health_check_interval=30,
            )
            client.ping()
            _client = client
            return _client
        except Exception:
            _client_failed = True
            _client = None
            return None


def redis_available() -> bool:
    return _connect() is not None


def redis_status() -> dict[str, Any]:
    configured = redis_configured()
    if not configured:
        return {"configured": False, "connected": False, "backend": "memory"}
    ok = redis_available()
    return {
        "configured": True,
        "connected": ok,
        "backend": "redis" if ok else "memory-fallback",
    }


def _full_key(key: str) -> str:
    return key if key.startswith(_PREFIX) else f"{_PREFIX}{key}"


def _memory_get(key: str) -> str | None:
    now = time.monotonic()
    with _memory_lock:
        row = _memory.get(key)
        if not row:
            return None
        expires_at, payload = row
        if expires_at < now:
            _memory.pop(key, None)
            return None
        return payload


def _memory_set(key: str, payload: str, ttl: int) -> None:
    with _memory_lock:
        _memory[key] = (time.monotonic() + max(1, ttl), payload)


def _memory_delete(keys: list[str]) -> None:
    with _memory_lock:
        for key in keys:
            _memory.pop(key, None)


def get_json(key: str) -> Any | None:
    full = _full_key(key)
    cached = _memory_get(full)
    if cached is not None:
        try:
            return json.loads(cached)
        except json.JSONDecodeError:
            pass

    client = _connect()
    if client is not None:
        try:
            raw = client.get(full)
            if raw:
                _memory_set(full, raw, min(5, _DEFAULT_TTL))
                return json.loads(raw)
        except Exception:
            pass
    return None


def set_json(key: str, value: Any, ttl: int = _DEFAULT_TTL) -> None:
    full = _full_key(key)
    try:
        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"), default=str)
    except TypeError:
        return
    _memory_set(full, payload, ttl)
    client = _connect()
    if client is None:
        return
    try:
        client.setex(full, max(1, int(ttl)), payload)
    except Exception:
        return


def delete(*keys: str) -> None:
    full_keys = [_full_key(key) for key in keys if key]
    if not full_keys:
        return
    _memory_delete(full_keys)
    client = _connect()
    if client is None:
        return
    try:
        client.delete(*full_keys)
    except Exception:
        return


def delete_prefix(prefix: str) -> None:
    """Invalide toutes les clés ``fc:{prefix}*`` (mémoire + Redis)."""
    needle = _full_key(prefix)
    with _memory_lock:
        doomed = [key for key in _memory if key.startswith(needle)]
        for key in doomed:
            _memory.pop(key, None)

    client = _connect()
    if client is None:
        return
    try:
        cursor = 0
        while True:
            cursor, found = client.scan(cursor=cursor, match=f"{needle}*", count=100)
            if found:
                client.delete(*found)
            if cursor == 0:
                break
    except Exception:
        return


# --- Clés métier -----------------------------------------------------------

KEY_SETTINGS_MAP = "settings:map"
KEY_SETTINGS_PAYLOAD = "settings:payload"
KEY_ADMIN_DASHBOARD = "admin:dashboard"


def charts_cache_key(date_from: str | None, date_to: str | None, network: str | None) -> str:
    return f"admin:charts:{date_from or ''}:{date_to or ''}:{network or ''}"


def invalidate_settings() -> None:
    delete(KEY_SETTINGS_MAP, KEY_SETTINGS_PAYLOAD)


def invalidate_admin_stats() -> None:
    delete(KEY_ADMIN_DASHBOARD)
    delete_prefix("admin:charts:")
