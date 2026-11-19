"""Règles d’éligibilité PDR pures (SRP) — sans dépendance aux services métier."""

from shared.models import Pdr


def pdr_supports_network(pdr: Pdr, network: str | None) -> bool:
    if not network:
        return True
    return network in (pdr.networks or "").split(",")


def pdr_can_handle(pdr: Pdr, kind: str, currency: str, amount: float, network: str | None) -> bool:
    """Éligibilité recherche / création d’opération : actif, ouvert, réseau."""
    del currency, amount  # réservés pour de futurs filtres liquidité
    if pdr.status != "active" or not pdr.is_open:
        return False
    if not pdr_supports_network(pdr, network):
        return False
    if kind == "deposit":
        return bool(pdr.accepts_deposits)
    return True
