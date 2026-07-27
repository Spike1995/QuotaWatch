"""FastAPI entrypoint for Quota Watch's local-only learning backend."""

import ipaddress
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Literal

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.exception_handlers import request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

from .credential_profiles import (
    CredentialProfileManager,
    SecretStoreError,
    SecretStoreUnavailableError,
)
from .models import (
    CredentialProfileSummary,
    CredentialProfileUpdate,
    HealthResponse,
    ProviderName,
    ProviderQuota,
    ResetAllowance,
)
from .providers.aggregator import QuotaAggregator
from .providers.codex_app_server import CodexAppServerAdapter
from .providers.glm_adapter import (
    GLM_API_KEY_ENV,
    GlmProviderAdapter,
    GlmUsageClient,
)
from .providers.kimi_adapter import (
    KIMI_API_KEY_ENV,
    KimiProviderAdapter,
    KimiUsageClient,
)

# 阶段 9（假数据移除）：删除了 scenarios.py 的离线假场景与 experimental
# 聚合演示路由。后端现在只提供真实额度查询（Codex/Kimi/GLM 各自开关 +
# all_real 综合查询）。

app = FastAPI(
    title="Quota Watch Local Backend",
    version="0.6.0",
    description=(
        "Local Codex, Kimi, and GLM quota adapters plus loopback-only "
        "OS-backed credential profiles."
    ),
)

# Flutter Web runs on a changing localhost port during development.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=False,
    allow_methods=["GET", "PUT", "DELETE"],
    allow_headers=["*"],
)


@app.exception_handler(RequestValidationError)
async def safe_request_validation_error(
    request: Request,
    error: RequestValidationError,
) -> Response:
    if request.url.path.startswith("/api/v1/credential-profiles"):
        # FastAPI's default 422 payload can include the rejected input.  This
        # endpoint may carry a secret, so return only a normalized message.
        return JSONResponse(
            status_code=422,
            content={
                "detail": {
                    "code": "invalid_credential_profile",
                    "message": "配置内容格式不正确",
                }
            },
        )
    return await request_validation_exception_handler(request, error)


_credential_profiles = CredentialProfileManager()

# Codex 真实额度默认关闭。构造 Adapter 不会启动进程；只有 codex_real 请求且开关为 1 时才读取。
_CODEX_REAL_ENABLED = os.getenv("QUOTA_WATCH_CODEX_REAL") == "1"
_codex_real_aggregator = QuotaAggregator([CodexAppServerAdapter()])

# Kimi 真实额度可由环境变量或设置页写入的 Windows 凭据启用。
_KIMI_REAL_ENABLED = os.getenv("QUOTA_WATCH_KIMI_REAL") == "1"
_kimi_real_aggregator = QuotaAggregator(
    [
        KimiProviderAdapter(
            KimiUsageClient(
                api_key_resolver=lambda: _credential_profiles.resolve_api_key(
                    "kimi",
                    KIMI_API_KEY_ENV,
                ),
            ),
        )
    ]
)

# GLM 真实额度同理；仍不读取 ZCode 或开发 worker 的任何配置。
_GLM_REAL_ENABLED = os.getenv("QUOTA_WATCH_GLM_REAL") == "1"
_glm_real_aggregator = QuotaAggregator(
    [
        GlmProviderAdapter(
            GlmUsageClient(
                api_key_resolver=lambda: _credential_profiles.resolve_api_key(
                    "glm",
                    GLM_API_KEY_ENV,
                ),
            ),
        )
    ]
)


def _not_queried(provider: ProviderName) -> ProviderQuota:
    """Explain that a provider is available through a different real-data scene."""

    return ProviderQuota(
        provider=provider,
        plan_name="当前场景未查询",
        status="unknown",
        windows=[],
    )


def _real_not_enabled(provider: ProviderName) -> ProviderQuota:
    """Represent a provider whose individual real-data gate is still off."""

    return ProviderQuota(
        provider=provider,
        plan_name="真实查询未启用",
        status="unknown",
        windows=[],
    )


def _combined_query_failed(provider: ProviderName) -> ProviderQuota:
    """Normalize an unexpected local orchestration failure without raw details."""

    return ProviderQuota(
        provider=provider,
        plan_name="未知套餐",
        status="error",
        error_message="本地综合查询失败",
        windows=[],
    )


def _get_codex_real_quotas() -> list[ProviderQuota]:
    codex_results = _codex_real_aggregator.fetch_all()
    return [codex_results[0], _not_queried("kimi"), _not_queried("glm")]


def _get_kimi_real_quotas() -> list[ProviderQuota]:
    kimi_results = _kimi_real_aggregator.fetch_all()
    return [_not_queried("codex"), kimi_results[0], _not_queried("glm")]


def _get_glm_real_quotas() -> list[ProviderQuota]:
    glm_results = _glm_real_aggregator.fetch_all()
    return [_not_queried("codex"), _not_queried("kimi"), glm_results[0]]


def _get_all_real_quotas() -> list[ProviderQuota]:
    """Query every explicitly enabled provider concurrently and keep stable order."""

    sources: list[tuple[ProviderName, bool, QuotaAggregator]] = [
        ("codex", _CODEX_REAL_ENABLED, _codex_real_aggregator),
        ("kimi", _kimi_real_enabled(), _kimi_real_aggregator),
        ("glm", _glm_real_enabled(), _glm_real_aggregator),
    ]
    results: dict[ProviderName, ProviderQuota] = {
        provider: _real_not_enabled(provider)
        for provider, enabled, _ in sources
        if not enabled
    }
    enabled_sources = [
        (provider, aggregator)
        for provider, enabled, aggregator in sources
        if enabled
    ]
    if enabled_sources:
        with ThreadPoolExecutor(
            max_workers=len(enabled_sources),
            thread_name_prefix="quota-watch-real",
        ) as executor:
            future_to_provider = {
                executor.submit(aggregator.fetch_all): provider
                for provider, aggregator in enabled_sources
            }
            for future in as_completed(future_to_provider):
                provider = future_to_provider[future]
                try:
                    provider_results = future.result()
                    results[provider] = provider_results[0]
                except Exception:
                    # Never include an exception string: a provider/client
                    # could attach raw response or sensitive request details.
                    results[provider] = _combined_query_failed(provider)

    return [results[provider] for provider in ("codex", "kimi", "glm")]


def _kimi_real_enabled() -> bool:
    return _KIMI_REAL_ENABLED or _credential_profiles.has_api_key(
        "kimi",
        KIMI_API_KEY_ENV,
    )


def _glm_real_enabled() -> bool:
    return _GLM_REAL_ENABLED or _credential_profiles.has_api_key(
        "glm",
        GLM_API_KEY_ENV,
    )


def _attach_manual_reset_allowance(
    quotas: list[ProviderQuota],
) -> list[ProviderQuota]:
    """Merge only explicitly manual, non-secret Codex reset metadata."""

    metadata = _credential_profiles.metadata_for("codex")
    if metadata.reset_count is None:
        return quotas
    allowance = ResetAllowance(
        count=metadata.reset_count,
        expiresAt=metadata.reset_expires_at,
        source="manual",
    )
    # Aggregators retain their last successful ProviderQuota in memory.  Return
    # a copy instead of mutating that cached provider result, otherwise clearing
    # a manual note could leave stale reset metadata on a later error fallback.
    return [
        quota.model_copy(update={"reset_allowance": allowance})
        if quota.provider == "codex"
        else quota
        for quota in quotas
    ]


def _require_loopback(request: Request) -> None:
    client_host = request.client.host if request.client is not None else ""
    try:
        is_loopback = ipaddress.ip_address(client_host).is_loopback
    except ValueError:
        is_loopback = client_host.lower() == "localhost"
    if not is_loopback:
        raise HTTPException(
            status_code=403,
            detail={
                "code": "loopback_only",
                "message": "安全配置只允许从本机访问",
            },
        )


def _profile_summary(provider: ProviderName) -> CredentialProfileSummary:
    env_name = {
        "codex": None,
        "kimi": KIMI_API_KEY_ENV,
        "glm": GLM_API_KEY_ENV,
    }[provider]
    summary = _credential_profiles.summary(
        provider,
        env_name=env_name,
        codex_enabled=_CODEX_REAL_ENABLED,
    )
    return CredentialProfileSummary(
        provider=summary.provider,
        label=summary.label,
        configured=summary.configured,
        source=summary.source,
        resetCount=summary.reset_count,
        resetExpiresAt=summary.reset_expires_at,
        resetSource="manual" if summary.reset_count is not None else None,
    )


def _credential_store_error(status_code: int, message: str) -> HTTPException:
    return HTTPException(
        status_code=status_code,
        detail={
            "code": "credential_store_error",
            "message": message,
        },
    )


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse()


@app.get(
    "/api/v1/credential-profiles",
    response_model=list[CredentialProfileSummary],
)
def get_credential_profiles(request: Request) -> list[CredentialProfileSummary]:
    _require_loopback(request)
    try:
        return [
            _profile_summary(provider)
            for provider in ("codex", "kimi", "glm")
        ]
    except SecretStoreError:
        raise _credential_store_error(
            503,
            "Windows 凭据管理器暂时不可用",
        ) from None


@app.put(
    "/api/v1/credential-profiles/{provider}",
    response_model=CredentialProfileSummary,
)
def update_credential_profile(
    provider: ProviderName,
    payload: CredentialProfileUpdate,
    request: Request,
) -> CredentialProfileSummary:
    _require_loopback(request)
    try:
        if provider == "codex":
            if payload.apiKey is not None:
                raise HTTPException(
                    status_code=422,
                    detail={
                        "code": "codex_key_forbidden",
                        "message": "Codex 继续使用官方本机登录，不能在此粘贴登录 Token",
                    },
                )
            if (payload.resetCount is None) != (payload.resetExpiresAt is None):
                raise HTTPException(
                    status_code=422,
                    detail={
                        "code": "reset_metadata_incomplete",
                        "message": "请同时填写可重置次数和到期时间",
                    },
                )
            _credential_profiles.save_codex_metadata(
                label=payload.label,
                reset_count=payload.resetCount,
                reset_expires_at=payload.resetExpiresAt,
            )
        else:
            if payload.apiKey is None:
                raise HTTPException(
                    status_code=422,
                    detail={
                        "code": "api_key_required",
                        "message": "请输入新的 API Key",
                    },
                )
            if payload.resetCount is not None or payload.resetExpiresAt is not None:
                raise HTTPException(
                    status_code=422,
                    detail={
                        "code": "reset_metadata_not_supported",
                        "message": "手动重置次数只用于 Codex 本机备注",
                    },
                )
            _credential_profiles.save_api_key(
                provider,
                label=payload.label,
                api_key=payload.apiKey.get_secret_value(),
            )
        return _profile_summary(provider)
    except HTTPException:
        raise
    except ValueError:
        raise _credential_store_error(
            422,
            "配置内容格式不正确",
        ) from None
    except SecretStoreUnavailableError:
        raise _credential_store_error(
            503,
            "当前系统不支持 Windows 凭据管理器",
        ) from None
    except SecretStoreError:
        raise _credential_store_error(
            500,
            "保存到 Windows 凭据管理器失败",
        ) from None


@app.delete(
    "/api/v1/credential-profiles/{provider}",
    response_model=CredentialProfileSummary,
)
def delete_credential_profile(
    provider: ProviderName,
    request: Request,
) -> CredentialProfileSummary:
    _require_loopback(request)
    try:
        _credential_profiles.delete(provider)
        return _profile_summary(provider)
    except SecretStoreUnavailableError:
        raise _credential_store_error(
            503,
            "当前系统不支持 Windows 凭据管理器",
        ) from None
    except SecretStoreError:
        raise _credential_store_error(
            500,
            "删除 Windows 凭据失败",
        ) from None


@app.get("/api/v1/quotas", response_model=list[ProviderQuota])
def get_quotas(
    scenario: Literal["codex_real", "kimi_real", "glm_real", "all_real"] = Query(
        default="all_real",
        description="Real-data scenario: a single gated provider or the combined all_real query.",
    ),
) -> list[ProviderQuota]:
    if scenario == "codex_real":
        if not _CODEX_REAL_ENABLED:
            raise HTTPException(
                status_code=503,
                detail={
                    "code": "codex_real_disabled",
                    "message": "Codex 真实额度未启用；请先用环境开关启动本地后端",
                },
            )
        return _attach_manual_reset_allowance(_get_codex_real_quotas())
    if scenario == "kimi_real":
        if not _kimi_real_enabled():
            raise HTTPException(
                status_code=503,
                detail={
                    "code": "kimi_real_disabled",
                    "message": "Kimi 真实额度未启用；请先安全设置 Key 并用环境开关启动本地后端",
                },
            )
        return _attach_manual_reset_allowance(_get_kimi_real_quotas())
    if scenario == "glm_real":
        if not _glm_real_enabled():
            raise HTTPException(
                status_code=503,
                detail={
                    "code": "glm_real_disabled",
                    "message": "GLM 真实额度未启用；请先确认使用边界，再安全设置 Key 和环境开关",
                },
            )
        return _attach_manual_reset_allowance(_get_glm_real_quotas())
    # scenario == "all_real"
    return _attach_manual_reset_allowance(_get_all_real_quotas())
