"""Connexion SQLite partagée par les microservices Fast-Cash."""

from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, sessionmaker

DATA_DIR = Path(__file__).resolve().parents[1] / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / "fastcash.db"

engine = create_engine(
    f"sqlite:///{DB_PATH}",
    connect_args={"check_same_thread": False, "timeout": 30},
    future=True,
)


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
    with engine.begin() as connection:
        rows = connection.exec_driver_sql("PRAGMA table_info(admins)").fetchall()
        if not rows:
            return
        names = {row[1] for row in rows}
        if "password_hash" not in names:
            connection.exec_driver_sql("ALTER TABLE admins ADD COLUMN password_hash VARCHAR(200) DEFAULT ''")


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
