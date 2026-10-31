"""Passerelle API : point d'entrée unique des microservices."""

import sys
from pathlib import Path

import httpx
from fastapi import Request
from fastapi.responses import JSONResponse, Response

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from shared.http import create_app

app = create_app("gateway")

ROUTES = [
    ("/api/auth", "http://127.0.0.1:8001", "/auth"),
    ("/api/meta", "http://127.0.0.1:8001", "/meta"),
    ("/api/users", "http://127.0.0.1:8001", "/users"),
    ("/api/phones", "http://127.0.0.1:8001", "/phones"),
    ("/api/pdr", "http://127.0.0.1:8002", "/pdr"),
    ("/api/operations", "http://127.0.0.1:8003", "/operations"),
    ("/api/notifications", "http://127.0.0.1:8004", "/notifications"),
    ("/api/admin", "http://127.0.0.1:8005", "/admin"),
    ("/api/settings", "http://127.0.0.1:8005", "/settings"),
]

SERVICES = {
    "identity": "http://127.0.0.1:8001/health",
    "pdr": "http://127.0.0.1:8002/health",
    "operations": "http://127.0.0.1:8003/health",
    "notifications": "http://127.0.0.1:8004/health",
    "admin": "http://127.0.0.1:8005/health",
}


def _target(path: str) -> str | None:
    for prefix, base, mount in sorted(ROUTES, key=lambda item: len(item[0]), reverse=True):
        if path == prefix or path.startswith(prefix + "/"):
            return base + mount + path[len(prefix) :]
    return None


@app.get("/")
def root():
    return {
        "name": "Fast-Cash",
        "slogan": "Votre argent, votre monnaie, à proximité.",
    }


@app.get("/api/health")
def health():
    report = {}
    for name, url in SERVICES.items():
        try:
            response = httpx.get(url, timeout=2)
            report[name] = response.status_code == 200
        except httpx.HTTPError:
            report[name] = False
    payload = {"gateway": True, "services": report}
    # Render ne marque le service Live que si le health check répond 200.
    if not all(report.values()):
        return JSONResponse(payload, status_code=503)
    return payload


@app.api_route("/api/{full_path:path}", methods=["GET", "POST", "PATCH", "PUT", "DELETE"])
async def proxy(full_path: str, request: Request):
    path = f"/api/{full_path}"
    url = _target(path)
    if not url:
        return JSONResponse({"detail": "Route inconnue."}, status_code=404)
    if request.url.query:
        url = f"{url}?{request.url.query}"
    headers = {
        key: value
        for key, value in request.headers.items()
        if key.lower() not in {"host", "content-length"}
    }
    body = await request.body()
    try:
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.request(request.method, url, content=body, headers=headers)
    except httpx.HTTPError:
        return JSONResponse({"detail": "Service indisponible."}, status_code=503)
    return Response(content=response.content, status_code=response.status_code, media_type=response.headers.get("content-type"))
