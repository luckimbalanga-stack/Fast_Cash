"""Modèles de données Fast-Cash."""

from sqlalchemy import Boolean, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from shared.db import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_at: Mapped[str] = mapped_column(String(40))


class PhoneNumber(Base):
    __tablename__ = "phone_numbers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    phone: Mapped[str] = mapped_column(String(20), index=True)
    network: Mapped[str] = mapped_column(String(20))
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False)
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[str] = mapped_column(String(40))


class OtpChallenge(Base):
    __tablename__ = "otp_challenges"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    phone: Mapped[str] = mapped_column(String(20), index=True)
    purpose: Mapped[str] = mapped_column(String(30))
    code: Mapped[str] = mapped_column(String(6))
    expires_at: Mapped[str] = mapped_column(String(40))
    consumed: Mapped[bool] = mapped_column(Boolean, default=False)


class Pdr(Base):
    __tablename__ = "pdrs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(20), unique=True)
    name: Mapped[str] = mapped_column(String(140))
    manager_name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[str] = mapped_column(String(20), unique=True)
    address: Mapped[str] = mapped_column(String(200))
    commune: Mapped[str] = mapped_column(String(80), index=True)
    city: Mapped[str] = mapped_column(String(80), default="Kinshasa")
    lat: Mapped[float] = mapped_column(Float)
    lng: Mapped[float] = mapped_column(Float)
    usd_declared: Mapped[float] = mapped_column(Float, default=0)
    cdf_declared: Mapped[float] = mapped_column(Float, default=0)
    usd_reserved: Mapped[float] = mapped_column(Float, default=0)
    cdf_reserved: Mapped[float] = mapped_column(Float, default=0)
    accepts_deposits: Mapped[bool] = mapped_column(Boolean, default=True)
    networks: Mapped[str] = mapped_column(String(120), default="orange,airtel,mpesa,afrimoney")
    status: Mapped[str] = mapped_column(String(20), default="active")
    is_open: Mapped[bool] = mapped_column(Boolean, default=True)
    rating_avg: Mapped[float] = mapped_column(Float, default=5)
    rating_count: Mapped[int] = mapped_column(Integer, default=0)
    opening_hours: Mapped[str] = mapped_column(String(40), default="07:00 - 20:00")
    created_at: Mapped[str] = mapped_column(String(40))


class Rating(Base):
    __tablename__ = "ratings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    pdr_id: Mapped[int] = mapped_column(ForeignKey("pdrs.id"), index=True)
    user_id: Mapped[int] = mapped_column(Integer)
    user_name: Mapped[str] = mapped_column(String(120))
    operation_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    stars: Mapped[int] = mapped_column(Integer)
    comment: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[str] = mapped_column(String(40))


class Operation(Base):
    __tablename__ = "operations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    reference: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    type: Mapped[str] = mapped_column(String(20), index=True)
    user_id: Mapped[int] = mapped_column(Integer, index=True)
    user_name: Mapped[str] = mapped_column(String(120))
    pdr_id: Mapped[int] = mapped_column(Integer, index=True)
    pdr_name: Mapped[str] = mapped_column(String(140))
    pdr_address: Mapped[str] = mapped_column(String(200))
    pdr_commune: Mapped[str] = mapped_column(String(80))
    pdr_lat: Mapped[float] = mapped_column(Float)
    pdr_lng: Mapped[float] = mapped_column(Float)
    pdr_hours: Mapped[str] = mapped_column(String(40))
    pdr_phone: Mapped[str] = mapped_column(String(20), default="")
    phone: Mapped[str] = mapped_column(String(20))
    network: Mapped[str] = mapped_column(String(20))
    amount: Mapped[float] = mapped_column(Float)
    currency: Mapped[str] = mapped_column(String(5))
    fees: Mapped[float] = mapped_column(Float, default=0)
    status: Mapped[str] = mapped_column(String(30), index=True)
    token_code: Mapped[str | None] = mapped_column(String(20), nullable=True, unique=True)
    token_status: Mapped[str | None] = mapped_column(String(20), nullable=True)
    token_expires_at: Mapped[str | None] = mapped_column(String(40), nullable=True)
    reserved: Mapped[bool] = mapped_column(Boolean, default=False)
    rating_stars: Mapped[int | None] = mapped_column(Integer, nullable=True)
    rating_comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    mm_session_ref: Mapped[str | None] = mapped_column(String(40), nullable=True)
    mm_status: Mapped[str | None] = mapped_column(String(30), nullable=True)
    mm_instruction: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[str] = mapped_column(String(40), index=True)
    updated_at: Mapped[str] = mapped_column(String(40))


class TimelineEvent(Base):
    __tablename__ = "timeline_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    operation_id: Mapped[int] = mapped_column(ForeignKey("operations.id"), index=True)
    status: Mapped[str] = mapped_column(String(40))
    label: Mapped[str] = mapped_column(String(220))
    created_at: Mapped[str] = mapped_column(String(40))


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    audience: Mapped[str] = mapped_column(String(20), index=True)
    target_id: Mapped[int] = mapped_column(Integer, index=True)
    title: Mapped[str] = mapped_column(String(160))
    body: Mapped[str] = mapped_column(Text)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    operation_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[str] = mapped_column(String(40))


class Setting(Base):
    __tablename__ = "settings"

    key: Mapped[str] = mapped_column(String(60), primary_key=True)
    value: Mapped[str] = mapped_column(Text)


class AdminUser(Base):
    __tablename__ = "admins"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    email: Mapped[str] = mapped_column(String(160), unique=True)
    password_hash: Mapped[str] = mapped_column(String(200), default="")
    role: Mapped[str] = mapped_column(String(40), default="support")
    status: Mapped[str] = mapped_column(String(20), default="active")
    created_at: Mapped[str] = mapped_column(String(40))
