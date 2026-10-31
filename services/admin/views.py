"""Contrats du service Administration."""

from pydantic import BaseModel, Field


class AdminWrite(BaseModel):
    name: str = Field(min_length=2)
    email: str
    password: str = Field(min_length=8, max_length=80)
    role: str = "support"


class AdminPatch(BaseModel):
    name: str | None = None
    role: str | None = None
    status: str | None = None


class SettingsWrite(BaseModel):
    fee_percent: float | None = None
    token_minutes: int | None = None
    usd_cdf_rate: float | None = None
    app_version: str | None = None
    app_min_version: str | None = None
    app_download_url: str | None = None
    app_update_message: str | None = None
