"""Stage 6 / 卡 2 离线测试：ProviderAdapter 聚合层与缓存。

全部用 FakeProviderAdapter 注入受控结果/异常，**不发起任何真实请求，不接触凭据**。
覆盖：成功、单家失败不拖垮其他家、401/429/超时/契约变化归一化、
有旧值返回旧值+过期提示、无旧值返回纯错误、过期判断。
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from app.models import ProviderName, ProviderQuota, QuotaWindow
from app.providers.aggregator import QuotaAggregator
from app.providers.base import (
    AuthError,
    ContractError,
    ProviderConnectionError,
    ProviderTimeoutError,
    RateLimitError,
)
from tests.fake_provider import FakeProviderAdapter


def _ok(provider: ProviderName, plan: str = "测试套餐") -> ProviderQuota:
    return ProviderQuota(
        provider=provider,
        planName=plan,
        windows=[
            QuotaWindow(label="5 小时窗口", used=10, limit=100, unit="tokens"),
        ],
        status="ok",
    )


# ---- 成功路径 ----


def test_all_success_returns_three_in_stable_order() -> None:
    agg = QuotaAggregator(
        [
            FakeProviderAdapter("codex", result=_ok("codex", "ChatGPT Pro")),
            FakeProviderAdapter("kimi", result=_ok("kimi", "Kimi Moderato")),
            FakeProviderAdapter("glm", result=_ok("glm", "GLM Pro")),
        ]
    )
    results = agg.fetch_all()

    assert [q.provider for q in results] == ["codex", "kimi", "glm"]
    assert all(q.status == "ok" for q in results)
    # 成功结果带 fetchedAt。
    assert all(q.fetched_at is not None for q in results)


def test_success_writes_cache() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex"))])
    agg.fetch_all()
    assert "codex" in agg._cache


# ---- 单家失败不拖垮其他家 ----


def test_single_failure_keeps_other_providers() -> None:
    agg = QuotaAggregator(
        [
            FakeProviderAdapter("codex", result=_ok("codex")),
            FakeProviderAdapter("kimi", error=AuthError()),
            FakeProviderAdapter("glm", result=_ok("glm")),
        ]
    )
    results = agg.fetch_all()

    assert len(results) == 3
    by_provider = {q.provider: q for q in results}
    assert by_provider["codex"].status == "ok"
    assert by_provider["glm"].status == "ok"
    # 无旧值：纯错误。
    assert by_provider["kimi"].status == "error"
    assert by_provider["kimi"].windows == []
    assert by_provider["kimi"].error_message == "需要重新登录或检查凭据"


# ---- 错误归一化覆盖各 ProviderError 子类 ----


@pytest.mark.parametrize(
    "error, expected_message",
    [
        (AuthError(), "需要重新登录或检查凭据"),
        (RateLimitError(), "查询过于频繁，请稍后重试"),
        (ProviderTimeoutError(), "查询超时"),
        (ProviderConnectionError(), "无法连接到服务商"),
        (ContractError(), "服务商接口可能已变化"),
    ],
)
def test_error_normalization(error, expected_message: str) -> None:
    agg = QuotaAggregator([FakeProviderAdapter("glm", error=error)])
    (result,) = agg.fetch_all()

    assert result.provider == "glm"
    assert result.status == "error"
    assert result.error_message == expected_message


# ---- 缓存：失败有旧值 -> 返回旧值 + 过期提示 ----


def test_failure_with_cached_value_returns_stale_with_hint() -> None:
    # 第一次成功，写入缓存。
    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex"))])
    first = agg.fetch_all()[0]
    assert first.status == "ok"
    fetched_at = first.fetched_at
    assert fetched_at is not None

    # 换成会失败的适配器，模拟下次刷新出错。
    agg._adapters["codex"] = FakeProviderAdapter("codex", error=RateLimitError())
    second = agg.fetch_all()[0]

    # 有旧值：仍返回旧套餐名和窗口，但状态标 error 并附过期提示。
    assert second.plan_name == "测试套餐"
    assert len(second.windows) == 1
    assert second.status == "error"
    assert second.fetched_at == fetched_at
    assert "查询过于频繁，请稍后重试" in (second.error_message or "")
    assert "数据可能已过期" in (second.error_message or "")


def test_failure_without_cache_returns_pure_error() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("glm", error=ContractError())])
    (result,) = agg.fetch_all()

    assert result.status == "error"
    assert result.error_message == "服务商接口可能已变化"
    # 无旧值时 errorMessage 不应包含过期提示。
    assert "过期" not in (result.error_message or "")


# ---- 过期判断 ----


def test_is_stale_true_when_older_than_threshold() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex"))], staleness_threshold=3600)
    old_quota = ProviderQuota(
        provider="codex",
        planName="旧",
        windows=[],
        status="ok",
        fetchedAt=datetime.now(timezone.utc) - timedelta(hours=2),
    )
    assert agg.is_stale(old_quota) is True


def test_is_stale_false_when_recent() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex"))], staleness_threshold=3600)
    fresh_quota = ProviderQuota(
        provider="codex",
        planName="新",
        windows=[],
        status="ok",
        fetchedAt=datetime.now(timezone.utc) - timedelta(minutes=5),
    )
    assert agg.is_stale(fresh_quota) is False


def test_is_stale_true_when_no_fetched_at() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex"))])
    no_time = ProviderQuota(provider="codex", planName="x", windows=[], status="error")
    assert agg.is_stale(no_time) is True


# ---- Fake 适配器自身的契约 ----


def test_fake_adapter_requires_result_or_error() -> None:
    with pytest.raises(ValueError):
        FakeProviderAdapter("codex")
