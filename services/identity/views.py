"""Contrats d'entrée du service Identité."""

from pydantic import BaseModel, Field


class OtpRequest(BaseModel):
    phone: str
    purpose: str = "login"
    name: str | None = None


class OtpVerify(BaseModel):
    phone: str
    code: str = Field(min_length=6, max_length=6)
    purpose: str = "login"
    name: str | None = None
    network: str | None = None


class PhoneChallenge(BaseModel):
    phone: str
    network: str | None = None


class PhoneCreate(BaseModel):
    phone: str
    network: str | None = None
    code: str = Field(min_length=6, max_length=6)


class PhoneVerify(BaseModel):
    code: str = Field(min_length=6, max_length=6)


class PhoneUpdate(BaseModel):
    network: str


class StatusUpdate(BaseModel):
    status: str


class AdminEnter(BaseModel):
    email: str
    password: str = Field(min_length=8, max_length=80)
