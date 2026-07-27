"""Lock the Python Codex parser to the golden results shared with Dart."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.providers.codex_app_server import parse_codex_rate_limits

FIXTURE_DIR = Path(__file__).resolve().parents[1] / "fixtures" / "codex"


def test_python_parser_matches_shared_dart_golden() -> None:
    payload = json.loads(
        (FIXTURE_DIR / "rate_limits_typical.json").read_text(encoding="utf-8")
    )
    payload.pop("_comment", None)
    result = parse_codex_rate_limits(
        payload,
        fetched_at=datetime(2026, 7, 27, tzinfo=timezone.utc),
    )
    actual: dict[str, Any] = {
        "provider": result.provider,
        "planName": result.plan_name,
        "planType": result.plan_type,
        "windows": [
            {
                "label": window.label,
                "used": window.used,
                "limit": window.limit,
                "unit": window.unit,
                "resetAt": (
                    window.reset_at.isoformat().replace("+00:00", "Z")
                    if window.reset_at is not None
                    else None
                ),
                "note": window.note,
            }
            for window in result.windows
        ],
        "credits": (
            {
                "hasCredits": result.credits.has_credits,
                "unlimited": result.credits.unlimited,
                "balance": result.credits.balance,
            }
            if result.credits is not None
            else None
        ),
    }
    expected = json.loads(
        (FIXTURE_DIR / "parity" / "parser_expected.json").read_text(
            encoding="utf-8"
        )
    )
    expected.pop("_comment", None)
    assert actual == expected
