"""Point d'entrée du microservice PDR."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from services.pdr.controllers import router
from shared.http import create_app

app = create_app("pdr")
app.include_router(router)
