"""Contrats d'entrée du service Opérations."""

from pydantic import BaseModel, Field


class OperationCreate(BaseModel):
    pdr_id: int
    phone: str
    amount: float
    currency: str
    type: str = "withdrawal"


class TokenRedeem(BaseModel):
    code: str


class PinBody(BaseModel):
    pin: str = Field(min_length=4, max_length=8)


class RatingBody(BaseModel):
    stars: int = Field(ge=1, le=5)
    comment: str = ""
