"""Annulation d’offres pending (noyau partagé — évite le couplage pdr ↔ operations)."""

from sqlalchemy.orm import Session

from shared.models import Operation, TimelineEvent
from shared.utils import now_iso


def cancel_pending_for_pdr(db: Session, pdr_id: int, label: str = "Point de retrait indisponible") -> int:
    """Annule toutes les offres en attente d’un PDR (fermeture / déconnexion)."""
    rows = (
        db.query(Operation)
        .filter(Operation.pdr_id == pdr_id, Operation.status == "pending")
        .all()
    )
    closed = 0
    stamp = now_iso()
    for op in rows:
        if op.status != "pending":
            continue
        op.status = "cancelled"
        op.updated_at = stamp
        db.add(
            TimelineEvent(
                operation_id=op.id,
                status="cancelled",
                label=label,
                created_at=stamp,
            )
        )
        closed += 1
    return closed
