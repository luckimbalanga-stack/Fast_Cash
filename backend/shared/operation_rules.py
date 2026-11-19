"""Règles pures sur les opérations (SRP) — partagées pdr / admin / operations."""

from shared.models import Operation
from shared.utils import round_money


def is_pdr_success(op: Operation) -> bool:
    """Transaction réussie côté PDR (après scan / clôture)."""
    return op.status == "completed"


def amount_cdf(op: Operation, rate: float) -> float:
    """Montant de l’opération converti en CDF."""
    value = float(op.amount or 0)
    if op.currency == "CDF":
        return value
    return value * float(rate)


def amount_cdf_rounded(op: Operation, rate: float) -> float:
    return round_money(amount_cdf(op, rate), "CDF")
