"""Préparation des ordres envoyés aux opérateurs Mobile Money.

La clé d'API et le jeton de session opérateur ne figurent pas ici :
ils seront ajoutés au moment du branchement réel. Le code PIN circule
uniquement dans l'ordre en mémoire, puis disparaît.
"""

import secrets
from copy import deepcopy


OPERATORS = {
    "orange": "Orange Money",
    "airtel": "Airtel Money",
    "mpesa": "M-Pesa",
    "afrimoney": "AfriMoney",
}


def prepare_instruction(
    *,
    operator: str,
    kind: str,
    subscriber_msisdn: str,
    agent_msisdn: str,
    amount: float,
    currency: str,
    reference: str,
    pin: str,
) -> dict:
    if operator not in OPERATORS:
        raise ValueError("Opérateur Mobile Money inconnu.")
    if kind not in {"withdrawal", "deposit"}:
        raise ValueError("Type d'opération inconnu.")
    if not pin.isdigit() or not 4 <= len(pin) <= 8:
        raise ValueError("Le code PIN doit contenir 4 à 8 chiffres.")
    session_ref = f"MM-{secrets.token_hex(6).upper()}"
    steps = [
        {
            "action": "open_session",
            "session_ref": session_ref,
            "operator": operator,
            "subscriber_msisdn": subscriber_msisdn,
        },
        {
            "action": "transfer",
            "session_ref": session_ref,
            "direction": "cash_out" if kind == "withdrawal" else "cash_in",
            "subscriber_msisdn": subscriber_msisdn,
            "agent_msisdn": agent_msisdn,
            "amount": amount,
            "currency": currency,
            "reference": reference,
            "pin": pin,
        },
        {
            "action": "close_session",
            "session_ref": session_ref,
        },
    ]
    redacted = deepcopy(steps)
    redacted[1].pop("pin")
    redacted[1]["pin_provided"] = True
    return {
        "operator": operator,
        "operator_label": OPERATORS[operator],
        "session_ref": session_ref,
        "credentials": {"api_key": None, "token": None},
        "steps": steps,
        "record": {
            "operator": operator,
            "operator_label": OPERATORS[operator],
            "session_ref": session_ref,
            "credentials_attached": False,
            "steps": redacted,
        },
    }
