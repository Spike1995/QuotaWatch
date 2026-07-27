"""Lock the Python GLM parser to the golden results shared with Dart."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.providers.glm_parser import parse_glm_usage

FIXTURE_DIR = Path(__file__).resolve().parents[1] / "fixtures" / "glm"
EXPECTED_PATH = FIXTURE_DIR / "parity" / "parser_expected.json"


def _normalize(payload: dict[str, Any]) -> list[dict[str, Any]]:
    return [
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
        for window in parse_glm_usage(payload)
    ]


def test_python_parser_matches_shared_dart_golden() -> None:
    expected = json.loads(EXPECTED_PATH.read_text(encoding="utf-8"))
    expected.pop("_comment", None)

    actual: dict[str, list[dict[str, Any]]] = {}
    for fixture_name in expected:
        payload = json.loads((FIXTURE_DIR / fixture_name).read_text(encoding="utf-8"))
        payload.pop("_comment", None)
        actual[fixture_name] = _normalize(payload)

    assert actual == expected
