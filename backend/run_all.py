"""Démarre les microservices Fast-Cash (local et Render)."""

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

# Indispensable pour les processus enfants (uvicorn charge les apps par chemin module).
os.environ["PYTHONPATH"] = os.pathsep.join(
    [str(ROOT)] + [p for p in os.environ.get("PYTHONPATH", "").split(os.pathsep) if p and p != str(ROOT)]
)

from shared.db import init_database

INTERNAL_SERVICES = [
    ("services.identity.main:app", 8001),
    ("services.pdr.main:app", 8002),
    ("services.operations.main:app", 8003),
    ("services.notifications.main:app", 8004),
    ("services.admin.main:app", 8005),
]


def _serve(app_path: str, host: str, port: int) -> None:
    uvicorn.run(app_path, host=host, port=port, log_level="info", access_log=False)


def _wait_ports(ports: set[int], timeout_s: float = 60) -> set[int]:
    deadline = time.time() + timeout_s
    pending = set(ports)
    while pending and time.time() < deadline:
        ready: set[int] = set()
        for port in pending:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(0.2)
                if sock.connect_ex(("127.0.0.1", port)) == 0:
                    ready.add(port)
        pending -= ready
        if pending:
            time.sleep(0.25)
    return pending


def main() -> None:
    init_database(seed=True)
    public_port = int(os.environ.get("PORT", "8000"))
    # Render injecte PORT : le gateway doit écouter sur toutes les interfaces.
    gateway_host = "0.0.0.0" if os.environ.get("PORT") else "127.0.0.1"

    print("Fast-Cash — démarrage des services", flush=True)
    print(f"Passerelle API : http://{gateway_host}:{public_port}", flush=True)

    processes: list[multiprocessing.Process] = []
    for app_path, port in INTERNAL_SERVICES:
        process = multiprocessing.Process(
            target=_serve,
            args=(app_path, "127.0.0.1", port),
            daemon=True,
            name=app_path.split(":")[0],
        )
        process.start()
        processes.append(process)

    pending = _wait_ports({port for _, port in INTERNAL_SERVICES}, timeout_s=60)
    if pending:
        print(f"ERREUR : services non prêts sur {sorted(pending)}", flush=True)
        for process in processes:
            process.terminate()
        raise SystemExit(1)

    print("Microservices prêts — ouverture de la passerelle", flush=True)
    gateway = multiprocessing.Process(
        target=_serve,
        args=("gateway.main:app", gateway_host, public_port),
        daemon=True,
        name="gateway",
    )
    gateway.start()
    processes.append(gateway)

    if _wait_ports({public_port}, timeout_s=30):
        print(f"ERREUR : passerelle non prête sur le port {public_port}", flush=True)
        for process in processes:
            process.terminate()
        raise SystemExit(1)

    print("Fast-Cash — API prête", flush=True)
    try:
        for process in processes:
            process.join()
    except KeyboardInterrupt:
        for process in processes:
            process.terminate()


if __name__ == "__main__":
    multiprocessing.freeze_support()
    main()
