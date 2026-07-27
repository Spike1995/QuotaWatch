"""Shared JSON contract exposed by the local fake backend."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, SecretStr


def _to_camel(field_name: str) -> str:
    """Convert Python snake_case field names to Flutter's camelCase JSON keys."""
    first, *rest = field_name.split("_")
    return first + "".join(part.capitalize() for part in rest)


class ContractModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=_to_camel,
        populate_by_name=True,
    )


ProviderName = Literal["codex", "kimi", "glm"]
QuotaStatus = Literal["ok", "degraded", "error", "loading", "unknown"]
CredentialSource = Literal[
    "environment",
    "windows_credential_manager",
    "codex_local_login",
    "not_configured",
]
ResetSource = Literal["provider", "manual"]


class QuotaWindow(ContractModel):
    label: str
    used: float
    limit: float
    unit: str
    reset_at: datetime | None = None
    note: str | None = None


class QuotaCredits(ContractModel):
    """恢复额度（Codex 官方 app-server credits 对象的归一化形态）。

    balance 是官方返回的字符串原值，只用于本机界面展示；
    为 None 表示官方没有给出余量文本（例如 hasCredits=False）。
    """

    has_credits: bool
    unlimited: bool
    balance: str | None = None


class ResetAllowance(ContractModel):
    """可额外重置额度的次数与有效期。

    当前 Codex app-server 契约没有这两个字段；source="manual" 表示用户只在
    本机记录的非敏感备注，不能当作 Provider 官方返回值。
    """

    count: int = Field(ge=0, le=1_000_000)
    expires_at: datetime | None = None
    source: ResetSource


class ProviderQuota(ContractModel):
    provider: ProviderName
    plan_name: str
    windows: list[QuotaWindow]
    plan_type: str | None = None
    expires_at: datetime | None = None
    status: QuotaStatus = "ok"
    error_message: str | None = None
    fetched_at: datetime | None = None
    credits: QuotaCredits | None = None
    reset_allowance: ResetAllowance | None = None


class CredentialProfileUpdate(BaseModel):
    """Loopback-only profile mutation payload.

    SecretStr prevents accidental repr/validation logging from exposing an API
    key.  The response model below intentionally has no secret-shaped field.
    """

    # FastAPI 0.116 + current Pydantic warns when it clones alias-generated
    # request fields.  Keep the wire names explicit in this one input-only
    # model; all response contracts continue to use ContractModel.
    label: str = Field(min_length=1, max_length=80)
    # Secret length/newline validation happens after SecretStr conversion in
    # CredentialProfileManager so an automatic validation error can never echo
    # the raw value.
    apiKey: SecretStr | None = None
    resetCount: int | None = Field(default=None, ge=0, le=1_000_000)
    resetExpiresAt: datetime | None = None


class CredentialProfileSummary(ContractModel):
    provider: ProviderName
    label: str
    configured: bool
    source: CredentialSource
    reset_count: int | None = None
    reset_expires_at: datetime | None = None
    reset_source: Literal["manual"] | None = None


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    service: Literal["quota-watch-local-backend"] = "quota-watch-local-backend"
