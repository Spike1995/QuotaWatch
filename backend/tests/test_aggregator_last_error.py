"""QuotaAggregator.last_error 诊断测试（阶段 6 §3 CachedQuota 设计）。

验证聚合层记录每家最近一次失败的异常类型、归一化文案与时间，供后端诊断；
不含原始敏感响应，不进入前端 JSON。全部离线，无真实请求/凭据。
"""

from __future__ import annotations

from app.providers.aggregator import QuotaAggregator
from app.providers.base import AuthError, RateLimitError
from tests.fake_provider import FakeProviderAdapter
from app.models import ProviderQuota, QuotaWindow


def _ok(provider: str) -> ProviderQuota:
    return ProviderQuota(
        provider=provider,  # type: ignore[arg-type]
        planName=f"{provider}-plan",
        windows=[QuotaWindow(label="5h", used=1, limit=10, unit="tokens")],
        status="ok",
    )


def test_no_error_returns_none() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex"))])
    agg.fetch_all()
    assert agg.last_error("codex") is None


def test_error_without_cache_records_last_error() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", error=AuthError())])
    agg.fetch_all()
    err = agg.last_error("codex")
    assert err is not None
    type_name, message, when = err
    assert type_name == "AuthError"
    assert message == "需要重新登录或检查凭据"
    assert when is not None


def test_error_with_cache_records_last_error_and_keeps_cache() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex"))])
    agg.fetch_all()  # 成功，无 error
    assert agg.last_error("codex") is None

    agg._adapters["codex"] = FakeProviderAdapter("codex", error=RateLimitError())
    agg.fetch_all()  # 失败回退旧值
    err = agg.last_error("codex")
    assert err is not None
    assert err[0] == "RateLimitError"
    assert err[1] == "查询过于频繁，请稍后重试"
    # 旧值仍在缓存。
    assert "codex" in agg._cache


def test_last_error_updates_to_most_recent_failure() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", error=AuthError())])
    agg.fetch_all()
    assert agg.last_error("codex")[0] == "AuthError"

    agg._adapters["codex"] = FakeProviderAdapter("codex", error=RateLimitError())
    agg.fetch_all()
    # 最近一次失败更新为 RateLimitError。
    assert agg.last_error("codex")[0] == "RateLimitError"


def test_last_error_isolated_per_provider() -> None:
    agg = QuotaAggregator(
        [
            FakeProviderAdapter("codex", error=AuthError()),
            FakeProviderAdapter("kimi", result=_ok("kimi")),
            FakeProviderAdapter("glm", error=RateLimitError()),
        ]
    )
    agg.fetch_all()
    assert agg.last_error("codex")[0] == "AuthError"
    assert agg.last_error("kimi") is None
    assert agg.last_error("glm")[0] == "RateLimitError"


def test_successful_fetch_after_error_does_not_clear_last_error() -> None:
    """成功后不清除诊断（保留最近一次失败供排查）；前端以返回的 status 为准。"""

    agg = QuotaAggregator([FakeProviderAdapter("codex", error=AuthError())])
    agg.fetch_all()
    assert agg.last_error("codex") is not None

    agg._adapters["codex"] = FakeProviderAdapter("codex", result=_ok("codex"))
    result = agg.fetch_all()
    by = {q.provider: q for q in result}
    assert by["codex"].status == "ok"  # 成功返回 ok
    # last_error 仍保留最近一次失败（诊断用途，不因成功而抹除）。
    assert agg.last_error("codex") is not None
    assert agg.last_error("codex")[0] == "AuthError"


def test_clear_last_error_removes_record() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", error=AuthError())])
    agg.fetch_all()
    assert agg.last_error("codex") is not None

    cleared = agg.clear_last_error("codex")
    assert cleared is True
    assert agg.last_error("codex") is None


def test_clear_last_error_returns_false_when_no_record() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", result=_ok("codex"))])
    agg.fetch_all()
    # 从未失败 -> 清除返回 False，不抛错。
    assert agg.clear_last_error("codex") is False
    assert agg.clear_last_error("kimi") is False  # 未注册也安全


def test_clear_last_error_isolated_per_provider() -> None:
    agg = QuotaAggregator(
        [
            FakeProviderAdapter("codex", error=AuthError()),
            FakeProviderAdapter("kimi", error=RateLimitError()),
        ]
    )
    agg.fetch_all()
    # 只清 codex，kimi 保留。
    assert agg.clear_last_error("codex") is True
    assert agg.last_error("codex") is None
    assert agg.last_error("kimi") is not None
    assert agg.last_error("kimi")[0] == "RateLimitError"


def test_clear_then_new_failure_records_again() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("codex", error=AuthError())])
    agg.fetch_all()
    agg.clear_last_error("codex")
    assert agg.last_error("codex") is None

    # 再次失败应重新记录。
    agg.fetch_all()
    assert agg.last_error("codex") is not None
    assert agg.last_error("codex")[0] == "AuthError"

