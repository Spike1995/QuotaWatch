"""Global test isolation for local credential state.

The production module constructs a Windows Credential Manager wrapper, but
tests must never read or modify the user's real vault.  Every test receives a
fresh in-memory store and temporary non-secret metadata file.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from app import main
from app.credential_profiles import CredentialProfileManager, MemorySecretStore


@pytest.fixture(autouse=True)
def isolated_credential_profiles(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> CredentialProfileManager:
    manager = CredentialProfileManager(
        secret_store=MemorySecretStore(),
        metadata_path=tmp_path / "credential_profiles.json",
        environment={},
    )
    monkeypatch.setattr(main, "_credential_profiles", manager)
    return manager
