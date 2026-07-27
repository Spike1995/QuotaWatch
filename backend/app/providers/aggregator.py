"""Quota aggregator with last-success cache and staleness (stage 6 / 卡 2).

并行查询多家 Provider，单家失败不拖垮其他家：
- 成功 -> 写缓存并返回；
- 失败且有旧值 -> 返回旧值 + status="error" + “数据可能已过期”提示；
- 失败且无旧值 -> 返回 status="error" + 归一化错误文案。

本模块只依赖 ProviderAdapter 协议，不绑定任何真实 Provider。
"""

from __future__ import annotations

from datetime import datetime, timezone

from ..models import ProviderName, ProviderQuota
from .base import ProviderAdapter, ProviderError


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _stale_message(quota: ProviderQuota) -> str:
    """失败回退旧值时附加的过期提示，包含旧数据的 fetchedAt（若有）。"""

    base = "数据可能已过期"
    if quota.fetched_at is not None:
        fetched = quota.fetched_at
        # 只暴露归一化后的 ISO 时间，不暴露任何敏感信息。
        return f"{base}（最近成功于 {fetched.isoformat()})"
    return base


class QuotaAggregator:
    """聚合多家 ProviderAdapter，带内存级最后成功缓存。

    staleness_threshold: 旧值被当作“可能已过期”的阈值（秒）。仅影响提示文案，
    不影响是否返回旧值——有旧值就返回旧值 + 提示。
    """

    def __init__(self, adapters: list[ProviderAdapter], staleness_threshold: float = 6 * 3600):
        self._adapters = {adapter.provider: adapter for adapter in adapters}
        self._cache: dict[ProviderName, ProviderQuota] = {}
        self._staleness_threshold = staleness_threshold
        # 阶段 6 §3 的 CachedQuota 设计：记录最近一次失败用于诊断（不进 JSON/前端/日志原文）。
        # 结构：{provider: (异常类型名, 用户文案, 发生时间)}。
        self._last_errors: dict[ProviderName, tuple[str, str, datetime]] = {}

    def fetch_all(self) -> list[ProviderQuota]:
        """查询全部已注册 Provider，单家失败不抛出，返回归一化结果列表。"""

        results: list[ProviderQuota] = []
        for provider, adapter in self._adapters.items():
            results.append(self._fetch_one(provider, adapter))
        # 保持 codex, kimi, glm 的稳定顺序，便于前端。
        order = {"codex": 0, "kimi": 1, "glm": 2}
        results.sort(key=lambda q: order.get(q.provider, 99))
        return results

    def _fetch_one(self, provider: ProviderName, adapter: ProviderAdapter) -> ProviderQuota:
        try:
            quota = adapter.fetch()
        except ProviderError as error:
            return self._on_error(provider, error)
        # 成功：写缓存（要求返回的 status 是 ok/degraded 才算“成功结果”）。
        if quota.status in ("ok", "degraded"):
            quota.fetched_at = quota.fetched_at or _now_utc()
            self._cache[provider] = quota
        return quota

    def _on_error(self, provider: ProviderName, error: ProviderError) -> ProviderQuota:
        # 记录最近一次失败用于诊断（仅类型名 + 归一化文案 + 时间，不含原始响应）。
        self._last_errors[provider] = (type(error).__name__, error.user_message, _now_utc())
        cached = self._cache.get(provider)
        if cached is not None:
            # 有旧值：返回旧值，但把状态标为 error 并附加过期提示。
            return ProviderQuota(
                provider=cached.provider,
                planName=cached.plan_name,
                windows=list(cached.windows),
                planType=cached.plan_type,
                expiresAt=cached.expires_at,
                status="error",
                errorMessage=f"{error.user_message}；{_stale_message(cached)}",
                fetchedAt=cached.fetched_at,
                credits=cached.credits,
                resetAllowance=cached.reset_allowance,
            )
        # 无旧值：纯错误。
        return ProviderQuota(
            provider=provider,
            planName="未知套餐",
            windows=[],
            status="error",
            errorMessage=error.user_message,
        )

    def last_error(self, provider: ProviderName) -> tuple[str, str, datetime] | None:
        """返回某家最近一次失败诊断（异常类型名、归一化文案、时间），无失败则 None。

        仅供后端诊断/日志，不含原始敏感响应；不进入前端 JSON。
        """

        return self._last_errors.get(provider)

    def clear_last_error(self, provider: ProviderName) -> bool:
        """清除某家的最近失败诊断。返回是否确实清除了一条记录。

        供运维/测试在确认问题已解决后重置诊断，避免长时间运行进程中残留误导性旧失败记录。
        """

        return self._last_errors.pop(provider, None) is not None

    def is_stale(self, quota: ProviderQuota, now: datetime | None = None) -> bool:
        """判断某条结果是否超过过期阈值（供前端展示“可能已过期”标记）。"""

        if quota.fetched_at is None:
            return True
        reference = now or _now_utc()
        # 兼容 naive/aware datetime：统一转 UTC 比较。
        fetched = quota.fetched_at
        if fetched.tzinfo is None:
            fetched = fetched.replace(tzinfo=timezone.utc)
        if reference.tzinfo is None:
            reference = reference.replace(tzinfo=timezone.utc)
        age = (reference - fetched).total_seconds()
        return age > self._staleness_threshold
