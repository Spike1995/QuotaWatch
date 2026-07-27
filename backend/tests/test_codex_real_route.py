"""FastAPI gate and contract tests for the Codex-only real scenario."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app import main
from app.models import ProviderQuota, QuotaWindow


client = TestClient(main.app)


class _ExplodingAggregator:
    def fetch_all(self):
        raise AssertionError("disabled route must not query Codex")


class _SuccessfulAggregator:
    def fetch_all(self) -> list[ProviderQuota]:
        return [
            ProviderQuota(
                provider="codex",
                planName="ChatGPT Pro",
                planType="pro",
                windows=[
                    QuotaWindow(
                        label="5 小时窗口",
                        used=25,
                        limit=100,
                        unit="percent",
                        resetAt=datetime(2026, 7, 23, 10, 0, tzinfo=timezone.utc),
                    )
                ],
                fetchedAt=datetime(2026, 7, 23, 6, 0, tzinfo=timezone.utc),
            )
        ]


def test_codex_real_is_disabled_by_default(monkeypatch) -> None:
    monkeypatch.setattr(main, "_CODEX_REAL_ENABLED", False)
    monkeypatch.setattr(main, "_codex_real_aggregator", _ExplodingAggregator())

    response = client.get("/api/v1/quotas", params={"scenario": "codex_real"})

    assert response.status_code == 503
    assert response.json()["detail"] == {
        "code": "codex_real_disabled",
        "message": "Codex 真实额度未启用；请先用环境开关启动本地后端",
    }


def test_codex_real_returns_actual_codex_and_marks_other_providers_unknown(monkeypatch) -> None:
    monkeypatch.setattr(main, "_CODEX_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_codex_real_aggregator", _SuccessfulAggregator())

    response = client.get("/api/v1/quotas", params={"scenario": "codex_real"})

    assert response.status_code == 200
    payload = response.json()
    assert [item["provider"] for item in payload] == ["codex", "kimi", "glm"]
    assert payload[0]["planName"] == "ChatGPT Pro"
    assert payload[0]["windows"][0]["used"] == 25
    assert payload[0]["windows"][0]["unit"] == "percent"
    assert payload[1]["status"] == payload[2]["status"] == "unknown"
    assert payload[1]["planName"] == payload[2]["planName"] == "当前场景未查询"
