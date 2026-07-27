"""Offline HTTP and mapping tests for the real Kimi Code adapter."""

from __future__ import annotations

from datetime import datetime, timezone

import httpx
import pytest

from app.providers.base import (
    AuthError,
    ContractError,
    ProviderConnectionError,
    ProviderTimeoutError,
    RateLimitError,
)
from app.providers.kimi_adapter import (
    KIMI_API_KEY_ENV,
    KIMI_USAGE_URL,
    KimiProviderAdapter,
    KimiUsageClient,
)


FIXED_NOW = datetime(2026, 7, 23, 8, 0, tzinfo=timezone.utc)
TEST_KEY = "test-kimi-code-key-not-a-secret"
SUCCESS_PAYLOAD = {
    "usage": {
        "name": "Weekly limit",
        "used": 40,
        "limit": 1000,
        "resetAt": "2026-07-30T00:00:00Z",
    },
    "limits": [
        {
            "detail": {"used": 1, "limit": 100, "name": "5h limit"},
            "window": {"duration": 5, "timeUnit": "HOUR"},
        }
    ],
}


def _make_client(
    handler,
    *,
    environment: dict[str, str] | None = None,
) -> tuple[httpx.Client, KimiUsageClient]:
    http_client = httpx.Client(transport=httpx.MockTransport(handler))
    usage_client = KimiUsageClient(
        environment=environment
        if environment is not None
        else {KIMI_API_KEY_ENV: TEST_KEY},
        client=http_client,
    )
    return http_client, usage_client


def test_success_uses_official_url_safe_headers_and_existing_parser() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.method == "GET"
        assert str(request.url) == KIMI_USAGE_URL
        assert request.headers["authorization"] == f"Bearer {TEST_KEY}"
        assert request.headers["accept"] == "application/json"
        assert request.headers.get("user-agent") is None
        assert request.headers.get("x-msh-platform") is None
        return httpx.Response(200, json=SUCCESS_PAYLOAD)

    http_client, usage_client = _make_client(handler)
    try:
        quota = KimiProviderAdapter(usage_client, clock=lambda: FIXED_NOW).fetch()
    finally:
        http_client.close()

    assert quota.provider == "kimi"
    assert quota.plan_name == "Kimi Code"
    assert quota.fetched_at == FIXED_NOW
    assert [(window.label, window.used, window.limit) for window in quota.windows] == [
        ("Weekly limit", 40.0, 1000.0),
        ("5h limit", 1.0, 100.0),
    ]
    assert all("官方接口本机只读" in (window.note or "") for window in quota.windows)


@pytest.mark.parametrize(
    "environment",
    [
        {},
        {KIMI_API_KEY_ENV: ""},
        {KIMI_API_KEY_ENV: "bad\nkey"},
    ],
)
def test_missing_or_invalid_key_never_sends_request(environment: dict[str, str]) -> None:
    def handler(_: httpx.Request) -> httpx.Response:
        raise AssertionError("invalid credentials must fail before HTTP")

    http_client, usage_client = _make_client(handler, environment=environment)
    try:
        with pytest.raises(AuthError):
            usage_client.read_usage()
    finally:
        http_client.close()


@pytest.mark.parametrize(
    ("status_code", "expected_error"),
    [
        (302, ContractError),
        (400, ContractError),
        (401, AuthError),
        (402, AuthError),
        (403, AuthError),
        (404, ContractError),
        (429, RateLimitError),
        (500, ProviderConnectionError),
    ],
)
def test_http_statuses_are_normalized_without_reading_error_body(
    status_code: int,
    expected_error: type[Exception],
) -> None:
    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(
            status_code,
            content=b'{"message":"must not be returned or logged"}',
            headers={"location": "https://example.invalid/steal"}
            if status_code == 302
            else None,
        )

    http_client, usage_client = _make_client(handler)
    try:
        with pytest.raises(expected_error) as captured:
            usage_client.read_usage()
    finally:
        http_client.close()

    assert str(captured.value) == ""


def test_timeout_is_normalized() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("offline timeout", request=request)

    http_client, usage_client = _make_client(handler)
    try:
        with pytest.raises(ProviderTimeoutError):
            usage_client.read_usage()
    finally:
        http_client.close()


@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(200, content=b"{broken"),
        httpx.Response(200, json=[]),
        httpx.Response(200, content=b'"' + b"x" * (1024 * 1024 + 1) + b'"'),
    ],
)
def test_invalid_or_oversized_payload_is_rejected(response: httpx.Response) -> None:
    http_client, usage_client = _make_client(lambda _: response)
    try:
        with pytest.raises(ContractError):
            usage_client.read_usage()
    finally:
        http_client.close()


def test_empty_usage_object_is_contract_error_at_adapter_boundary() -> None:
    http_client, usage_client = _make_client(lambda _: httpx.Response(200, json={}))
    try:
        with pytest.raises(ContractError):
            KimiProviderAdapter(usage_client).fetch()
    finally:
        http_client.close()
