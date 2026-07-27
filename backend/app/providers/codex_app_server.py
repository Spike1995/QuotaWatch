"""Codex rate-limit adapter backed by the official local app-server protocol.

The adapter never reads ``auth.json`` or accepts an OAuth token.  It starts the
locally installed ``codex app-server`` process, completes the documented JSONL
handshake, calls only ``account/rateLimits/read``, and returns the existing
Quota Watch contract.

Real execution is gated by ``QUOTA_WATCH_CODEX_REAL`` in ``app.main``.  This
module itself performs no work at import time, which keeps offline tests and the
default fake backend deterministic.
"""

from __future__ import annotations

import json
import math
import os
import queue
import shutil
import subprocess
import threading
import time
from collections.abc import Callable, Mapping, Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..models import ProviderName, ProviderQuota, QuotaCredits, QuotaWindow
from .base import (
    AuthError,
    ContractError,
    ProviderConnectionError,
    ProviderError,
    ProviderTimeoutError,
    RateLimitError,
)

_MAX_JSONL_LINE_BYTES = 1024 * 1024
_MISSING = object()
_EOF = object()


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def resolve_codex_command(environment: Mapping[str, str] | None = None) -> tuple[str, ...]:
    """Resolve one executable path without invoking a shell.

    ``QUOTA_WATCH_CODEX_COMMAND`` is intentionally restricted to an absolute
    file path.  It is not a free-form command string, so values such as
    ``codex && ...`` cannot be interpreted by a shell.
    """

    source = environment if environment is not None else os.environ
    override = source.get("QUOTA_WATCH_CODEX_COMMAND", "").strip()
    if override:
        candidate = Path(override)
        if not candidate.is_absolute() or not candidate.is_file():
            raise ProviderConnectionError()
        return (str(candidate),)

    local_app_data = source.get("LOCALAPPDATA", "").strip()
    if local_app_data:
        bundled = Path(local_app_data) / "OpenAI" / "Codex" / "bin" / "codex.exe"
        if bundled.is_file():
            return (str(bundled),)

    discovered = shutil.which("codex", path=source.get("PATH", ""))
    if discovered:
        return (discovered,)
    raise ProviderConnectionError()


class CodexAppServerClient:
    """Synchronous JSONL client with bounded reads and deterministic cleanup.

    默认 15 秒：Windows 冷启动 app-server（进程拉起 + 安全软件扫描 + 握手）
    实测可能超过 8 秒；超时仍是有界的，不会无限等待。
    """

    def __init__(
        self,
        command: Sequence[str] | None = None,
        *,
        timeout_seconds: float = 15.0,
        environment: Mapping[str, str] | None = None,
    ) -> None:
        if timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        self._command = tuple(command) if command is not None else None
        self._timeout_seconds = timeout_seconds
        self._environment = environment

    def read_rate_limits(self) -> Mapping[str, Any]:
        """Read one normalized-safe rate-limit snapshot.

        Raw stdout and JSON-RPC errors are never logged or returned.  Only the
        result object reaches the parser; stderr is discarded at process level.
        """

        command = self._command or resolve_codex_command(self._environment)
        creationflags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        try:
            process = subprocess.Popen(
                [*command, "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                shell=False,
                creationflags=creationflags,
            )
        except (FileNotFoundError, PermissionError, OSError) as error:
            raise ProviderConnectionError() from error

        responses: queue.Queue[bytes | object] = queue.Queue()
        reader = threading.Thread(
            target=self._read_stdout,
            args=(process, responses),
            name="quota-watch-codex-jsonl",
            daemon=True,
        )
        reader.start()
        try:
            self._request(
                process,
                responses,
                request_id=1,
                method="initialize",
                params={
                    "clientInfo": {
                        "name": "quota_watch_local",
                        "title": "Quota Watch Local",
                        "version": "0.1.0",
                    }
                },
            )
            self._write_message(process, {"method": "initialized"})
            return self._request(
                process,
                responses,
                request_id=2,
                method="account/rateLimits/read",
            )
        finally:
            self._close_process(process, reader)

    def _request(
        self,
        process: subprocess.Popen[bytes],
        responses: queue.Queue[bytes | object],
        *,
        request_id: int,
        method: str,
        params: object = _MISSING,
    ) -> Mapping[str, Any]:
        message: dict[str, Any] = {"id": request_id, "method": method}
        if params is not _MISSING:
            message["params"] = params
        self._write_message(process, message)

        deadline = time.monotonic() + self._timeout_seconds
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ProviderTimeoutError()
            line = self._read_line(responses, remaining)
            if line.get("id") != request_id:
                # Ignore notifications and responses for unrelated request IDs;
                # do not retain or log their payloads.
                continue
            if "error" in line:
                raise _map_rpc_error(line.get("error"))
            result = line.get("result")
            if not isinstance(result, Mapping):
                raise ContractError()
            return result

    def _read_line(
        self,
        responses: queue.Queue[bytes | object],
        timeout_seconds: float,
    ) -> Mapping[str, Any]:
        try:
            raw_line = responses.get(timeout=timeout_seconds)
        except queue.Empty as error:
            raise ProviderTimeoutError() from error
        if raw_line is _EOF:
            raise ProviderConnectionError()
        if not isinstance(raw_line, bytes):
            raise ContractError()
        if len(raw_line) > _MAX_JSONL_LINE_BYTES:
            raise ContractError()
        try:
            decoded = json.loads(raw_line)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ContractError() from error
        if not isinstance(decoded, Mapping):
            raise ContractError()
        return decoded

    def _write_message(
        self,
        process: subprocess.Popen[bytes],
        message: Mapping[str, Any],
    ) -> None:
        if process.stdin is None or process.poll() is not None:
            raise ProviderConnectionError()
        encoded = (json.dumps(message, separators=(",", ":")) + "\n").encode("utf-8")
        try:
            process.stdin.write(encoded)
            process.stdin.flush()
        except (BrokenPipeError, ConnectionError) as error:
            raise ProviderConnectionError() from error

    @staticmethod
    def _read_stdout(
        process: subprocess.Popen[bytes],
        responses: queue.Queue[bytes | object],
    ) -> None:
        try:
            if process.stdout is not None:
                while True:
                    raw_line = process.stdout.readline(_MAX_JSONL_LINE_BYTES + 1)
                    if not raw_line:
                        break
                    responses.put(raw_line)
        except OSError:
            pass
        finally:
            responses.put(_EOF)

    @staticmethod
    def _close_process(
        process: subprocess.Popen[bytes],
        reader: threading.Thread,
    ) -> None:
        if process.stdin is not None:
            try:
                process.stdin.close()
            except (BrokenPipeError, OSError):
                pass
        try:
            process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=0.5)
        if process.stdout is not None:
            process.stdout.close()
        reader.join(timeout=0.5)


class CodexAppServerAdapter:
    """Map one official Codex rate-limit snapshot to ``ProviderQuota``."""

    def __init__(
        self,
        client: CodexAppServerClient | None = None,
        *,
        clock: Callable[[], datetime] = _now_utc,
    ) -> None:
        self._client = client or CodexAppServerClient()
        self._clock = clock

    @property
    def provider(self) -> ProviderName:
        return "codex"

    def fetch(self) -> ProviderQuota:
        return parse_codex_rate_limits(
            self._client.read_rate_limits(),
            fetched_at=self._clock(),
        )


def parse_codex_rate_limits(
    payload: Mapping[str, Any],
    *,
    fetched_at: datetime | None = None,
) -> ProviderQuota:
    """Parse only documented rate-limit fields; discard everything else."""

    snapshot = _select_codex_snapshot(payload)
    windows: list[QuotaWindow] = []
    reached = snapshot.get("rateLimitReachedType")
    note = "Codex app-server 本机只读数据"
    if isinstance(reached, str) and reached:
        note += "；已触发额度限制"

    for position, key in enumerate(("primary", "secondary"), start=1):
        raw_window = snapshot.get(key)
        if raw_window is None:
            continue
        if not isinstance(raw_window, Mapping):
            raise ContractError()
        windows.append(_parse_window(raw_window, position=position, note=note))

    if not windows:
        raise ContractError()

    plan_type_value = snapshot.get("planType")
    plan_type = plan_type_value if isinstance(plan_type_value, str) else None
    return ProviderQuota(
        provider="codex",
        plan_name=_plan_name(plan_type),
        plan_type=plan_type,
        windows=windows,
        status="ok",
        fetched_at=fetched_at or _now_utc(),
        credits=_parse_credits(snapshot.get("credits")),
    )


def _parse_credits(raw: object) -> QuotaCredits | None:
    """Parse the optional official ``credits`` object; absence means None.

    Whitelist rules match the rest of this parser: wrong container or wrong
    field types are contract drift (``ContractError``), never silently shown.
    ``balance`` is a display-only string; cap its length so a drifting payload
    cannot push arbitrarily long text into the UI.
    """

    if raw is None:
        return None
    if not isinstance(raw, Mapping):
        raise ContractError()
    has_credits = raw.get("hasCredits")
    unlimited = raw.get("unlimited")
    if not isinstance(has_credits, bool) or not isinstance(unlimited, bool):
        raise ContractError()
    balance_raw = raw.get("balance")
    if balance_raw is not None and not isinstance(balance_raw, str):
        raise ContractError()
    balance = balance_raw.strip() if isinstance(balance_raw, str) else None
    if balance is not None and (not balance or len(balance) > 32):
        raise ContractError()
    return QuotaCredits(
        has_credits=has_credits,
        unlimited=unlimited,
        balance=balance,
    )


def _select_codex_snapshot(payload: Mapping[str, Any]) -> Mapping[str, Any]:
    buckets = payload.get("rateLimitsByLimitId")
    if isinstance(buckets, Mapping):
        direct = buckets.get("codex")
        if isinstance(direct, Mapping):
            return direct
        for candidate in buckets.values():
            if isinstance(candidate, Mapping) and candidate.get("limitId") == "codex":
                return candidate

    historical = payload.get("rateLimits")
    if not isinstance(historical, Mapping):
        raise ContractError()
    return historical


def _parse_window(
    raw: Mapping[str, Any],
    *,
    position: int,
    note: str,
) -> QuotaWindow:
    used_raw = raw.get("usedPercent")
    if isinstance(used_raw, bool) or not isinstance(used_raw, (int, float)):
        raise ContractError()
    used = float(used_raw)
    if not math.isfinite(used):
        raise ContractError()
    used = min(max(used, 0.0), 100.0)

    duration_raw = raw.get("windowDurationMins")
    duration: int | None = None
    if duration_raw is not None:
        if isinstance(duration_raw, bool) or not isinstance(duration_raw, (int, float)):
            raise ContractError()
        duration = int(duration_raw)
        if duration <= 0:
            raise ContractError()

    reset_at = _parse_reset_at(raw.get("resetsAt"))
    return QuotaWindow(
        label=_window_label(duration, position),
        used=used,
        limit=100.0,
        unit="percent",
        reset_at=reset_at,
        note=note,
    )


def _parse_reset_at(value: object) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ContractError()
    try:
        return datetime.fromtimestamp(int(value), tz=timezone.utc)
    except (OverflowError, OSError, ValueError) as error:
        raise ContractError() from error


def _window_label(duration_minutes: int | None, position: int) -> str:
    if duration_minutes is None:
        return "主额度窗口" if position == 1 else "次额度窗口"
    if duration_minutes % (24 * 60) == 0:
        return f"{duration_minutes // (24 * 60)} 天窗口"
    if duration_minutes % 60 == 0:
        return f"{duration_minutes // 60} 小时窗口"
    return f"{duration_minutes} 分钟窗口"


def _plan_name(plan_type: str | None) -> str:
    names = {
        "free": "ChatGPT Free",
        "go": "ChatGPT Go",
        "plus": "ChatGPT Plus",
        "pro": "ChatGPT Pro",
        "prolite": "ChatGPT Pro Lite",
        "team": "ChatGPT Team",
        "business": "ChatGPT Business",
        "self_serve_business_usage_based": "ChatGPT Business",
        "enterprise": "ChatGPT Enterprise",
        "enterprise_cbp_usage_based": "ChatGPT Enterprise",
        "edu": "ChatGPT Edu",
    }
    return names.get(plan_type, "ChatGPT Codex")


def _map_rpc_error(error_payload: object) -> ProviderError:
    # Inspect only for classification; never expose this text to callers/logs.
    try:
        text = json.dumps(error_payload, ensure_ascii=False).lower()
    except (TypeError, ValueError):
        text = ""
    if any(
        marker in text
        for marker in (
            "not logged in",
            "authentication",
            "unauthorized",
            "openai auth",
            "login required",
        )
    ):
        return AuthError()
    if "429" in text or "rate limit" in text:
        return RateLimitError()
    if "not initialized" in text or "method not found" in text:
        return ContractError()
    return ProviderConnectionError()
