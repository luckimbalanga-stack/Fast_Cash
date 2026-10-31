"""Comptes initiaux de mise en service. Aucune opération historique."""

from datetime import datetime

from shared.db import SessionLocal
from shared.models import AdminUser, Pdr, PhoneNumber, Setting, User
from shared.utils import KINSHASA, hash_password

INITIAL_ADMIN_PASSWORD = "FastCash-2026"

APP_UPDATE_DEFAULTS = {
    "app_version": "1.0.0",
    "app_min_version": "1.0.0",
    "app_download_url": "",
    "app_update_message": "Une nouvelle version de Fast-Cash est disponible. Téléchargez-la pour continuer.",
}


def ensure_initial_admin_password() -> None:
    db = SessionLocal()
    try:
        admin = db.query(AdminUser).filter(AdminUser.email == "admin@fastcash.cd").one_or_none()
        if admin and not (admin.password_hash or "").strip():
            admin.password_hash = hash_password(INITIAL_ADMIN_PASSWORD)
            db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def ensure_app_update_settings() -> None:
    """Crée les clés de mise à jour mobile si elles manquent encore."""
    db = SessionLocal()
    try:
        for key, value in APP_UPDATE_DEFAULTS.items():
            if db.get(Setting, key) is None:
                db.add(Setting(key=key, value=value))
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def ensure_default_ratings() -> None:
    """Un point sans avis réel reste affiché à 5 étoiles."""
    db = SessionLocal()
    try:
        pending = db.query(Pdr).filter(Pdr.rating_count == 0, Pdr.rating_avg < 5).all()
        for pdr in pending:
            pdr.rating_avg = 5
        if pending:
            db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def seed_if_empty() -> None:
    db = SessionLocal()
    try:
        if db.query(User).count() or db.query(Pdr).count() or db.query(AdminUser).count():
            return
        _seed(db)
        db.commit()
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def _seed(db) -> None:
    now = datetime.now(KINSHASA).replace(microsecond=0).isoformat()
    user = User(name="Jean Mwamba", phone="+243810123456", status="active", created_at=now)
    db.add(user)
    db.flush()
    db.add(
        PhoneNumber(
            user_id=user.id,
            phone=user.phone,
            network="orange",
            is_primary=True,
            verified=True,
            created_at=now,
        )
    )
    db.add(
        Pdr(
            code="FC-PDR-001",
            name="PDR Gombe Centre",
            manager_name="Aline Mputu",
            phone="+243815000001",
            address="12 Avenue du Commerce",
            commune="Gombe",
            city="Kinshasa",
            lat=-4.3052,
            lng=15.3048,
            usd_declared=500,
            cdf_declared=1_500_000,
            usd_reserved=0,
            cdf_reserved=0,
            accepts_deposits=True,
            networks="orange,airtel,mpesa,afrimoney",
            status="active",
            is_open=True,
            opening_hours="07:00 - 20:00",
            rating_avg=5,
            rating_count=0,
            created_at=now,
        )
    )
    db.add(
        AdminUser(
            name="Admin Fast-Cash",
            email="admin@fastcash.cd",
            password_hash=hash_password(INITIAL_ADMIN_PASSWORD),
            role="superadmin",
            status="active",
            created_at=now,
        )
    )
    db.add_all(
        [
            Setting(key="fee_percent", value="1"),
            Setting(key="token_minutes", value="30"),
            Setting(key="usd_cdf_rate", value="2880"),
            Setting(key="app_version", value="1.0.0"),
            Setting(key="app_min_version", value="1.0.0"),
            Setting(key="app_download_url", value=""),
            Setting(
                key="app_update_message",
                value="Une nouvelle version de Fast-Cash est disponible. Téléchargez-la pour continuer.",
            ),
        ]
    )
