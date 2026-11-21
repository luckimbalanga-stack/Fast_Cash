"""Contrats d'entrée du service Opérations (schémas OpenAPI / Swagger)."""

from pydantic import BaseModel, Field


class OperationCreate(BaseModel):
    pdr_id: int = Field(description="Identifiant du point de retrait ciblé")
    phone: str = Field(description="Numéro Mobile Money vérifié du client")
    amount: float = Field(gt=0, description="Montant de l’opération")
    currency: str = Field(description="USD ou CDF")
    type: str = Field(default="withdrawal", description="withdrawal | deposit")


class TokenRedeem(BaseModel):
    code: str = Field(description="Code / ticket QR à scanner (retrait ou dépôt)")


class PinBody(BaseModel):
    pin: str = Field(min_length=4, max_length=8, description="Code PIN Mobile Money (non stocké)")


class RatingBody(BaseModel):
    stars: int = Field(ge=1, le=5, description="Note de 1 à 5")
    comment: str = Field(default="", description="Commentaire optionnel")
