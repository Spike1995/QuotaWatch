"""Offline tests for loopback-only, OS-backed credential profiles."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from fastapi.testclient import TestClient

from app import main
from app.credential_profiles import CredentialProfileManager, MemorySecretStore
from app.models import ProviderQuota, QuotaWindow
from app.providers.kimi_adapter import KIMI_API_KEY_ENV


LOCAL_CLIENT = TestClient(
    main.app,
    client=("127.0.0.1", 51000),
)
REMOTE_CLIENT = TestClient(
    main.app,
    client=("192.0.2.10", 51000),
)
FAKE_KEY = "fixture-key-for-offline-tests"


class _SuccessfulKimiAggregator:
    def fetch_all(self) -> list[ProviderQuota]:
        return [
            ProviderQuota(
                provider="kimi",
                planName="Kimi Code",
                windows=[
                    QuotaWindow(
                        label="5 小时额度",
                        used=25,
                        limit=100,
                        unit="percent",
                    )
                ],
            )
        ]


class _SuccessfulCodexAggregator:
    def fetch_all(self) -> list[ProviderQuota]:
        return [
            ProviderQuota(
                provider="codex",
                planName="ChatGPT Plus",
                windows=[
                    QuotaWindow(
                        label="5 小时额度",
                        used=10,
                        limit=100,
                        unit="percent",
                    )
                ],
            )
        ]


class _StableCodexAggregator:
    """Return the same object to model an aggregator-owned cache entry."""

    def __init__(self) -> None:
        self.quota = ProviderQuota(
            provider="codex",
            planName="ChatGPT Plus",
            windows=[
                QuotaWindow(
                    label="5 小时额度",
                    used=10,
                    limit=100,
                    unit="percent",
                )
            ],
        )

    def fetch_all(self) -> list[ProviderQuota]:
        return [self.quota]


def test_profile_round_trip_never_serializes_or_returns_secret(
    isolated_credential_profiles: CredentialProfileManager,
    tmp_path: Path,
) -> None:
    response = LOCAL_CLIENT.put(
        "/api/v1/credential-profiles/kimi",
        json={"label": "我的 Kimi", "apiKey": FAKE_KEY},
    )

    assert response.status_code == 200
    assert response.json() == {
        "provider": "kimi",
        "label": "我的 Kimi",
        "configured": True,
        "source": "windows_credential_manager",
        "resetCount": None,
        "resetExpiresAt": None,
        "resetSource": None,
    }
    assert FAKE_KEY not in response.text

    profiles_response = LOCAL_CLIENT.get("/api/v1/credential-profiles")
    assert profiles_response.status_code == 200
    assert FAKE_KEY not in profiles_response.text
    assert "apiKey" not in profiles_response.text

    metadata_path = tmp_path / "credential_profiles.json"
    metadata_text = metadata_path.read_text(encoding="utf-8")
    assert FAKE_KEY not in metadata_text
    assert json.loads(metadata_text)["profiles"]["kimi"] == {
        "label": "我的 Kimi",
    }
    assert (
        isolated_credential_profiles.resolve_api_key(
            "kimi",
            KIMI_API_KEY_ENV,
        )
        == FAKE_KEY
    )


def test_saved_key_enables_provider_without_backend_restart(
    monkeypatch,
) -> None:
    monkeypatch.setattr(main, "_KIMI_REAL_ENABLED", False)
    monkeypatch.setattr(main, "_kimi_real_aggregator", _SuccessfulKimiAggregator())

    before = LOCAL_CLIENT.get(
        "/api/v1/quotas",
        params={"scenario": "kimi_real"},
    )
    assert before.status_code == 503

    saved = LOCAL_CLIENT.put(
        "/api/v1/credential-profiles/kimi",
        json={"label": "Kimi Code", "apiKey": FAKE_KEY},
    )
    assert saved.status_code == 200

    after = LOCAL_CLIENT.get(
        "/api/v1/quotas",
        params={"scenario": "kimi_real"},
    )
    assert after.status_code == 200
    assert after.json()[1]["provider"] == "kimi"


def test_environment_key_has_precedence_over_vault(tmp_path: Path) -> None:
    manager = CredentialProfileManager(
        secret_store=MemorySecretStore(),
        metadata_path=tmp_path / "metadata.json",
        environment={KIMI_API_KEY_ENV: "environment-fixture-key"},
    )
    manager.save_api_key(
        "kimi",
        label="Kimi Code",
        api_key="vault-fixture-key",
    )

    assert (
        manager.resolve_api_key("kimi", KIMI_API_KEY_ENV)
        == "environment-fixture-key"
    )
    assert manager.summary("kimi", env_name=KIMI_API_KEY_ENV).source == "environment"


def test_remote_profile_mutation_is_rejected() -> None:
    response = REMOTE_CLIENT.put(
        "/api/v1/credential-profiles/glm",
        json={"label": "GLM", "apiKey": FAKE_KEY},
    )

    assert response.status_code == 403
    assert response.json()["detail"]["code"] == "loopback_only"
    assert FAKE_KEY not in response.text


def test_invalid_key_is_rejected_without_echo() -> None:
    response = LOCAL_CLIENT.put(
        "/api/v1/credential-profiles/glm",
        json={"label": "GLM", "apiKey": "line-one\nline-two"},
    )

    assert response.status_code == 422
    assert response.json()["detail"]["message"] == "配置内容格式不正确"
    assert "line-one" not in response.text

    oversized = "oversized-fixture-" * 200
    oversized_response = LOCAL_CLIENT.put(
        "/api/v1/credential-profiles/glm",
        json={"label": "GLM", "apiKey": oversized},
    )
    assert oversized_response.status_code == 422
    assert oversized not in oversized_response.text


def test_malformed_secret_payload_uses_sanitized_validation_error() -> None:
    marker = "must-not-echo-fixture-secret"
    response = LOCAL_CLIENT.put(
        "/api/v1/credential-profiles/kimi",
        content=f'{{"label":"Kimi","apiKey":"{marker}"',
        headers={"content-type": "application/json"},
    )

    assert response.status_code == 422
    assert response.json()["detail"]["code"] == "invalid_credential_profile"
    assert marker not in response.text


def test_codex_rejects_token_but_accepts_manual_reset_note(
    monkeypatch,
) -> None:
    rejected = LOCAL_CLIENT.put(
        "/api/v1/credential-profiles/codex",
        json={"label": "本机账号", "apiKey": FAKE_KEY},
    )
    assert rejected.status_code == 422
    assert FAKE_KEY not in rejected.text

    expires_at = datetime(2026, 12, 31, 15, 59, tzinfo=timezone.utc)
    saved = LOCAL_CLIENT.put(
        "/api/v1/credential-profiles/codex",
        json={
            "label": "本机 ChatGPT 账号",
            "resetCount": 3,
            "resetExpiresAt": expires_at.isoformat(),
        },
    )
    assert saved.status_code == 200
    assert saved.json()["resetSource"] == "manual"

    monkeypatch.setattr(main, "_CODEX_REAL_ENABLED", True)
    monkeypatch.setattr(
        main,
        "_codex_real_aggregator",
        _SuccessfulCodexAggregator(),
    )
    quotas = LOCAL_CLIENT.get(
        "/api/v1/quotas",
        params={"scenario": "codex_real"},
    )
    assert quotas.status_code == 200
    allowance = quotas.json()[0]["resetAllowance"]
    assert allowance == {
        "count": 3,
        "expiresAt": expires_at.isoformat().replace("+00:00", "Z"),
        "source": "manual",
    }


def test_manual_reset_note_never_mutates_provider_cache(
    monkeypatch,
) -> None:
    aggregator = _StableCodexAggregator()
    monkeypatch.setattr(main, "_CODEX_REAL_ENABLED", True)
    monkeypatch.setattr(main, "_codex_real_aggregator", aggregator)
    expires_at = datetime(2026, 12, 31, 15, 59, tzinfo=timezone.utc)
    saved = LOCAL_CLIENT.put(
        "/api/v1/credential-profiles/codex",
        json={
            "label": "本机 ChatGPT 账号",
            "resetCount": 2,
            "resetExpiresAt": expires_at.isoformat(),
        },
    )
    assert saved.status_code == 200

    with_note = LOCAL_CLIENT.get(
        "/api/v1/quotas",
        params={"scenario": "codex_real"},
    )
    assert with_note.status_code == 200
    assert with_note.json()[0]["resetAllowance"]["count"] == 2
    assert aggregator.quota.reset_allowance is None

    cleared = LOCAL_CLIENT.delete("/api/v1/credential-profiles/codex")
    assert cleared.status_code == 200
    without_note = LOCAL_CLIENT.get(
        "/api/v1/quotas",
        params={"scenario": "codex_real"},
    )
    assert without_note.status_code == 200
    assert without_note.json()[0]["resetAllowance"] is None


def test_delete_removes_vault_value_and_non_secret_metadata(
    isolated_credential_profiles: CredentialProfileManager,
) -> None:
    LOCAL_CLIENT.put(
        "/api/v1/credential-profiles/glm",
        json={"label": "GLM", "apiKey": FAKE_KEY},
    )

    deleted = LOCAL_CLIENT.delete("/api/v1/credential-profiles/glm")

    assert deleted.status_code == 200
    assert deleted.json()["configured"] is False
    assert (
        isolated_credential_profiles.resolve_api_key(
            "glm",
            "QUOTA_WATCH_GLM_API_KEY",
        )
        is None
    )
