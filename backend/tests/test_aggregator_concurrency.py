"""QuotaAggregator 并发刷新 / 重复请求竞态离线测试。

阶段 5/8 关注的“并发刷新、重复请求和竞态”风险，在此用离线方式覆盖：
- 多线程并发 fetch_all 不损坏缓存、不抛错，每次都返回完整三家结果；
- 重复请求（同一 adapter 连续 fetch）结果一致，无交叉污染；
- 共享有状态 adapter 在并发下保持各家隔离；
- fetch_all 进行中清空缓存不导致崩溃（容错）。

全部离线，不发起真实请求、不接触凭据。
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

import pytest

from app.models import ProviderQuota, QuotaWindow
from app.providers.aggregator import QuotaAggregator
from app.providers.base import RateLimitError
from tests.fake_provider import FakeProviderAdapter


def _ok(provider: str, used: int) -> ProviderQuota:
    return ProviderQuota(
        provider=provider,  # type: ignore[arg-type]
        planName=f"{provider}-plan",
        windows=[QuotaWindow(label="5h", used=used, limit=100, unit="tokens")],
        status="ok",
    )


# ---- 并发 fetch_all 不损坏缓存 / 不抛错 ----


def test_concurrent_fetch_all_returns_complete_results_each_time() -> None:
    agg = QuotaAggregator(
        [
            FakeProviderAdapter("codex", result=_ok("codex", 10)),
            FakeProviderAdapter("kimi", result=_ok("kimi", 20)),
            FakeProviderAdapter("glm", result=_ok("glm", 30)),
        ]
    )

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda _: agg.fetch_all(), range(50)))

    assert len(results) == 50
    for batch in results:
        # 每次并发调用都必须返回完整三家、稳定顺序。
        assert [q.provider for q in batch] == ["codex", "kimi", "glm"]
        assert all(q.status == "ok" for q in batch)
        by = {q.provider: q for q in batch}
        assert by["codex"].windows[0].used == 10
        assert by["kimi"].windows[0].used == 20
        assert by["glm"].windows[0].used == 30


def test_concurrent_fetch_all_with_mixed_success_and_failure() -> None:
    """并发下 Kimi 总是失败、其余成功：每次都应返回三家，Kimi 为 error，其余 ok。"""

    agg = QuotaAggregator(
        [
            FakeProviderAdapter("codex", result=_ok("codex", 1)),
            FakeProviderAdapter("kimi", error=RateLimitError()),
            FakeProviderAdapter("glm", result=_ok("glm", 3)),
        ]
    )

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda _: agg.fetch_all(), range(40)))

    for batch in results:
        by = {q.provider: q for q in batch}
        assert by["codex"].status == "ok"
        assert by["glm"].status == "ok"
        # Kimi 无旧值 -> 纯 error（并发下不产生旧值，因为总失败）。
        assert by["kimi"].status == "error"
        assert by["kimi"].windows == []


# ---- 重复请求：同一 adapter 连续 fetch 结果一致 ----


def test_repeated_fetch_returns_consistent_results() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex", 42))])
    first = agg.fetch_all()[0]
    second = agg.fetch_all()[0]
    third = agg.fetch_all()[0]

    assert first.windows[0].used == second.windows[0].used == third.windows[0].used == 42
    # 连续成功不改变 used/limit（无漂移）。
    assert first.windows[0].limit == second.windows[0].limit == third.windows[0].limit == 100


def test_repeated_fetch_after_failure_uses_cache_then_recovers() -> None:
    """先成功（写缓存）-> 反复失败（回退旧值）-> 再成功（刷新）。"""

    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex", 5))])
    ok1 = agg.fetch_all()[0]
    assert ok1.status == "ok" and ok1.windows[0].used == 5

    # 换成失败适配器，重复 3 次：每次都应回退到旧值 5。
    agg._adapters["codex"] = FakeProviderAdapter("codex", error=RateLimitError())
    for _ in range(3):
        stale = agg.fetch_all()[0]
        assert stale.status == "error"
        assert stale.windows[0].used == 5  # 旧值
        assert "数据可能已过期" in (stale.error_message or "")

    # 恢复成功（新值 9）：缓存被刷新，不再过期。
    agg._adapters["codex"] = FakeProviderAdapter("codex", result=_ok("codex", 9))
    recovered = agg.fetch_all()[0]
    assert recovered.status == "ok"
    assert recovered.windows[0].used == 9


# ---- 共享有状态 adapter 的隔离 ----


class _CountingAdapter:
    """记录被调用次数的假适配器，用于验证并发下各家独立计数、互不串扰。"""

    def __init__(self, provider: str) -> None:
        self.provider = provider  # type: ignore[assignment]
        self.call_count = 0

    def fetch(self) -> ProviderQuota:
        self.call_count += 1
        return _ok(self.provider, self.call_count)  # type: ignore[arg-type]


def test_shared_stateful_adapters_isolated_under_concurrency() -> None:
    codex = _CountingAdapter("codex")
    kimi = _CountingAdapter("kimi")
    glm = _CountingAdapter("glm")
    agg = QuotaAggregator([codex, kimi, glm])  # type: ignore[list-item]

    with ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(lambda _: agg.fetch_all(), range(30)))

    # 每家各被调用 30 次（无串扰、无丢失）。
    assert codex.call_count == 30
    assert kimi.call_count == 30
    assert glm.call_count == 30
    # 每次结果三家齐全。
    assert all(len(batch) == 3 for batch in results)


# ---- fetch_all 进行中清空缓存不崩溃 ----


def test_clearing_cache_during_iteration_does_not_crash(monkeypatch) -> None:
    """模拟极端竞态：在 _fetch_one 写缓存后、下一次读取前清空缓存。

    由于当前 fetch_all 是顺序执行，真正“进行中清空”需注入；这里验证：
    即使缓存被外部清空，后续失败查询返回纯 error（无旧值），不抛 KeyError。
    """

    agg = QuotaAggregator(
        [
            FakeProviderAdapter("codex", result=_ok("codex", 1)),
            FakeProviderAdapter("kimi", error=RateLimitError()),
        ]
    )
    # 先成功写 codex 缓存。
    first = agg.fetch_all()
    assert {q.provider: q for q in first}["codex"].status == "ok"

    # 外部清空缓存（模拟另一线程 reset）。
    agg._cache.clear()

    # 再次查询：Kimi 失败且无缓存 -> 纯 error，不抛错。
    second = agg.fetch_all()
    by = {q.provider: q for q in second}
    assert by["kimi"].status == "error"
    assert by["kimi"].windows == []
    # codex 仍可重新成功。
    assert by["codex"].status == "ok"


# ---- 多家同时失败不互相影响错误文案 ----


def test_multiple_providers_failing_simultaneously_keep_distinct_messages() -> None:
    from app.providers.base import AuthError, ContractError, ProviderTimeoutError

    agg = QuotaAggregator(
        [
            FakeProviderAdapter("codex", error=AuthError()),
            FakeProviderAdapter("kimi", error=ProviderTimeoutError()),
            FakeProviderAdapter("glm", error=ContractError()),
        ]
    )
    by = {q.provider: q for q in agg.fetch_all()}
    assert by["codex"].error_message == "需要重新登录或检查凭据"
    assert by["kimi"].error_message == "查询超时"
    assert by["glm"].error_message == "服务商接口可能已变化"
