"""Test-only stub provider adapter (not production code).

阶段 9（假数据移除）：原 app/providers/fake.py 的 FakeProviderAdapter 是
纯测试替身，不产生任何用户可见数据，只用于测试 QuotaAggregator 的
隔离/并发/排序/错误传播逻辑。删除 app 侧的假数据后，把它保留在 tests/
目录下作为测试 helper，避免破坏聚合器单元测试。
"""

from __future__ import annotations

from typing import Optional

from app.models import ProviderName, ProviderQuota
from app.providers.base import ProviderError


class FakeProviderAdapter:
    """注入预设结果或异常的测试适配器，不发起任何请求、不接触凭据。"""

    def __init__(
        self,
        provider: ProviderName,
        *,
        result: Optional[ProviderQuota] = None,
        error: Optional[ProviderError] = None,
    ) -> None:
        if result is None and error is None:
            raise ValueError("FakeProviderAdapter 需要 result 或 error 之一")
        if result is not None and error is not None:
            raise ValueError("result 与 error 不能同时给出")
        self._provider = provider
        self._result = result
        self._error = error

    @property
    def provider(self) -> ProviderName:
        return self._provider

    def fetch(self) -> ProviderQuota:
        if self._error is not None:
            raise self._error
        assert self._result is not None
        return self._result
