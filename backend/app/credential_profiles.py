"""Local credential profiles backed by the operating-system secret store.

Only Kimi and GLM API keys are accepted.  Secret values are never serialized
to the metadata file and never returned by this module.  The JSON file contains
only non-secret labels plus the optional, explicitly manual Codex reset note.
"""

from __future__ import annotations

import ctypes
import json
import os
import threading
from ctypes import wintypes
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Literal, Protocol

from .models import ProviderName

CredentialSource = Literal[
    "environment",
    "windows_credential_manager",
    "codex_local_login",
    "not_configured",
]

KEY_PROVIDERS = ("kimi", "glm")
MAX_SECRET_BYTES = 2048
_METADATA_VERSION = 1
_TARGETS = {
    "kimi": "QuotaWatch/Kimi",
    "glm": "QuotaWatch/GLM",
}


class SecretStoreError(RuntimeError):
    """Base error for safe, normalized secret-store failures."""


class SecretStoreUnavailableError(SecretStoreError):
    """The current OS does not provide the configured secret store."""


class SecretStore(Protocol):
    def read(self, target: str) -> str | None: ...

    def write(self, target: str, secret: str) -> None: ...

    def delete(self, target: str) -> None: ...


class MemorySecretStore:
    """Deterministic test double; production never selects this store."""

    def __init__(self) -> None:
        self._values: dict[str, str] = {}

    def read(self, target: str) -> str | None:
        return self._values.get(target)

    def write(self, target: str, secret: str) -> None:
        self._values[target] = secret

    def delete(self, target: str) -> None:
        self._values.pop(target, None)


class UnavailableSecretStore:
    def read(self, target: str) -> str | None:
        del target
        return None

    def write(self, target: str, secret: str) -> None:
        del target, secret
        raise SecretStoreUnavailableError("OS credential store is unavailable")

    def delete(self, target: str) -> None:
        del target
        raise SecretStoreUnavailableError("OS credential store is unavailable")


class _CredentialAttributeW(ctypes.Structure):
    _fields_ = [
        ("Keyword", wintypes.LPWSTR),
        ("Flags", wintypes.DWORD),
        ("ValueSize", wintypes.DWORD),
        ("Value", ctypes.POINTER(wintypes.BYTE)),
    ]


class _CredentialW(ctypes.Structure):
    _fields_ = [
        ("Flags", wintypes.DWORD),
        ("Type", wintypes.DWORD),
        ("TargetName", wintypes.LPWSTR),
        ("Comment", wintypes.LPWSTR),
        ("LastWritten", wintypes.FILETIME),
        ("CredentialBlobSize", wintypes.DWORD),
        ("CredentialBlob", ctypes.POINTER(wintypes.BYTE)),
        ("Persist", wintypes.DWORD),
        ("AttributeCount", wintypes.DWORD),
        ("Attributes", ctypes.POINTER(_CredentialAttributeW)),
        ("TargetAlias", wintypes.LPWSTR),
        ("UserName", wintypes.LPWSTR),
    ]


_CredentialPointer = ctypes.POINTER(_CredentialW)


class WindowsCredentialStore:
    """Minimal WinCred wrapper for generic, local-machine-persisted secrets."""

    _CRED_TYPE_GENERIC = 1
    _CRED_PERSIST_LOCAL_MACHINE = 2
    _ERROR_NOT_FOUND = 1168

    def __init__(self) -> None:
        if os.name != "nt":
            raise SecretStoreUnavailableError(
                "Windows Credential Manager is unavailable",
            )
        self._advapi32 = ctypes.WinDLL(
            "Advapi32.dll",
            use_last_error=True,
        )
        self._advapi32.CredReadW.argtypes = [
            wintypes.LPCWSTR,
            wintypes.DWORD,
            wintypes.DWORD,
            ctypes.POINTER(_CredentialPointer),
        ]
        self._advapi32.CredReadW.restype = wintypes.BOOL
        self._advapi32.CredWriteW.argtypes = [
            ctypes.POINTER(_CredentialW),
            wintypes.DWORD,
        ]
        self._advapi32.CredWriteW.restype = wintypes.BOOL
        self._advapi32.CredDeleteW.argtypes = [
            wintypes.LPCWSTR,
            wintypes.DWORD,
            wintypes.DWORD,
        ]
        self._advapi32.CredDeleteW.restype = wintypes.BOOL
        self._advapi32.CredFree.argtypes = [ctypes.c_void_p]
        self._advapi32.CredFree.restype = None

    def read(self, target: str) -> str | None:
        credential_pointer = _CredentialPointer()
        ok = self._advapi32.CredReadW(
            target,
            self._CRED_TYPE_GENERIC,
            0,
            ctypes.byref(credential_pointer),
        )
        if not ok:
            error_code = ctypes.get_last_error()
            if error_code == self._ERROR_NOT_FOUND:
                return None
            raise SecretStoreError(f"CredReadW failed with code {error_code}")
        try:
            credential = credential_pointer.contents
            blob = ctypes.string_at(
                credential.CredentialBlob,
                credential.CredentialBlobSize,
            )
            try:
                return blob.decode("utf-8")
            except UnicodeDecodeError as error:
                raise SecretStoreError("stored credential is not valid UTF-8") from error
        finally:
            self._advapi32.CredFree(credential_pointer)

    def write(self, target: str, secret: str) -> None:
        payload = secret.encode("utf-8")
        blob = (wintypes.BYTE * len(payload)).from_buffer_copy(payload)
        credential = _CredentialW()
        credential.Type = self._CRED_TYPE_GENERIC
        credential.TargetName = target
        credential.CredentialBlobSize = len(payload)
        credential.CredentialBlob = ctypes.cast(
            blob,
            ctypes.POINTER(wintypes.BYTE),
        )
        credential.Persist = self._CRED_PERSIST_LOCAL_MACHINE
        credential.UserName = "Quota Watch"
        if not self._advapi32.CredWriteW(ctypes.byref(credential), 0):
            error_code = ctypes.get_last_error()
            raise SecretStoreError(f"CredWriteW failed with code {error_code}")

    def delete(self, target: str) -> None:
        if self._advapi32.CredDeleteW(target, self._CRED_TYPE_GENERIC, 0):
            return
        error_code = ctypes.get_last_error()
        if error_code != self._ERROR_NOT_FOUND:
            raise SecretStoreError(f"CredDeleteW failed with code {error_code}")


@dataclass(frozen=True)
class ProfileMetadata:
    label: str
    reset_count: int | None = None
    reset_expires_at: datetime | None = None


@dataclass(frozen=True)
class ProfileSummary:
    provider: ProviderName
    label: str
    configured: bool
    source: CredentialSource
    reset_count: int | None = None
    reset_expires_at: datetime | None = None


class CredentialProfileManager:
    """Resolve env-or-vault keys and atomically store non-secret metadata."""

    def __init__(
        self,
        *,
        secret_store: SecretStore | None = None,
        metadata_path: Path | None = None,
        environment: dict[str, str] | os._Environ[str] | None = None,
    ) -> None:
        self._secret_store = secret_store or _default_secret_store()
        self._metadata_path = metadata_path or _default_metadata_path()
        self._environment = environment if environment is not None else os.environ
        self._lock = threading.RLock()

    def resolve_api_key(self, provider: ProviderName, env_name: str) -> str | None:
        if provider not in KEY_PROVIDERS:
            return None
        environment_value = self._environment.get(env_name, "").strip()
        if _is_valid_runtime_secret(environment_value):
            return environment_value
        stored = self._secret_store.read(_TARGETS[provider])
        if stored is None:
            return None
        stored = stored.strip()
        return stored if _is_valid_runtime_secret(stored) else None

    def has_api_key(self, provider: ProviderName, env_name: str) -> bool:
        return self.resolve_api_key(provider, env_name) is not None

    def save_api_key(
        self,
        provider: ProviderName,
        *,
        label: str,
        api_key: str,
    ) -> ProfileMetadata:
        if provider not in KEY_PROVIDERS:
            raise ValueError("only Kimi and GLM accept API keys")
        safe_label = _validate_label(label)
        safe_key = _validate_persisted_secret(api_key)
        target = _TARGETS[provider]
        with self._lock:
            previous_secret = self._secret_store.read(target)
            metadata = self._read_metadata()
            previous_metadata = metadata.get(provider)
            self._secret_store.write(target, safe_key)
            metadata[provider] = ProfileMetadata(label=safe_label)
            try:
                self._write_metadata(metadata)
            except Exception:
                if previous_secret is None:
                    self._secret_store.delete(target)
                else:
                    self._secret_store.write(target, previous_secret)
                if previous_metadata is not None:
                    metadata[provider] = previous_metadata
                raise
            return metadata[provider]

    def save_codex_metadata(
        self,
        *,
        label: str,
        reset_count: int | None,
        reset_expires_at: datetime | None,
    ) -> ProfileMetadata:
        safe_label = _validate_label(label)
        if reset_count is not None and not 0 <= reset_count <= 1_000_000:
            raise ValueError("reset count is outside the supported range")
        with self._lock:
            metadata = self._read_metadata()
            metadata["codex"] = ProfileMetadata(
                label=safe_label,
                reset_count=reset_count,
                reset_expires_at=reset_expires_at,
            )
            self._write_metadata(metadata)
            return metadata["codex"]

    def delete(self, provider: ProviderName) -> None:
        with self._lock:
            metadata = self._read_metadata()
            previous_metadata = metadata.pop(provider, None)
            if provider in KEY_PROVIDERS:
                target = _TARGETS[provider]
                previous_secret = self._secret_store.read(target)
                self._secret_store.delete(target)
            else:
                previous_secret = None
            try:
                self._write_metadata(metadata)
            except Exception:
                if provider in KEY_PROVIDERS and previous_secret is not None:
                    self._secret_store.write(_TARGETS[provider], previous_secret)
                if previous_metadata is not None:
                    metadata[provider] = previous_metadata
                raise

    def metadata_for(self, provider: ProviderName) -> ProfileMetadata:
        with self._lock:
            metadata = self._read_metadata().get(provider)
        return metadata or ProfileMetadata(label=_default_label(provider))

    def summary(
        self,
        provider: ProviderName,
        *,
        env_name: str | None = None,
        codex_enabled: bool = False,
    ) -> ProfileSummary:
        metadata = self.metadata_for(provider)
        if provider == "codex":
            return ProfileSummary(
                provider=provider,
                label=metadata.label,
                configured=codex_enabled,
                source="codex_local_login"
                if codex_enabled
                else "not_configured",
                reset_count=metadata.reset_count,
                reset_expires_at=metadata.reset_expires_at,
            )
        assert env_name is not None
        environment_value = self._environment.get(env_name, "").strip()
        if _is_valid_runtime_secret(environment_value):
            source: CredentialSource = "environment"
            configured = True
        else:
            configured = self._secret_store.read(_TARGETS[provider]) is not None
            source = (
                "windows_credential_manager"
                if configured
                else "not_configured"
            )
        return ProfileSummary(
            provider=provider,
            label=metadata.label,
            configured=configured,
            source=source,
        )

    def _read_metadata(self) -> dict[ProviderName, ProfileMetadata]:
        try:
            raw = json.loads(self._metadata_path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            return {}
        if not isinstance(raw, dict) or raw.get("version") != _METADATA_VERSION:
            return {}
        profiles = raw.get("profiles")
        if not isinstance(profiles, dict):
            return {}

        result: dict[ProviderName, ProfileMetadata] = {}
        for provider in ("codex", "kimi", "glm"):
            item = profiles.get(provider)
            if not isinstance(item, dict):
                continue
            label = item.get("label")
            if not isinstance(label, str):
                continue
            reset_count = item.get("resetCount")
            if reset_count is not None and (
                not isinstance(reset_count, int) or isinstance(reset_count, bool)
            ):
                reset_count = None
            raw_expires_at = item.get("resetExpiresAt")
            try:
                reset_expires_at = (
                    datetime.fromisoformat(raw_expires_at)
                    if isinstance(raw_expires_at, str)
                    else None
                )
            except ValueError:
                reset_expires_at = None
            result[provider] = ProfileMetadata(
                label=label,
                reset_count=reset_count,
                reset_expires_at=reset_expires_at,
            )
        return result

    def _write_metadata(
        self,
        metadata: dict[ProviderName, ProfileMetadata],
    ) -> None:
        self._metadata_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "version": _METADATA_VERSION,
            "profiles": {
                provider: {
                    "label": profile.label,
                    **(
                        {"resetCount": profile.reset_count}
                        if profile.reset_count is not None
                        else {}
                    ),
                    **(
                        {"resetExpiresAt": profile.reset_expires_at.isoformat()}
                        if profile.reset_expires_at is not None
                        else {}
                    ),
                }
                for provider, profile in metadata.items()
            },
        }
        temporary_path = self._metadata_path.with_name(
            f".{self._metadata_path.name}.{os.getpid()}.tmp",
        )
        with temporary_path.open("w", encoding="utf-8", newline="\n") as stream:
            json.dump(payload, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, self._metadata_path)


def _default_secret_store() -> SecretStore:
    if os.name == "nt":
        return WindowsCredentialStore()
    return UnavailableSecretStore()


def _default_metadata_path() -> Path:
    local_app_data = os.getenv("LOCALAPPDATA")
    if local_app_data:
        return Path(local_app_data) / "QuotaWatch" / "credential_profiles.json"
    return Path.home() / ".quota_watch" / "credential_profiles.json"


def _default_label(provider: ProviderName) -> str:
    return {
        "codex": "本机 Codex 登录",
        "kimi": "Kimi Code",
        "glm": "GLM Coding Plan",
    }[provider]


def _validate_label(value: str) -> str:
    label = value.strip()
    if not label or len(label) > 80 or "\r" in label or "\n" in label:
        raise ValueError("profile label is invalid")
    return label


def _validate_persisted_secret(value: str) -> str:
    secret = value.strip()
    if (
        not secret
        or "\r" in secret
        or "\n" in secret
        or len(secret.encode("utf-8")) > MAX_SECRET_BYTES
    ):
        raise ValueError("API key is invalid")
    return secret


def _is_valid_runtime_secret(value: str) -> bool:
    return bool(value) and len(value) <= 8192 and "\r" not in value and "\n" not in value
