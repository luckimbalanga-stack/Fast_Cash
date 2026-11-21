"""Plages de commission PDR (montants USD → coupe liquidité CDF)."""

from __future__ import annotations

import json
from typing import Any

from fastapi import HTTPException

from shared.utils import round_money

# Plage par défaut si aucune n’est configurée (évite de bloquer les retraits).
DEFAULT_COMMISSION_RANGES: list[dict[str, float]] = [
    {"min_usd": 1.0, "max_usd": 10000.0, "cut_usd": 0.5},
]


def parse_commission_ranges(raw: Any) -> list[dict[str, float]]:
    """Normalise une liste JSON / dicts en plages {min_usd, max_usd, cut_usd}."""
    if raw is None or raw == "":
        return []
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise HTTPException(status_code=400, detail="Plages de commission invalides (JSON).") from exc
    if not isinstance(raw, list):
        raise HTTPException(status_code=400, detail="Les plages de commission doivent être une liste.")
    ranges: list[dict[str, float]] = []
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            raise HTTPException(status_code=400, detail=f"Plage #{index + 1} invalide.")
        try:
            min_usd = float(item.get("min_usd"))
            max_usd = float(item.get("max_usd"))
            cut_usd = float(item.get("cut_usd"))
        except (TypeError, ValueError) as exc:
            raise HTTPException(status_code=400, detail=f"Plage #{index + 1} : montants numériques requis.") from exc
        if min_usd <= 0 or max_usd <= 0 or cut_usd <= 0:
            raise HTTPException(status_code=400, detail=f"Plage #{index + 1} : X, Y et Z doivent être > 0.")
        if max_usd <= min_usd:
            raise HTTPException(status_code=400, detail=f"Plage #{index + 1} : Y doit être strictement supérieur à X.")
        ranges.append(
            {
                "min_usd": round_money(min_usd, "USD"),
                "max_usd": round_money(max_usd, "USD"),
                "cut_usd": round_money(cut_usd, "USD"),
            }
        )
    return ranges


def validate_commission_ranges(ranges: list[dict[str, float]]) -> list[dict[str, float]]:
    """Refuse les chevauchements (ex. 1–10 puis 9–15). Les bornes adjacentes 10 puis 11 sont OK."""
    ordered = sorted(ranges, key=lambda row: (row["min_usd"], row["max_usd"]))
    previous: dict[str, float] | None = None
    for row in ordered:
        if previous is not None:
            # Chevauchement inclusif : [a,b] ∩ [c,d] ≠ ∅
            if row["min_usd"] <= previous["max_usd"]:
                raise HTTPException(
                    status_code=400,
                    detail=(
                        f"Chevauchement : la plage {row['min_usd']:g}–{row['max_usd']:g} USD "
                        f"entre dans {previous['min_usd']:g}–{previous['max_usd']:g} USD. "
                        f"Commencez au-delà de {previous['max_usd']:g} (ex. {previous['max_usd'] + 1:g})."
                    ),
                )
        previous = row
    return ordered


def ranges_with_display(ranges: list[dict[str, float]], rate: float) -> list[dict[str, Any]]:
    """Ajoute CDF + % de coupe vs montant max de la plage (pour l’admin)."""
    fx = float(rate) if rate else 2880.0
    payload = []
    for row in ranges:
        max_usd = float(row["max_usd"])
        cut_usd = float(row["cut_usd"])
        percent = round((cut_usd / max_usd) * 100, 2) if max_usd > 0 else 0.0
        payload.append(
            {
                **row,
                "min_cdf": round_money(float(row["min_usd"]) * fx, "CDF"),
                "max_cdf": round_money(max_usd * fx, "CDF"),
                "cut_cdf": round_money(cut_usd * fx, "CDF"),
                "cut_percent_of_max": percent,
            }
        )
    return payload


def amount_to_usd(amount: float, currency: str, rate: float) -> float:
    value = float(amount or 0)
    if currency.upper() == "USD":
        return value
    fx = float(rate) if rate else 2880.0
    if fx <= 0:
        raise HTTPException(status_code=400, detail="Taux USD/CDF invalide.")
    return value / fx


def find_commission_range(ranges: list[dict[str, float]], amount_usd: float) -> dict[str, float] | None:
    for row in ranges:
        if row["min_usd"] <= amount_usd <= row["max_usd"]:
            return row
    return None


def commission_cut_usd(ranges: list[dict[str, float]], amount: float, currency: str, rate: float) -> float:
    """Retourne la coupe Z (USD) pour le montant d’opération, ou erreur si hors plage."""
    amount_usd = amount_to_usd(amount, currency, rate)
    if amount_usd <= 0:
        raise HTTPException(status_code=400, detail="Montant de retrait invalide.")
    match = find_commission_range(ranges, amount_usd)
    if not match:
        raise HTTPException(
            status_code=409,
            detail=(
                f"Aucune plage de commission pour {amount_usd:g} USD. "
                "Ajoutez une plage couvrant ce montant dans Paramètres."
            ),
        )
    return float(match["cut_usd"])


def commission_cut_cdf(ranges: list[dict[str, float]], amount: float, currency: str, rate: float) -> float:
    cut_usd = commission_cut_usd(ranges, amount, currency, rate)
    return round_money(cut_usd * float(rate), "CDF")


def dumps_ranges(ranges: list[dict[str, float]]) -> str:
    return json.dumps(ranges, ensure_ascii=False, separators=(",", ":"))
