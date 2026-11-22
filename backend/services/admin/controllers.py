"""Contrôleur HTTP du service Administration."""

from fastapi import APIRouter, Depends, Header
from sqlalchemy.orm import Session

from services.admin import services
from services.admin.views import AdminPatch, AdminWrite, SettingsWrite, UserImportBody
from shared.db import get_db
from shared.utils import require_roles

router = APIRouter()


def _admin(authorization: str | None) -> None:
    require_roles(authorization, "admin")


@router.get("/admin/dashboard")
def dashboard(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.dashboard(db)


@router.get(
    "/admin/charts",
    summary="Graphiques dashboard",
    description=(
        "`daily` : volumes retraits/dépôts CDF & USD. "
        "`pdr_daily.withdrawals` / `cuts` : coupes commission **retrait** (CDF). "
        "`pdr_daily.deposits` : coupes commission **dépôt** (CDF). Filtre optionnel opérateur / dates."
    ),
    tags=["Admin"],
)
def charts(
    date_from: str | None = None,
    date_to: str | None = None,
    network: str | None = None,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    _admin(authorization)
    return services.charts(db, date_from, date_to, network)


@router.get("/admin/reports")
def reports(
    date_from: str | None = None,
    date_to: str | None = None,
    network: str | None = None,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    _admin(authorization)
    return services.reports(db, date_from, date_to, network)


@router.get("/admin/users")
def users(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.list_users(db)


@router.post("/admin/users/import")
def import_users(body: UserImportBody, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.import_users(db, [row.model_dump() for row in body.users])


@router.get("/admin/admins")
def admins(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.list_admins(db)


@router.post("/admin/admins")
def create_admin(body: AdminWrite, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.create_admin(db, body.model_dump())


@router.patch("/admin/admins/{admin_id}")
def update_admin(admin_id: int, body: AdminPatch, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.update_admin(db, admin_id, body.model_dump(exclude_unset=True))


@router.get(
    "/settings",
    summary="Lire les paramètres globaux",
    description=(
        "Retourne frais, taux USD/CDF, rayon, délai offre PDR, versions app, et "
        "`commission_ranges` enrichies (équivalents CDF + % coupe vs max de plage)."
    ),
    tags=["Paramètres"],
)
def settings(db: Session = Depends(get_db)):
    return services.settings_payload(db)


@router.put(
    "/settings",
    summary="Mettre à jour les paramètres",
    description=(
        "Mise à jour partielle. Pour `commission_ranges` : au moins une plage, sans chevauchement "
        "(ex. 1–10 puis 11–15). Auth admin requise."
    ),
    tags=["Paramètres"],
)
def update_settings(body: SettingsWrite, authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    _admin(authorization)
    return services.update_settings(db, body.model_dump(exclude_unset=True))
