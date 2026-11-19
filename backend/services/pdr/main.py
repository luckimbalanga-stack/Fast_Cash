"""Point d'entrée du microservice PDR."""

import asyncio
import sys
from contextlib import asynccontextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from services.pdr.controllers import router
from shared.db import SessionLocal
from shared.http import create_app


def _run_settlement_sync() -> None:
    db = SessionLocal()
    try:
        from services.pdr.services import maybe_run_daily_settlement

        maybe_run_daily_settlement(db)
        if db.new or db.dirty or db.deleted:
            db.commit()
        else:
            db.rollback()
    except Exception:
        db.rollback()
    finally:
        db.close()


@asynccontextmanager
async def lifespan(_app):
    stop = asyncio.Event()

    async def settlement_loop():
        while not stop.is_set():
            try:
                await asyncio.to_thread(_run_settlement_sync)
            except Exception:
                pass
            try:
                await asyncio.wait_for(stop.wait(), timeout=60)
            except asyncio.TimeoutError:
                pass

    task = asyncio.create_task(settlement_loop())
    yield
    stop.set()
    await task


app = create_app("pdr", lifespan=lifespan)
app.include_router(router)
