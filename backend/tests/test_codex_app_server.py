"""Offline tests for the Codex app-server rate-limit adapter."""

from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pytest

from app.providers.base import AuthError, ContractError, ProviderConnectionError, ProviderTimeoutError
from app.providers.codex_app_server import (
    CodexAppServerAdapter,
    CodexAppServerClient,
    parse_codex_rate_limits,
    resolve_codex_command,
)


FIXED_NOW = datetime(2026, 7, 23, 6, 0, tzinfo=timezone.utc)
FAKE_SERVER = Path(__file__).with_name("fake_codex_app_server.py")


class _StubClient:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload

    def read_rate_limits(self) -> dict[str, Any]:
        return self.payload


def _snapshot() -> dict[str, Any]:
    return {
        "rateLimits": {
            "limitId": "codex",
            "planType": "plus",
            "primary": {
                "usedPercent": 25,
                "windowDurationMins": 300,
                "resetsAt": 1760000000,
            },
            "secondary": {
                "usedPercent": 80,
                "windowDurationMins": 10080,
                "resetsAt": 1760500000,
            },
        }
    }


def test_parser_maps_primary_secondary_and_plan() -> None:
    result = parse_codex_rate_limits(_snapshot(), fetched_at=FIXED_NOW)

    assert result.provider == "codex"
    assert result.plan_name == "ChatGPT Plus"
    assert result.plan_type == "plus"
    assert result.fetched_at == FIXED_NOW
    assert [(window.label, window.used, window.limit, window.unit) for window in result.windows] == [
        ("5 小时窗口", 25.0, 100.0, "percent"),
        ("7 天窗口", 80.0, 100.0, "percent"),
    ]
    assert result.windows[0].reset_at == datetime.fromtimestamp(1760000000, tz=timezone.utc)
    assert "本机只读" in (result.windows[0].note or "")


def test_parser_prefers_codex_multi_bucket() -> None:
    payload = _snapshot()
    payload["rateLimitsByLimitId"] = {
        "other": {"limitId": "other", "primary": {"usedPercent": 99}},
        "codex": {
            "limitId": "codex",
            "planType": "pro",
            "primary": {"usedPercent": 12, "windowDurationMins": 300},
        },
    }

    result = parse_codex_rate_limits(payload, fetched_at=FIXED_NOW)

    assert result.plan_name == "ChatGPT Pro"
    assert result.windows[0].used == 12


def test_parser_clamps_percent_and_handles_missing_duration() -> None:
    payload = {
        "rateLimits": {
            "primary": {"usedPercent": -2},
            "secondary": {"usedPercent": 120},
        }
    }

    result = parse_codex_rate_limits(payload, fetched_at=FIXED_NOW)

    assert [(window.label, window.used) for window in result.windows] == [
        ("主额度窗口", 0),
        ("次额度窗口", 100),
    ]


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"rateLimits": {}},
        {"rateLimits": {"primary": {"usedPercent": "25"}}},
        {"rateLimits": {"primary": {"usedPercent": 25, "resetsAt": "soon"}}},
    ],
)
def test_parser_rejects_contract_drift(payload: dict[str, Any]) -> None:
    with pytest.raises(ContractError):
        parse_codex_rate_limits(payload, fetched_at=FIXED_NOW)


def test_adapter_uses_injected_client_and_clock() -> None:
    adapter = CodexAppServerAdapter(_StubClient(_snapshot()), clock=lambda: FIXED_NOW)

    result = adapter.fetch()

    assert adapter.provider == "codex"
    assert result.fetched_at == FIXED_NOW


def test_parser_maps_optional_credits() -> None:
    payload = _snapshot()
    payload["rateLimits"]["credits"] = {
        "hasCredits": True,
        "unlimited": False,
        "balance": "50",
    }

    result = parse_codex_rate_limits(payload, fetched_at=FIXED_NOW)

    assert result.credits is not None
    assert result.credits.has_credits is True
    assert result.credits.unlimited is False
    assert result.credits.balance == "50"


def test_parser_allows_missing_or_null_credits() -> None:
    result = parse_codex_rate_limits(_snapshot(), fetched_at=FIXED_NOW)
    assert result.credits is None

    payload = _snapshot()
    payload["rateLimits"]["credits"] = None
    result_null = parse_codex_rate_limits(payload, fetched_at=FIXED_NOW)
    assert result_null.credits is None


@pytest.mark.parametrize(
    "credits",
    [
        "not-an-object",
        {"hasCredits": "yes", "unlimited": False},
        {"hasCredits": True, "unlimited": 0},
        {"hasCredits": True, "unlimited": False, "balance": 50},
        {"hasCredits": True, "unlimited": False, "balance": "   "},
        {"hasCredits": True, "unlimited": False, "balance": "x" * 33},
    ],
)
def test_parser_rejects_credits_contract_drift(credits: object) -> None:
    payload = _snapshot()
    payload["rateLimits"]["credits"] = credits
    with pytest.raises(ContractError):
        parse_codex_rate_limits(payload, fetched_at=FIXED_NOW)


def test_credits_serialize_with_camel_case_keys() -> None:
    payload = _snapshot()
    payload["rateLimits"]["credits"] = {
        "hasCredits": True,
        "unlimited": False,
        "balance": "50",
    }

    result = parse_codex_rate_limits(payload, fetched_at=FIXED_NOW)
    dumped = result.model_dump(by_alias=True)

    assert dumped["credits"] == {
        "hasCredits": True,
        "unlimited": False,
        "balance": "50",
    }


def test_jsonl_client_completes_handshake_and_ignores_notification() -> None:
    client = CodexAppServerClient(
        [sys.executable, str(FAKE_SERVER), "success"],
        timeout_seconds=2,
    )

    result = client.read_rate_limits()

    assert result["rateLimits"]["primary"]["usedPercent"] == 25


def test_jsonl_client_maps_auth_error_without_echoing_raw_error() -> None:
    client = CodexAppServerClient(
        [sys.executable, str(FAKE_SERVER), "auth_error"],
        timeout_seconds=2,
    )

    with pytest.raises(AuthError) as captured:
        client.read_rate_limits()

    assert str(captured.value) == ""


def test_jsonl_client_times_out_and_cleans_up() -> None:
    client = CodexAppServerClient(
        [sys.executable, str(FAKE_SERVER), "timeout"],
        timeout_seconds=0.05,
    )

    with pytest.raises(ProviderTimeoutError):
        client.read_rate_limits()


def test_jsonl_client_rejects_invalid_json() -> None:
    client = CodexAppServerClient(
        [sys.executable, str(FAKE_SERVER), "invalid_json"],
        timeout_seconds=2,
    )

    with pytest.raises(ContractError):
        client.read_rate_limits()


def test_command_override_requires_existing_absolute_file(tmp_path: Path) -> None:
    executable = tmp_path / "codex.exe"
    executable.write_bytes(b"fake")

    assert resolve_codex_command({"QUOTA_WATCH_CODEX_COMMAND": str(executable)}) == (
        str(executable),
    )
    with pytest.raises(ProviderConnectionError):
        resolve_codex_command({"QUOTA_WATCH_CODEX_COMMAND": "codex && echo unsafe"})
