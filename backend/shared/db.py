"""Connexion base de données partagée (Neon Postgres ou SQLite local)."""

import os
from pathlib import Path

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker

ROOT = Path(__file__).resolve().parents[2]
BACKEND = Path(__file__).resolve().parents[1]
DATA_DIR = BACKEND / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / "fastcash.db"


def _load_env_files() -> None:
    """Charge .env.local / .env sans écraser les variables déjà définies (ex. Render)."""
    for path in (ROOT / ".env.local", ROOT / ".env", BACKEND / ".env.local", BACKEND / ".env"):
        if not path.exists():
            continue
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            if not key or key in os.environ:
                continue
            value = value.strip()
            if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
                value = value[1:-1]
            os.environ[key] = value


_load_env_files()


def _database_url() -> str:
    raw = (os.environ.get("DATABASE_URL") or "").strip()
    if not raw:
        return f"sqlite:///{DB_PATH}"
    if raw.startswith("postgres://"):
        return "postgresql+psycopg2://" + raw[len("postgres://") :]
    if raw.startswith("postgresql://"):
        return "postgresql+psycopg2://" + raw[len("postgresql://") :]
    return raw


DATABASE_URL = _database_url()
IS_SQLITE = DATABASE_URL.startswith("sqlite:")

engine_kwargs = {"future": True}
if IS_SQLITE:
    engine_kwargs["connect_args"] = {"check_same_thread": False, "timeout": 30}
else:
    # Neon / Postgres : pool sain pour Render (wake + connexions intermittentes).
    engine_kwargs.update(pool_pre_ping=True, pool_size=5, max_overflow=10)

engine = create_engine(DATABASE_URL, **engine_kwargs)


if IS_SQLITE:
    from sqlalchemy import event

    @event.listens_for(engine, "connect")
    def _sqlite_pragmas(dbapi_connection, _connection_record):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.execute("PRAGMA busy_timeout=5000")
        cursor.close()


class Base(DeclarativeBase):
    pass


SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False)


def get_db():
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _ensure_admin_password_column() -> None:
    inspector = inspect(engine)
    if "admins" not in inspector.get_table_names():
        return
    names = {column["name"] for column in inspector.get_columns("admins")}
    if "password_hash" in names:
        return
    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE admins ADD COLUMN password_hash VARCHAR(200) DEFAULT ''"))


def init_database(seed: bool = False) -> None:
    from shared import models  # noqa: F401

    Base.metadata.create_all(engine)
    _ensure_admin_password_column()
    if seed:
        from shared.seed import (
            ensure_app_update_settings,
            ensure_default_ratings,
            ensure_initial_admin_password,
            seed_if_empty,
        )

        seed_if_empty()
        ensure_initial_admin_password()
        ensure_default_ratings()
        ensure_app_update_settings()
