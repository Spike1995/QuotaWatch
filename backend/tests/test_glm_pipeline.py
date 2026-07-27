"""Stage 6 集成测试：GLM 解析器 -> GlmFixtureAdapter，以及三家离线聚合演示。

证明 parse_glm_usage 产出的窗口能经 GlmFixtureAdapter 喂入 QuotaAggregator，
并与 Kimi fixture + Codex fake 一起并行聚合（全部离线）。
**不发起任何真实请求、不接触凭据**。GLM 真实查询默认禁用，此处仅离线回归。
"""

from __future__ import annotations

from app.models import ProviderQuota, QuotaWindow
from app.providers.aggregator import QuotaAggregator
from app.providers.base import RateLimitError
from tests.fake_provider import FakeProviderAdapter
from tests.fixture_adapters import GlmFixtureAdapter
from tests.fixture_adapters import KimiFixtureAdapter

GLM_RESPONSE = {
    "code": 200,
    "data": {
        "limits": [
            {"type": "TOKENS_LIMIT", "unit": 3, "usage": 40000000, "currentValue": 12345678, "nextResetTime": 1760000000000},
            {"type": "TOKENS_LIMIT", "unit": 6, "usage": 280000000, "currentValue": 89000000, "nextResetTime": 1760500000000},
        ]
    },
}

KIMI_RESPONSE = {
    "usage": {"used": 40, "limit": 1000, "name": "Weekly limit"},
    "limits": [{"detail": {"used": 1, "limit": 100}, "window": {"duration": 5, "timeUnit": "HOUR"}}],
}


def test_glm_fixture_adapter_parses_two_token_windows() -> None:
    adapter = GlmFixtureAdapter(GLM_RESPONSE)
    quota = adapter.fetch()

    assert quota.provider == "glm"
    assert quota.status == "ok"
    labels = [w.label for w in quota.windows]
    assert "5 小时窗口" in labels
    assert "周窗口" in labels
    # usage=上限, currentValue=已用
    five_h = next(w for w in quota.windows if w.label == "5 小时窗口")
    assert five_h.limit == 40000000
    assert five_h.used == 12345678


def test_three_providers_offline_aggregate() -> None:
    """Codex(fake) + Kimi(fixture) + GLM(fixture) 并行聚合，全部离线。"""

    agg = QuotaAggregator(
        [
            FakeProviderAdapter(
                "codex",
                result=ProviderQuota(
                    provider="codex",
                    planName="ChatGPT Pro",
                    windows=[QuotaWindow(label="5h", used=10, limit=100, unit="tokens")],
                    status="ok",
                ),
            ),
            KimiFixtureAdapter(KIMI_RESPONSE, plan_name="Kimi Moderato"),
            GlmFixtureAdapter(GLM_RESPONSE, plan_name="GLM Coding Plan"),
        ]
    )
    results = agg.fetch_all()

    assert [q.provider for q in results] == ["codex", "kimi", "glm"]
    by = {q.provider: q for q in results}
    assert all(q.status == "ok" for q in results)
    # 三家都至少解析出一个窗口。
    assert len(by["codex"].windows) >= 1
    assert len(by["kimi"].windows) == 2
    assert len(by["glm"].windows) == 2


def test_glm_cache_fallback_with_kimi_still_ok() -> None:
    """GLM 失败回退旧值，Kimi 仍正常（单家失败不拖垮其他家）。"""

    agg = QuotaAggregator(
        [
            KimiFixtureAdapter(KIMI_RESPONSE),
            GlmFixtureAdapter(GLM_RESPONSE),
        ]
    )
    first = {q.provider: q for q in agg.fetch_all()}
    assert first["glm"].status == "ok"

    # 让 GLM 第二次失败。
    agg._adapters["glm"] = GlmFixtureAdapter({}, error=RateLimitError())
    second = {q.provider: q for q in agg.fetch_all()}

    assert second["kimi"].status == "ok"
    assert second["glm"].status == "error"
    # 旧窗口仍在。
    assert len(second["glm"].windows) == 2
    assert "数据可能已过期" in (second["glm"].error_message or "")
