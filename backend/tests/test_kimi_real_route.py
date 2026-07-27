"""FastAPI gate and contract tests for the Kimi-only real scenario."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app import main
from app.models import ProviderQuota, QuotaWindow


client = TestClient(main.app)


class _ExplodingAggregator:
    def fetch_all(self):
        raise AssertionError("disabled route must not query Kimi")


class _SuccessfulAggregator:
    def fetch_all(self) -> list[ProviderQuota]:
        return [
            ProviderQuota(
                provider="kimi",
                planName="Kimi Code",
                windows=[
                    QuotaWindow(
                        label="5h limit",
                        used=25,
                        limit=100,
                        unit="tokens",
                        resetAt=datetime(2026, 7, 23, 12, 0, tzinfo=timezone.utc),
                    )
                ],
                fetchedAt=datetime(2026, 7, 23, 8, 0, tzinfo=timezone.utc),
            )
        ]


def test_kimi_real_is_disabled_by_default(monkeypatch) -> None:
    monkeypatch.setattr(main, "_KIMI_REAL_ENABLED", False)
    monkeypatch.setattr(main, "_kimi_real_aggregator", _ExplodingAggregator())

    response = client.get("/api/v1/quotas", params={"scenario": "kimi_real"})

    assert response.status_code == 503
    assert response.json()["detail"] == {
        "code": "kimi_real_disabled",
        "message": "Kimi 真实额度未启用；请先安全设置 Key 并用环境开关启动本地后端",
    }


def test_kimi_real_returns_actual_kimi_and_marks_other_providers_unknown(monkeypatch) -> None:
    monkeypatch.setattr(main, "_KIMI_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_kimi_real_aggregator", _SuccessfulAggregator())

    response = client.get("/api/v1/quotas", params={"scenario": "kimi_real"})

    assert response.status_code == 200
    payload = response.json()
    assert [item["provider"] for item in payload] == ["codex", "kimi", "glm"]
    assert payload[1]["planName"] == "Kimi Code"
    assert payload[1]["windows"][0]["used"] == 25
    assert payload[1]["windows"][0]["unit"] == "tokens"
    assert payload[0]["status"] == payload[2]["status"] == "unknown"
    assert payload[0]["planName"] == "当前场景未查询"
    assert payload[2]["planName"] == "当前场景未查询"
