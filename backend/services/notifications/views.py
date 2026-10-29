"""Contrats du service Notifications."""

from pydantic import BaseModel


class NotificationCreate(BaseModel):
    audience: str
    target_id: int
    title: str
    body: str
    operation_id: int | None = None
