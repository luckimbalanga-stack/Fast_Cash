"""Fabrique d'application et appels internes."""

import os

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from shared.utils import INTERNAL_KEY

PDR_URL = os.getenv("PDR_URL", "http://127.0.0.1:8002")
NOTIF_URL = os.getenv("NOTIF_URL", "http://127.0.0.1:8004")


def create_app(service_name: str) -> FastAPI:
    app = FastAPI(title=f"Fast-Cash — {service_name}", version="1.0.0")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        # * + credentials est refusé par les navigateurs ; false = OK pour mobile + admin web.
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/health")
    def health():
        return {"status": "ok", "service": service_name}

    return app


def internal_post(base: str, path: str, payload: dict) -> dict:
    try:
        response = httpx.post(
            f"{base}{path}",
            json=payload,
            headers={"X-Internal-Key": INTERNAL_KEY},
            timeout=8,
        )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="Un service interne est momentanément indisponible.") from exc
    if response.status_code >= 400:
        detail = "Opération refusée par un service interne."
        try:
            detail = response.json().get("detail", detail)
        except Exception:
            pass
        raise HTTPException(status_code=response.status_code, detail=detail)
    return response.json()


def notify(audience: str, target_id: int, title: str, body: str, operation_id: int | None = None) -> None:
    try:
        httpx.post(
            f"{NOTIF_URL}/notifications",
            json={
                "audience": audience,
                "target_id": target_id,
                "title": title,
                "body": body,
                "operation_id": operation_id,
            },
            headers={"X-Internal-Key": INTERNAL_KEY},
            timeout=4,
        )
    except httpx.HTTPError:
        return
