"""Gate, isolation, and combined-mode tests for real GLM quota data."""

from __future__ import annotations

from datetime import datetime, timezone
from threading import Barrier

from fastapi.testclient import TestClient

from app import main
from app.models import ProviderName, ProviderQuota, QuotaWindow


client = TestClient(main.app)
FIXED_NOW = datetime(2026, 7, 23, 9, 0, tzinfo=timezone.utc)


class _ExplodingAggregator:
    def fetch_all(self):
        raise AssertionError("this aggregator must not be queried")


class _SuccessfulAggregator:
    def __init__(self, provider: ProviderName, *, barrier: Barrier | None = None):
        self.provider = provider
        self.barrier = barrier
        self.calls = 0

    def fetch_all(self) -> list[ProviderQuota]:
        self.calls += 1
        if self.barrier is not None:
            self.barrier.wait(timeout=2)
        return [
            ProviderQuota(
                provider=self.provider,
                planName=f"{self.provider.upper()} real",
                windows=[
                    QuotaWindow(
                        label="real window",
                        used=25,
                        limit=100,
                        unit="tokens",
                        resetAt=datetime(
                            2026,
                            7,
                            23,
                            12,
                            0,
                            tzinfo=timezone.utc,
                        ),
                    )
                ],
                fetchedAt=FIXED_NOW,
            )
        ]


class _ErrorAggregator:
    def __init__(self, provider: ProviderName):
        self.provider = provider

    def fetch_all(self) -> list[ProviderQuota]:
        return [
            ProviderQuota(
                provider=self.provider,
                planName="未知套餐",
                status="error",
                errorMessage="归一化测试错误",
                windows=[],
            )
        ]


def test_glm_real_is_disabled_by_default(monkeypatch) -> None:
    monkeypatch.setattr(main, "_GLM_REAL_ENABLED", False)
    monkeypatch.setattr(main, "_glm_real_aggregator", _ExplodingAggregator())

    response = client.get("/api/v1/quotas", params={"scenario": "glm_real"})

    assert response.status_code == 503
    assert response.json()["detail"] == {
        "code": "glm_real_disabled",
        "message": "GLM 真实额度未启用；请先确认使用边界，再安全设置 Key 和环境开关",
    }


def test_glm_real_returns_glm_and_marks_other_providers_not_queried(
    monkeypatch,
) -> None:
    monkeypatch.setattr(main, "_GLM_REAL_ENABLED", True)
    monkeypatch.setattr(
        main,
        "_glm_real_aggregator",
        _SuccessfulAggregator("glm"),
    )

    response = client.get("/api/v1/quotas", params={"scenario": "glm_real"})

    assert response.status_code == 200
    payload = response.json()
    assert [item["provider"] for item in payload] == ["codex", "kimi", "glm"]
    assert payload[2]["planName"] == "GLM real"
    assert payload[2]["windows"][0]["used"] == 25
    assert payload[0]["planName"] == payload[1]["planName"] == "当前场景未查询"


def test_all_real_shows_codex_and_kimi_without_calling_disabled_glm(
    monkeypatch,
) -> None:
    codex = _SuccessfulAggregator("codex")
    kimi = _SuccessfulAggregator("kimi")
    monkeypatch.setattr(main, "_CODEX_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_KIMI_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_GLM_REAL_ENABLED", False)
    monkeypatch.setattr(main, "_codex_real_aggregator", codex)
    monkeypatch.setattr(main, "_kimi_real_aggregator", kimi)
    monkeypatch.setattr(main, "_glm_real_aggregator", _ExplodingAggregator())

    response = client.get("/api/v1/quotas", params={"scenario": "all_real"})

    assert response.status_code == 200
    payload = response.json()
    assert [item["provider"] for item in payload] == ["codex", "kimi", "glm"]
    assert payload[0]["status"] == payload[1]["status"] == "ok"
    assert payload[2]["planName"] == "真实查询未启用"
    assert payload[2]["status"] == "unknown"
    assert codex.calls == 1
    assert payload[1]["status"] == "ok"
    assert kimi.calls == 1


def test_all_real_queries_all_enabled_providers_concurrently(monkeypatch) -> None:
    barrier = Barrier(3)
    aggregators = {
        provider: _SuccessfulAggregator(provider, barrier=barrier)
        for provider in ("codex", "kimi", "glm")
    }
    monkeypatch.setattr(main, "_CODEX_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_KIMI_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_GLM_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_codex_real_aggregator", aggregators["codex"])
    monkeypatch.setattr(main, "_kimi_real_aggregator", aggregators["kimi"])
    monkeypatch.setattr(main, "_glm_real_aggregator", aggregators["glm"])

    response = client.get("/api/v1/quotas", params={"scenario": "all_real"})

    assert response.status_code == 200
    payload = response.json()
    assert [item["provider"] for item in payload] == ["codex", "kimi", "glm"]
    assert all(item["status"] == "ok" for item in payload)
    assert all(aggregator.calls == 1 for aggregator in aggregators.values())


def test_all_real_keeps_other_results_when_one_provider_fails(monkeypatch) -> None:
    monkeypatch.setattr(main, "_CODEX_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_KIMI_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_GLM_REAL_ENABLED", True)
    monkeypatch.setattr(
        main,
        "_codex_real_aggregator",
        _SuccessfulAggregator("codex"),
    )
    monkeypatch.setattr(main, "_kimi_real_aggregator", _ErrorAggregator("kimi"))
    monkeypatch.setattr(main, "_glm_real_aggregator", _SuccessfulAggregator("glm"))

    response = client.get("/api/v1/quotas", params={"scenario": "all_real"})

    assert response.status_code == 200
    payload = response.json()
    assert payload[0]["status"] == "ok"
    assert payload[1]["status"] == "error"
    assert payload[2]["status"] == "ok"


def test_all_real_sanitizes_unexpected_orchestration_failure(monkeypatch) -> None:
    monkeypatch.setattr(main, "_CODEX_REAL_ENABLED", False)
    monkeypatch.setattr(main, "_KIMI_REAL_ENABLED", False)
    monkeypatch.setattr(main, "_GLM_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_glm_real_aggregator", _ExplodingAggregator())

    response = client.get("/api/v1/quotas", params={"scenario": "all_real"})

    assert response.status_code == 200
    glm = response.json()[2]
    assert glm["status"] == "error"
    assert glm["errorMessage"] == "本地综合查询失败"
    assert "must not be queried" not in str(glm)
