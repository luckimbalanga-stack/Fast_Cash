"""Contrats d'entrée du service PDR."""

from pydantic import BaseModel, Field


class PdrWrite(BaseModel):
    name: str = Field(min_length=2)
    manager_name: str = Field(min_length=2)
    phone: str
    address: str = Field(min_length=3)
    commune: str = Field(min_length=2)
    city: str = "Kinshasa"
    lat: float
    lng: float
    networks: list[str] = ["orange", "airtel", "mpesa", "afrimoney"]
    status: str = "active"
    is_open: bool = True
    accepts_deposits: bool = True
    opening_hours: str = "07:00 - 20:00"
    usd_declared: float = 0
    cdf_declared: float = 0
    code: str | None = None


class PdrPatch(BaseModel):
    name: str | None = None
    manager_name: str | None = None
    phone: str | None = None
    address: str | None = None
    commune: str | None = None
    city: str | None = None
    lat: float | None = None
    lng: float | None = None
    networks: list[str] | None = None
    status: str | None = None
    is_open: bool | None = None
    accepts_deposits: bool | None = None
    opening_hours: str | None = None


class AvailabilityWrite(BaseModel):
    usd_declared: float | None = None
    cdf_declared: float | None = None
    accepts_deposits: bool | None = None
    networks: list[str] | None = None
    is_open: bool | None = None


class LiquidityMove(BaseModel):
    currency: str
    amount: float


class RatingWrite(BaseModel):
    user_id: int
    user_name: str
    operation_id: int
    stars: int = Field(ge=1, le=5)
    comment: str = ""
