"""Contrats du service Administration (schémas OpenAPI / Swagger)."""

from pydantic import BaseModel, Field


class AdminWrite(BaseModel):
    name: str = Field(min_length=2, description="Nom affiché de l’administrateur")
    email: str = Field(description="E-mail de connexion")
    password: str = Field(min_length=8, max_length=80, description="Mot de passe (8 caractères min.)")
    role: str = Field(default="support", description="Rôle admin : support | admin")


class AdminPatch(BaseModel):
    name: str | None = Field(default=None, description="Nouveau nom")
    role: str | None = Field(default=None, description="Nouveau rôle")
    status: str | None = Field(default=None, description="Statut : active | inactive")


class CommissionRangeWrite(BaseModel):
    """Plage de commission PDR (montants saisis en USD, coupés en CDF via le taux plateforme)."""

    min_usd: float = Field(
        gt=0,
        description="X — montant minimum de retrait (USD). Inclus.",
        examples=[1],
    )
    max_usd: float = Field(
        gt=0,
        description="Y — montant maximum de retrait (USD). Inclus. Doit être > min_usd.",
        examples=[10],
    )
    cut_usd: float = Field(
        gt=0,
        description=(
            "Z — commission coupée dans la liquidité CDF du PDR (USD convertis au taux usd_cdf_rate). "
            "Le % affiché côté admin = cut_usd / max_usd."
        ),
        examples=[0.5],
    )

    model_config = {
        "json_schema_extra": {
            "examples": [
                {"min_usd": 1, "max_usd": 10, "cut_usd": 0.5},
                {"min_usd": 11, "max_usd": 50, "cut_usd": 1},
            ]
        }
    }


class SettingsWrite(BaseModel):
    """Mise à jour partielle des paramètres globaux. Au moins une plage de commission est obligatoire."""

    fee_percent: float | None = Field(
        default=None,
        ge=0,
        le=10,
        description="Frais client (%) et seuil de couverture liquidité PDR (0–10).",
    )
    token_minutes: int | None = Field(default=None, ge=5, le=180, description="Validité historique du jeton (minutes).")
    usd_cdf_rate: float | None = Field(
        default=None,
        ge=100,
        le=20000,
        description="Taux indicatif 1 USD → CDF. Sert aussi à convertir les plages de commission.",
    )
    search_radius_m: int | None = Field(default=None, ge=100, le=20000, description="Rayon de recherche / scan de zone (mètres).")
    pdr_offer_seconds: int | None = Field(
        default=None,
        ge=5,
        le=120,
        description="Délai d’acceptation / refus d’une offre pending par le PDR (secondes).",
    )
    app_version: str | None = Field(default=None, description="Version mobile publiée (popup de mise à jour).")
    app_min_version: str | None = Field(default=None, description="Version minimale acceptée (mise à jour forcée).")
    app_download_url: str | None = Field(default=None, description="URL HTTPS de téléchargement de l’APK.")
    app_update_message: str | None = Field(default=None, description="Message affiché dans la popup de mise à jour.")
    commission_ranges: list[CommissionRangeWrite] | None = Field(
        default=None,
        min_length=1,
        description=(
            "Plages de commission PDR (au moins une). Pas de chevauchement : "
            "ex. 1–10 puis 9–15 est refusé ; 11–15 est accepté. "
            "Sur un retrait réussi, la liquidité CDF du PDR est diminuée de Z (converti), pas du montant retiré."
        ),
    )


class UserImportRow(BaseModel):
    name: str = Field(min_length=2)
    phone: str = Field(description="Numéro mobile RDC (9 chiffres nationaux ou +243…)")
    network: str | None = Field(default=None, description="orange | airtel | mpesa | afrimoney")
    status: str | None = "active"


class UserImportBody(BaseModel):
    users: list[UserImportRow] = Field(min_length=1)
