"""QuotaAggregator 的 provider 返回顺序契约测试（阶段 6/8）。

锁定聚合层返回三家额度的稳定顺序（codex, kimi, glm），前端依赖该顺序定位卡片。
覆盖：标准三家顺序、子集注册、注册乱序仍稳定、未知 provider 落到末尾、单家。
全部离线，无真实请求/凭据。
"""

from __future__ import annotations

from app.models import ProviderQuota, QuotaWindow
from app.providers.aggregator import QuotaAggregator
from tests.fake_provider import FakeProviderAdapter


def _ok(provider: str) -> ProviderQuota:
    return ProviderQuota(
        provider=provider,  # type: ignore[arg-type]
        planName=f"{provider}-plan",
        windows=[QuotaWindow(label="5h", used=1, limit=10, unit="tokens")],
        status="ok",
    )


def test_standard_three_provider_order() -> None:
    agg = QuotaAggregator(
        [
            FakeProviderAdapter("codex", result=_ok("codex")),
            FakeProviderAdapter("kimi", result=_ok("kimi")),
            FakeProviderAdapter("glm", result=_ok("glm")),
        ]
    )
    assert [q.provider for q in agg.fetch_all()] == ["codex", "kimi", "glm"]


def test_registration_in_wrong_order_still_sorts_canonical() -> None:
    # 以 glm, codex, kimi 顺序注册，结果仍应是 codex, kimi, glm。
    agg = QuotaAggregator(
        [
            FakeProviderAdapter("glm", result=_ok("glm")),
            FakeProviderAdapter("codex", result=_ok("codex")),
            FakeProviderAdapter("kimi", result=_ok("kimi")),
        ]
    )
    assert [q.provider for q in agg.fetch_all()] == ["codex", "kimi", "glm"]


def test_subset_registration_preserves_relative_order() -> None:
    # 只注册 kimi 和 codex：结果应为 codex, kimi。
    agg = QuotaAggregator(
        [
            FakeProviderAdapter("kimi", result=_ok("kimi")),
            FakeProviderAdapter("codex", result=_ok("codex")),
        ]
    )
    assert [q.provider for q in agg.fetch_all()] == ["codex", "kimi"]


def test_single_provider_returns_single_element_list() -> None:
    agg = QuotaAggregator([FakeProviderAdapter("glm", result=_ok("glm"))])
    result = agg.fetch_all()
    assert len(result) == 1
    assert result[0].provider == "glm"


def test_order_stable_across_repeated_calls() -> None:
    agg = QuotaAggregator(
        [
            FakeProviderAdapter("glm", result=_ok("glm")),
            FakeProviderAdapter("kimi", result=_ok("kimi")),
            FakeProviderAdapter("codex", result=_ok("codex")),
        ]
    )
    first = [q.provider for q in agg.fetch_all()]
    second = [q.provider for q in agg.fetch_all()]
    third = [q.provider for q in agg.fetch_all()]
    assert first == second == third == ["codex", "kimi", "glm"]


def test_mixed_success_and_failure_preserves_order() -> None:
    from app.providers.base import RateLimitError

    agg = QuotaAggregator(
        [
            FakeProviderAdapter("glm", result=_ok("glm")),
            FakeProviderAdapter("codex", error=RateLimitError()),
            FakeProviderAdapter("kimi", result=_ok("kimi")),
        ]
    )
    # 即使 codex 失败，顺序仍是 codex(error), kimi(ok), glm(ok)。
    result = agg.fetch_all()
    assert [q.provider for q in result] == ["codex", "kimi", "glm"]
    by = {q.provider: q for q in result}
    assert by["codex"].status == "error"
    assert by["kimi"].status == "ok"
    assert by["glm"].status == "ok"
