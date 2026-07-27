"""Stage 6 / 卡 3 集成测试：Kimi 解析器 -> KimiFixtureAdapter -> 聚合器 -> 缓存（全部离线）。

证明 parse_kimi_usage 产出的窗口能经 KimiFixtureAdapter 喂入 QuotaAggregator，
并复用缓存回退与过期提示逻辑。**不发起任何真实请求、不接触凭据**。
"""

from __future__ import annotations

from app.models import ProviderQuota, QuotaWindow
from app.providers.aggregator import QuotaAggregator
from app.providers.base import RateLimitError
from tests.fake_provider import FakeProviderAdapter
from tests.fixture_adapters import KimiFixtureAdapter

# 官方样例衍生的脱敏响应（usage + limits 两窗口）。
KIMI_RESPONSE = {
    "usage": {"used": 40, "limit": 1000, "name": "Weekly limit"},
    "limits": [
        {"detail": {"used": 1, "limit": 100}, "window": {"duration": 5, "timeUnit": "HOUR"}},
    ],
}


def test_kimi_fixture_adapter_parses_windows() -> None:
    adapter = KimiFixtureAdapter(KIMI_RESPONSE)
    quota = adapter.fetch()

    assert quota.provider == "kimi"
    assert quota.status == "ok"
    labels = [w.label for w in quota.windows]
    assert labels == ["Weekly limit", "5h limit"]


def test_kimi_adapter_feeds_aggregator_alongside_others() -> None:
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
            FakeProviderAdapter("glm", error=RateLimitError()),
        ]
    )
    results = agg.fetch_all()

    assert [q.provider for q in results] == ["codex", "kimi", "glm"]
    by = {q.provider: q for q in results}
    assert by["codex"].status == "ok"
    assert by["kimi"].status == "ok"
    assert by["kimi"].plan_name == "Kimi Moderato"
    assert [w.label for w in by["kimi"].windows] == ["Weekly limit", "5h limit"]
    # GLM 无旧值 -> 纯错误。
    assert by["glm"].status == "error"
    assert by["glm"].error_message == "查询过于频繁，请稍后重试"


def test_kimi_cache_fallback_returns_stale_with_hint() -> None:
    agg = QuotaAggregator([KimiFixtureAdapter(KIMI_RESPONSE)])
    first = agg.fetch_all()[0]
    assert first.status == "ok"
    fetched_at = first.fetched_at
    assert fetched_at is not None

    # 第二次让 Kimi 失败，应回退到旧窗口 + 过期提示。
    agg._adapters["kimi"] = KimiFixtureAdapter({}, error=RateLimitError())
    second = agg.fetch_all()[0]

    assert second.status == "error"
    # 旧窗口仍在（来自缓存）。
    assert [w.label for w in second.windows] == ["Weekly limit", "5h limit"]
    assert second.fetched_at == fetched_at
    assert "查询过于频繁" in (second.error_message or "")
    assert "数据可能已过期" in (second.error_message or "")


def test_kimi_adapter_accepts_json_string_payload() -> None:
    import json

    adapter = KimiFixtureAdapter(json.dumps(KIMI_RESPONSE))
    quota = adapter.fetch()
    assert len(quota.windows) == 2
