"""Démarre les microservices Fast-Cash."""

import multiprocessing
import os
import socket
import sys
import time
from pathlib import Path

import uvicorn

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from shared.db import init_database

INTERNAL_SERVICES = [
    ("services.identity.main:app", 8001),
    ("services.pdr.main:app", 8002),
    ("services.operations.main:app", 8003),
    ("services.notifications.main:app", 8004),
    ("services.admin.main:app", 8005),
]


def _serve(app_path: str, host: str, port: int) -> None:
    uvicorn.run(app_path, host=host, port=port, log_level="info")


def main() -> None:
    init_database(seed=True)
    public_port = int(os.environ.get("PORT", "8000"))
    # Sur Render (ou si PORT est fourni), le gateway écoute sur toutes les interfaces.
    gateway_host = "0.0.0.0" if os.environ.get("PORT") else "127.0.0.1"

    print("Fast-Cash — services démarrés")
    print(f"Passerelle API : http://{gateway_host}:{public_port}")
    print("Documentation identité : http://127.0.0.1:8001/docs")

    processes: list[multiprocessing.Process] = []
    for app_path, port in INTERNAL_SERVICES:
        process = multiprocessing.Process(
            target=_serve,
            args=(app_path, "127.0.0.1", port),
            daemon=True,
        )
        process.start()
        processes.append(process)

    # Attendre que les microservices écoutent avant d’ouvrir la passerelle (health check Render).
    deadline = time.time() + 30
    pending = {port for _, port in INTERNAL_SERVICES}
    while pending and time.time() < deadline:
        ready: set[int] = set()
        for port in pending:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(0.2)
                if sock.connect_ex(("127.0.0.1", port)) == 0:
                    ready.add(port)
        pending -= ready
        if pending:
            time.sleep(0.3)
    if pending:
        print(f"Attention : services pas encore prêts sur les ports {sorted(pending)}")

    gateway = multiprocessing.Process(
        target=_serve,
        args=("gateway.main:app", gateway_host, public_port),
        daemon=True,
    )
    gateway.start()
    processes.append(gateway)

    try:
        for process in processes:
            process.join()
    except KeyboardInterrupt:
        for process in processes:
            process.terminate()


if __name__ == "__main__":
    multiprocessing.freeze_support()
    main()
