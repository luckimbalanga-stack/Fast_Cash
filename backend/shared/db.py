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

# Hiérarchie connexions : pool réduit par microservice (5 process × pool) pour Neon.
engine_kwargs = {"future": True}
if IS_SQLITE:
    engine_kwargs["connect_args"] = {"check_same_thread": False, "timeout": 30}
else:
    engine_kwargs.update(
        pool_pre_ping=True,
        pool_size=2,
        max_overflow=3,
        pool_recycle=280,
        pool_timeout=10,
    )

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
    """Session requête HTTP avec commit en fin de succès.

    On commit toujours (même après lecture) : un ``flush()`` vide ``session.new``,
    et un rollback conditionnel faisait disparaître OTP / tokens silencieusement.
    Les lectures pures peuvent utiliser ``get_db_readonly``.
    """
    db = SessionLocal()
    try:
        yield db
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def get_db_readonly():
    """Session lecture seule — jamais de commit réseau."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.rollback()
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


def _ensure_pdr_password_column() -> None:
    inspector = inspect(engine)
    if "pdrs" not in inspector.get_table_names():
        return
    names = {column["name"] for column in inspector.get_columns("pdrs")}
    with engine.begin() as connection:
        if "password_hash" not in names:
            connection.execute(text("ALTER TABLE pdrs ADD COLUMN password_hash VARCHAR(200) DEFAULT ''"))
        if "password_plain" not in names:
            connection.execute(text("ALTER TABLE pdrs ADD COLUMN password_plain VARCHAR(120) DEFAULT ''"))


def _ensure_otp_code_column_width() -> None:
    """Le hash SHA-256 fait 64 caractères ; l’ancien schéma VARCHAR(6) cassait Neon."""
    inspector = inspect(engine)
    if "otp_challenges" not in inspector.get_table_names():
        return
    code_col = next((column for column in inspector.get_columns("otp_challenges") if column["name"] == "code"), None)
    if not code_col:
        return
    col_type = str(code_col["type"]).upper()
    if "64" in col_type or "128" in col_type or "TEXT" in col_type:
        return
    with engine.begin() as connection:
        if IS_SQLITE:
            return
        connection.execute(text("ALTER TABLE otp_challenges ALTER COLUMN code TYPE VARCHAR(64)"))


def _ensure_perf_indexes() -> None:
    """Index composites pour hot paths (liquidité, polling, notifs)."""
    statements = [
        "CREATE INDEX IF NOT EXISTS ix_pdrs_status_is_open ON pdrs (status, is_open)",
        "CREATE INDEX IF NOT EXISTS ix_operations_pdr_updated ON operations (pdr_id, updated_at)",
        "CREATE INDEX IF NOT EXISTS ix_operations_pdr_status_created ON operations (pdr_id, status, created_at)",
        "CREATE INDEX IF NOT EXISTS ix_operations_user_status_created ON operations (user_id, status, created_at)",
        "CREATE INDEX IF NOT EXISTS ix_operations_status_created ON operations (status, created_at)",
        "CREATE INDEX IF NOT EXISTS ix_notifications_audience_target_created ON notifications (audience, target_id, created_at)",
    ]
    with engine.begin() as connection:
        for statement in statements:
            connection.execute(text(statement))


def init_database(seed: bool = False) -> None:
    from shared import models  # noqa: F401

    print(f"Fast-Cash DB : {'sqlite' if IS_SQLITE else 'postgres'}", flush=True)
    Base.metadata.create_all(engine)
    _ensure_admin_password_column()
    _ensure_pdr_password_column()
    _ensure_otp_code_column_width()
    _ensure_perf_indexes()
    if seed:
        from shared.seed import (
            ensure_app_update_settings,
            ensure_default_ratings,
            ensure_initial_admin_password,
            ensure_seed_pdr_password,
            seed_if_empty,
        )

        seed_if_empty()
        ensure_initial_admin_password()
        ensure_seed_pdr_password()
        ensure_default_ratings()
        ensure_app_update_settings()
