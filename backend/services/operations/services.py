"""Règles métier du service Opérations."""

import json
from datetime import datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from shared.http import PDR_URL, internal_post, notify
from shared.mobile_money import prepare_instruction
from shared.models import Operation, Pdr, PhoneNumber, Setting, TimelineEvent, User
from shared.serialize import operation_dict
from shared.utils import KINSHASA, make_reference, normalize_phone, now_iso, parse_iso, round_money


def _setting(db: Session, key: str, default: str) -> str:
    row = db.get(Setting, key)
    return row.value if row else default


def _offer_seconds(db: Session) -> int:
    return max(5, min(120, int(float(_setting(db, "pdr_offer_seconds", "30")))))


def _fee(db: Session, amount: float, currency: str) -> float:
    percent = float(_setting(db, "fee_percent", "1"))
    if percent <= 0 or amount <= 0:
        return 0
    raw = amount * percent / 100
    if currency == "CDF":
        return float(max(1, round(raw)))
    return round_money(raw, "USD")


def _events(db: Session, operation_id: int) -> list[TimelineEvent]:
    return (
        db.query(TimelineEvent)
        .filter(TimelineEvent.operation_id == operation_id)
        .order_by(TimelineEvent.id.asc())
        .all()
    )


def present(db: Session, op: Operation) -> dict:
    return operation_dict(op, _events(db, op.id))


def _touch(db: Session, op: Operation, status: str, label: str) -> None:
    op.status = status
    op.updated_at = now_iso()
    db.add(TimelineEvent(operation_id=op.id, status=status, label=label, created_at=op.updated_at))


def _liquidity(path: str, op: Operation) -> None:
    internal_post(PDR_URL, path, {"currency": op.currency, "amount": op.amount})


def _aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=KINSHASA)
    return value.astimezone(KINSHASA)


def _offer_deadline_at(created_at: str, offer_seconds: int) -> datetime | None:
    if not created_at:
        return None
    try:
        created = _aware(parse_iso(created_at))
    except Exception:
        return None
    return created + timedelta(seconds=offer_seconds)


def _close_pending_offer(db: Session, op: Operation, label: str) -> bool:
    """Clôture une offre pending expirée / abandonnée — pas de file d’attente fantôme."""
    if op.status != "pending":
        return False
    _touch(db, op, "cancelled", label)
    return True


def cancel_pending_for_pdr(db: Session, pdr_id: int, label: str = "Point de retrait indisponible") -> int:
    """Annule toutes les offres en attente d’un PDR (fermeture / déconnexion)."""
    rows = (
        db.query(Operation)
        .filter(Operation.pdr_id == pdr_id, Operation.status == "pending")
        .all()
    )
    closed = 0
    for op in rows:
        if _close_pending_offer(db, op, label):
            closed += 1
            notify(
                "user",
                op.user_id,
                "Point indisponible",
                f"{op.pdr_name} n’est plus disponible. La demande passe au point suivant.",
                op.id,
            )
    return closed


def expire_stale_pending(db: Session, *, user_id: int | None = None, pdr_id: int | None = None) -> int:
    """Expire en lot les offres pending hors délai (une lecture settings)."""
    offer_seconds = _offer_seconds(db)
    now = datetime.now(KINSHASA)
    query = db.query(Operation).filter(Operation.status == "pending")
    if user_id is not None:
        query = query.filter(Operation.user_id == user_id)
    if pdr_id is not None:
        query = query.filter(Operation.pdr_id == pdr_id)
    closed = 0
    for op in query.all():
        deadline = _offer_deadline_at(op.created_at, offer_seconds)
        if deadline is not None and now >= deadline:
            if _close_pending_offer(db, op, "Délai d’offre écoulé — passage au point suivant"):
                closed += 1
    return closed


def maybe_expire(db: Session, op: Operation, *, offer_seconds: int | None = None) -> None:
    """Expire les offres pending hors délai, puis gère les jetons de retrait."""
    if op.status == "pending":
        seconds = offer_seconds if offer_seconds is not None else _offer_seconds(db)
        deadline = _offer_deadline_at(op.created_at, seconds)
        if deadline is not None and datetime.now(KINSHASA) >= deadline:
            _close_pending_offer(db, op, "Délai d’offre écoulé — passage au point suivant")
            return
    if op.type != "withdrawal":
        return
    if op.status == "expired" and op.token_status == "expired":
        if op.token_code:
            op.status = "payment_confirmed"
            op.token_status = "active"
            op.token_expires_at = None
            if not op.reserved:
                try:
                    _liquidity(f"/pdr/{op.pdr_id}/liquidity/reserve", op)
                    op.reserved = True
                except Exception:
                    pass
            db.add(TimelineEvent(operation_id=op.id, status="payment_confirmed", label="Jeton réactivé jusqu’au scan", created_at=now_iso()))
            op.updated_at = now_iso()
        return
    if op.status == "payment_confirmed" and op.token_status == "active":
        op.token_expires_at = None


def get_operation(db: Session, operation_id: int) -> Operation:
    op = db.get(Operation, operation_id)
    if not op:
        raise HTTPException(status_code=404, detail="Opération introuvable.")
    maybe_expire(db, op)
    return op


def _visible(op: Operation, role: str, ident: int) -> None:
    if role == "user" and op.user_id != ident:
        raise HTTPException(status_code=403, detail="Cette opération ne vous appartient pas.")
    if role == "pdr" and op.pdr_id != ident:
        raise HTTPException(status_code=403, detail="Cette opération ne concerne pas votre point de retrait.")


def _prefetch_timelines(db: Session, operation_ids: list[int]) -> dict[int, list[TimelineEvent]]:
    if not operation_ids:
        return {}
    rows = (
        db.query(TimelineEvent)
        .filter(TimelineEvent.operation_id.in_(operation_ids))
        .order_by(TimelineEvent.id.asc())
        .all()
    )
    grouped: dict[int, list[TimelineEvent]] = {op_id: [] for op_id in operation_ids}
    for event in rows:
        grouped.setdefault(event.operation_id, []).append(event)
    return grouped


LIST_OPERATIONS_LIMIT = 100


def list_operations(
    db: Session,
    role: str,
    ident: int,
    type_: str | None,
    status: str | None,
    currency: str | None,
    pdr_id: int | None,
    user_id: int | None,
    date_from: str | None,
    date_to: str | None,
    query: str | None,
) -> list[dict]:
    # Expire d’abord le périmètre visible (évite N lectures settings).
    if role == "user":
        expire_stale_pending(db, user_id=ident)
    elif role == "pdr":
        expire_stale_pending(db, pdr_id=ident)
    else:
        expire_stale_pending(db)

    q = db.query(Operation)
    if role == "user":
        q = q.filter(Operation.user_id == ident)
    elif role == "pdr":
        q = q.filter(Operation.pdr_id == ident)
    elif role == "admin":
        if pdr_id:
            q = q.filter(Operation.pdr_id == pdr_id)
        if user_id:
            q = q.filter(Operation.user_id == user_id)
    if type_:
        q = q.filter(Operation.type == type_)
    if status:
        q = q.filter(Operation.status == status)
    if currency:
        q = q.filter(Operation.currency == currency)
    if date_from:
        q = q.filter(Operation.created_at >= date_from)
    if date_to:
        q = q.filter(Operation.created_at <= f"{date_to}T23:59:59")

    needle = (query or "").strip().lower()
    rows = q.order_by(Operation.created_at.desc()).limit(LIST_OPERATIONS_LIMIT * 3 if needle else LIST_OPERATIONS_LIMIT).all()
    if needle:
        filtered = []
        for op in rows:
            hay = " ".join([op.reference, op.user_name, op.pdr_name, op.phone, op.token_code or ""]).lower()
            if needle in hay:
                filtered.append(op)
            if len(filtered) >= LIST_OPERATIONS_LIMIT:
                break
        rows = filtered

    timelines = _prefetch_timelines(db, [op.id for op in rows])
    return [operation_dict(op, timelines.get(op.id, [])) for op in rows]


def create_operation(db: Session, user_id: int, data: dict) -> dict:
    user = db.get(User, user_id)
    if not user or user.status != "active":
        raise HTTPException(status_code=403, detail="Compte indisponible.")
    kind = data["type"]
    if kind not in {"withdrawal", "deposit"}:
        raise HTTPException(status_code=400, detail="Type d'opération inconnu.")
    currency = data["currency"].upper()
    if currency not in {"USD", "CDF"}:
        raise HTTPException(status_code=400, detail="Choisissez USD ou CDF.")
    amount = round_money(float(data["amount"]), currency)
    minimum = 1 if currency == "USD" else 1000
    if amount < minimum:
        raise HTTPException(status_code=400, detail=f"Montant minimum : {minimum:g} {currency}.")
    phone = normalize_phone(data["phone"])
    number = (
        db.query(PhoneNumber)
        .filter(PhoneNumber.user_id == user_id, PhoneNumber.phone == phone, PhoneNumber.verified.is_(True))
        .one_or_none()
    )
    if not number:
        raise HTTPException(status_code=400, detail="Choisissez un numéro Mobile Money vérifié.")
    pdr = db.get(Pdr, data["pdr_id"])
    if not pdr or pdr.status != "active":
        raise HTTPException(status_code=404, detail="Point de retrait indisponible.")
    from services.pdr.services import is_match

    if not is_match(pdr, kind, currency, amount, number.network):
        raise HTTPException(status_code=409, detail="Ce PDR ne peut pas traiter cette opération pour le moment.")
    # Chaînage : clôturer les offres pending précédentes du même utilisateur
    # pour qu’un PDR déjà sauté ne puisse plus accepter.
    for old in (
        db.query(Operation)
        .filter(Operation.user_id == user_id, Operation.status == "pending")
        .all()
    ):
        _close_pending_offer(db, old, "Passage au point suivant")

    fees = _fee(db, amount, currency)
    offer_seconds = _offer_seconds(db)
    reference = None
    for _ in range(12):
        candidate = make_reference()
        if db.query(Operation.id).filter(Operation.reference == candidate).first():
            continue
        reference = candidate
        break
    if not reference:
        raise HTTPException(status_code=500, detail="Impossible de créer la référence d’opération.")
    op = Operation(
        reference=reference,
        type=kind,
        user_id=user.id,
        user_name=user.name,
        pdr_id=pdr.id,
        pdr_name=pdr.name,
        pdr_address=pdr.address,
        pdr_commune=pdr.commune,
        pdr_lat=pdr.lat,
        pdr_lng=pdr.lng,
        pdr_hours=pdr.opening_hours,
        pdr_phone=pdr.phone,
        phone=number.phone,
        network=number.network,
        amount=amount,
        currency=currency,
        fees=fees,
        status="pending",
        reserved=False,
        created_at=now_iso(),
        updated_at=now_iso(),
    )
    db.add(op)
    db.flush()

    verb = "un retrait" if kind == "withdrawal" else "un dépôt"
    db.add(TimelineEvent(operation_id=op.id, status="pending", label="Demande envoyée", created_at=op.created_at))
    notify(
        "pdr",
        pdr.id,
        "Appel entrant",
        f"{user.name} demande {verb} de {amount:g} {currency} · {number.phone}. Validez ou refusez sous {offer_seconds} s.",
        op.id,
    )
    notify("user", user.id, "Demande envoyée", f"Votre demande {op.reference} est en attente du point de retrait.", op.id)
    return present(db, op)


def accept(db: Session, pdr_id: int, operation_id: int) -> dict:
    op = get_operation(db, operation_id)
    _visible(op, "pdr", pdr_id)
    if op.status != "pending":
        raise HTTPException(status_code=409, detail="Cette demande n'est plus en attente.")
    if op.type == "withdrawal":
        _liquidity(f"/pdr/{op.pdr_id}/liquidity/reserve", op)
        op.reserved = True
    _touch(db, op, "pin_required", "Demande acceptée, code PIN requis")
    verb = "retrait" if op.type == "withdrawal" else "dépôt"
    notify(
        "user",
        op.user_id,
        "Demande acceptée",
        f"{op.pdr_name} a accepté votre {verb}. Saisissez votre code PIN Mobile Money pour autoriser l'opération.",
        op.id,
    )
    return present(db, op)


def refuse(db: Session, pdr_id: int, operation_id: int) -> dict:
    op = get_operation(db, operation_id)
    _visible(op, "pdr", pdr_id)
    if op.status != "pending":
        raise HTTPException(status_code=409, detail="Cette demande n'est plus en attente.")
    _touch(db, op, "refused", "Demande refusée par le PDR")
    notify("user", op.user_id, "Demande refusée", f"{op.pdr_name} ne peut pas traiter {op.reference}. Choisissez un autre point.", op.id)
    return present(db, op)


def authorize(db: Session, user_id: int, operation_id: int, pin: str) -> dict:
    """Prépare l'ordre opérateur. Le PIN n'est ni enregistré ni renvoyé."""
    op = get_operation(db, operation_id)
    _visible(op, "user", user_id)
    if op.status != "pin_required":
        raise HTTPException(status_code=409, detail="Cette opération n'attend pas de code PIN.")
    pdr = db.get(Pdr, op.pdr_id)
    agent = op.pdr_phone or (pdr.phone if pdr else "")
    if not agent:
        raise HTTPException(status_code=409, detail="Le numéro du point de retrait est introuvable.")
    try:
        prepared = prepare_instruction(
            operator=op.network,
            kind=op.type,
            subscriber_msisdn=op.phone,
            agent_msisdn=agent,
            amount=op.amount,
            currency=op.currency,
            reference=op.reference,
            pin=pin.strip(),
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    op.pdr_phone = agent
    op.mm_session_ref = prepared["session_ref"]
    op.mm_status = "session_open"
    op.mm_instruction = json.dumps(prepared["record"], ensure_ascii=False)
    print(f"Fast-Cash — ordre Mobile Money préparé {op.reference} session {op.mm_session_ref}", flush=True)
    if op.type == "withdrawal":
        op.token_code = op.reference
        op.token_status = "active"
        op.token_expires_at = None
        _touch(db, op, "payment_confirmed", "Paiement confirmé")
        notify("pdr", op.pdr_id, "Paiement confirmé", f"Le jeton {op.token_code} est prêt à être scanné.", op.id)
        notify("user", op.user_id, "Paiement confirmé", f"Présentez le code QR {op.token_code} au {op.pdr_name}. Le jeton reste valide jusqu’au scan.", op.id)
    else:
        _touch(db, op, "accepted", "Code PIN confirmé, remise des espèces en attente")
        notify("user", op.user_id, "Rendez-vous au point de retrait", f"Remettez les espèces au {op.pdr_name}. Le transfert sera clôturé après confirmation.", op.id)
        notify("pdr", op.pdr_id, "Client autorisé", f"{op.user_name} a autorisé le dépôt {op.reference}.", op.id)
    return present(db, op)


def confirm_cash(db: Session, pdr_id: int, operation_id: int) -> dict:
    op = get_operation(db, operation_id)
    _visible(op, "pdr", pdr_id)
    if op.type != "deposit" or op.status != "accepted":
        raise HTTPException(status_code=409, detail="La réception des espèces n'est pas attendue pour cette opération.")
    _liquidity(f"/pdr/{op.pdr_id}/liquidity/receive", op)
    op.mm_status = "session_closed"
    _touch(db, op, "payment_confirmed", "Espèces reçues, session Mobile Money clôturée")
    notify("user", op.user_id, "Dépôt confirmé", f"La session de transfert vers {op.phone} est clôturée.", op.id)
    notify("pdr", op.pdr_id, "Dépôt confirmé", f"Le dépôt {op.reference} est clôturé.", op.id)
    return present(db, op)


def simulate_transfer(db: Session, role: str, ident: int, operation_id: int) -> dict:
    op = get_operation(db, operation_id)
    _visible(op, role, ident)
    if op.type == "deposit" and op.status == "payment_confirmed":
        return present(db, op)
    raise HTTPException(status_code=409, detail="Le transfert est clôturé lorsque le point de retrait confirme les espèces.")


def cancel(db: Session, role: str, ident: int, operation_id: int) -> dict:
    op = get_operation(db, operation_id)
    _visible(op, role, ident)
    if op.status == "cancelled":
        return present(db, op)
    if op.status not in {"pending", "accepted", "pin_required", "payment_pending", "payment_confirmed"}:
        raise HTTPException(status_code=409, detail="Cette opération ne peut plus être annulée.")
    was_offer = op.status == "pending"
    if op.reserved:
        _liquidity(f"/pdr/{op.pdr_id}/liquidity/release", op)
        op.reserved = False
    if op.token_status == "active":
        op.token_status = "cancelled"
    label = "Délai d’offre écoulé — passage au point suivant" if was_offer else "Opération annulée"
    _touch(db, op, "cancelled", label)
    # Offre pending : pas de notif (le chaînage mobile passe au PDR suivant).
    if not was_offer:
        notify("user", op.user_id, "Opération annulée", f"La demande {op.reference} a été annulée.", op.id)
        notify("pdr", op.pdr_id, "Opération annulée", f"La demande {op.reference} a été annulée.", op.id)
    return present(db, op)


def lookup_token(db: Session, pdr_id: int, code: str) -> dict:
    normalized = code.strip().upper()
    op = db.query(Operation).filter(Operation.token_code == normalized).one_or_none()
    if not op:
        raise HTTPException(status_code=404, detail="Jeton introuvable.")
    maybe_expire(db, op)
    if op.pdr_id != pdr_id:
        raise HTTPException(
            status_code=403,
            detail="Ce ticket ne peut être validé que chez le point de retrait qui a accepté la demande.",
        )
    payload = present(db, op)
    payload["redeemable"] = op.type == "withdrawal" and op.status == "payment_confirmed" and op.token_status == "active"
    if op.token_status == "used" or op.status == "completed":
        payload["error"] = "Ce jeton a déjà été utilisé."
    elif op.token_status == "cancelled" or op.status == "cancelled":
        payload["error"] = "Ce jeton a été annulé."
    elif not payload["redeemable"]:
        payload["error"] = "Ce jeton n'est pas valide pour une remise d'espèces."
    return payload


def redeem(db: Session, pdr_id: int, code: str) -> dict:
    preview = lookup_token(db, pdr_id, code)
    if not preview["redeemable"]:
        raise HTTPException(status_code=409, detail=preview.get("error") or "Jeton invalide.")
    op = get_operation(db, preview["id"])
    _liquidity(f"/pdr/{op.pdr_id}/liquidity/consume", op)
    op.reserved = False
    op.token_status = "used"
    op.token_expires_at = None
    op.mm_status = "session_closed"
    done = "Retrait effectué" if op.type == "withdrawal" else "Dépôt effectué"
    _touch(db, op, "completed", done)
    notify("user", op.user_id, done, f"{done} au {op.pdr_name}. Vous pouvez noter le point de retrait.", op.id)
    notify("pdr", op.pdr_id, done, f"{done} · {op.reference}.", op.id)
    return present(db, op)


def rate(db: Session, user_id: int, operation_id: int, stars: int, comment: str) -> dict:
    op = get_operation(db, operation_id)
    _visible(op, "user", user_id)
    allowed = (op.type == "withdrawal" and op.status in {"cash_delivered", "completed"}) or (
        op.type == "deposit" and op.status in {"payment_confirmed", "completed"}
    )
    if not allowed:
        raise HTTPException(status_code=409, detail="L'évaluation sera disponible à la fin de l'opération.")
    if stars < 1 or stars > 5:
        raise HTTPException(status_code=400, detail="Choisissez une note de 1 à 5 étoiles.")
    if op.rating_stars:
        raise HTTPException(status_code=409, detail="Cette opération a déjà été évaluée.")
    internal_post(
        PDR_URL,
        f"/pdr/{op.pdr_id}/ratings",
        {
            "user_id": op.user_id,
            "user_name": op.user_name,
            "operation_id": op.id,
            "stars": stars,
            "comment": comment,
        },
    )
    op.rating_stars = stars
    op.rating_comment = comment.strip()
    if op.status != "completed":
        _touch(db, op, "completed", "Opération terminée")
    else:
        op.updated_at = now_iso()
    return present(db, op)
