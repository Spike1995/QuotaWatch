"""Default-off GLM Coding Plan quota adapter.

The API key is read only from ``QUOTA_WATCH_GLM_API_KEY`` at request time.
It is never logged, cached, returned, or loaded from ZCode/worker config.
Production requests are restricted to the quota endpoint used by the official
GLM Plan Usage plugin and never follow redirects.

This module implements an explicitly gated local experiment. The existence of
the official plugin source proves the wire contract, but does not by itself
grant third-party usage permission.
"""

from __future__ import annotations

import json
import os
from collections.abc import Callable, Mapping
from datetime import datetime, timezone
from typing import Any

import httpx

from ..models import ProviderName, ProviderQuota
from .base import (
    AuthError,
    ContractError,
    ProviderConnectionError,
    ProviderError,
    ProviderTimeoutError,
    RateLimitError,
)
from .glm_parser import parse_glm_usage

GLM_USAGE_URL = "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
GLM_API_KEY_ENV = "QUOTA_WATCH_GLM_API_KEY"
_MAX_RESPONSE_BYTES = 1024 * 1024


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


class GlmUsageClient:
    """Read one GLM quota payload without retaining raw account data."""

    def __init__(
        self,
        *,
        timeout_seconds: float = 8.0,
        environment: Mapping[str, str] | None = None,
        api_key_resolver: Callable[[], str | None] | None = None,
        client: httpx.Client | None = None,
    ) -> None:
        if timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        self._timeout_seconds = timeout_seconds
        self._environment = environment
        self._api_key_resolver = api_key_resolver
        self._client = client

    def read_usage(self) -> Mapping[str, Any]:
        if self._api_key_resolver is not None:
            api_key = (self._api_key_resolver() or "").strip()
        else:
            source = self._environment if self._environment is not None else os.environ
            api_key = source.get(GLM_API_KEY_ENV, "").strip()
        if not api_key or len(api_key) > 8192 or "\r" in api_key or "\n" in api_key:
            raise AuthError()

        owns_client = self._client is None
        client = self._client or httpx.Client(
            timeout=self._timeout_seconds,
            follow_redirects=False,
            trust_env=True,
        )
        response: httpx.Response | None = None
        try:
            request = client.build_request(
                "GET",
                GLM_USAGE_URL,
                headers={
                    # Follow zai-org/zai-coding-plugins exactly: the Coding
                    # Plan token is assigned directly to Authorization.
                    "Authorization": api_key,
                    "Accept-Language": "en-US,en",
                    "Content-Type": "application/json",
                },
            )
            # Node's official plugin request does not add a custom UA.
            request.headers.pop("user-agent", None)
            request.headers.pop("accept", None)
            response = client.send(request, stream=True)
            _raise_for_status(response.status_code)
            payload = bytearray()
            for chunk in response.iter_bytes():
                if len(payload) + len(chunk) > _MAX_RESPONSE_BYTES:
                    raise ContractError()
                payload.extend(chunk)
            return _decode_payload(bytes(payload))
        except ProviderError:
            raise
        except httpx.TimeoutException:
            raise ProviderTimeoutError() from None
        except httpx.HTTPError:
            raise ProviderConnectionError() from None
        finally:
            if response is not None:
                response.close()
            if owns_client:
                client.close()


class GlmProviderAdapter:
    """Convert GLM quota-limit data into the shared quota contract."""

    def __init__(
        self,
        client: GlmUsageClient | None = None,
        *,
        clock: Callable[[], datetime] = _now_utc,
    ) -> None:
        self._client = client or GlmUsageClient()
        self._clock = clock

    @property
    def provider(self) -> ProviderName:
        return "glm"

    def fetch(self) -> ProviderQuota:
        windows = parse_glm_usage(self._client.read_usage())
        if not windows:
            raise ContractError()
        source_note = "GLM 官方插件契约，本机实验性只读数据"
        for window in windows:
            window.note = (
                f"{window.note}；{source_note}" if window.note else source_note
            )
        return ProviderQuota(
            provider="glm",
            plan_name="GLM Coding Plan",
            windows=windows,
            status="ok",
            fetched_at=self._clock(),
        )


def _raise_for_status(status_code: int) -> None:
    if 200 <= status_code < 300:
        return
    if status_code in (401, 402, 403):
        raise AuthError()
    if status_code == 429:
        raise RateLimitError()
    if status_code in (400, 404) or 300 <= status_code < 400:
        raise ContractError()
    raise ProviderConnectionError()


def _decode_payload(raw: bytes) -> Mapping[str, Any]:
    try:
        decoded = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ContractError() from None
    if not isinstance(decoded, Mapping):
        raise ContractError()
    return decoded
