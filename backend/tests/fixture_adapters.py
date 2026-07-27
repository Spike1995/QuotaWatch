"""Test-only fixture adapters wrapping the REAL parsers (not production code).

阶段 9（假数据移除）：原 app/providers/kimi_fixture.py 与 glm_fixture.py 是
真实解析器（parse_kimi_usage / parse_glm_usage）的离线测试封装——它们接收
脱敏响应 dict，调用真实解析逻辑产出 QuotaWindow。删除 app 侧假数据后，
把它们作为测试 helper 保留在 tests/，保护真实解析链的回归覆盖。

它们不发起任何请求、不接触凭据，仅在测试中喂入脱敏样例。
"""

from __future__ import annotations

from typing import Any, Optional

from app.models import ProviderName, ProviderQuota
from app.providers.base import ProviderError
from app.providers.glm_parser import parse_glm_usage
from app.providers.kimi_parser import parse_kimi_usage


def _coerce_payload(payload: Any) -> Any:
    """允许传入 dict 或 JSON 字符串。"""
    if isinstance(payload, str):
        import json

        return json.loads(payload)
    return payload


class KimiFixtureAdapter:
    """用脱敏响应驱动真实 parse_kimi_usage 的测试适配器。"""

    provider: ProviderName = "kimi"

    def __init__(
        self,
        response: Any,
        *,
        plan_name: str = "Kimi",
        error: Optional[ProviderError] = None,
    ) -> None:
        self._response = response
        self._plan_name = plan_name
        self._error = error

    def fetch(self) -> ProviderQuota:
        if self._error is not None:
            raise self._error
        payload = _coerce_payload(self._response)
        windows = parse_kimi_usage(payload)
        return ProviderQuota(
            provider="kimi",
            plan_name=self._plan_name,
            windows=windows,
            status="ok" if windows else "degraded",
        )


class GlmFixtureAdapter:
    """用脱敏响应驱动真实 parse_glm_usage 的测试适配器。"""

    provider: ProviderName = "glm"

    def __init__(
        self,
        response: Any,
        *,
        plan_name: str = "GLM",
        error: Optional[ProviderError] = None,
    ) -> None:
        self._response = response
        self._plan_name = plan_name
        self._error = error

    def fetch(self) -> ProviderQuota:
        if self._error is not None:
            raise self._error
        payload = _coerce_payload(self._response)
        windows = parse_glm_usage(payload)
        return ProviderQuota(
            provider="glm",
            plan_name=self._plan_name,
            windows=windows,
            status="ok" if windows else "degraded",
        )
