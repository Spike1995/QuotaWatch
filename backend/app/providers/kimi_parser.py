"""Offline parser for Kimi Code `/coding/v1/usages` (stage 6 / 卡 3).

把 Kimi 的 JSON 响应归一化成项目统一契约的 QuotaWindow 列表。
本模块**只解析**，不发起任何网络请求、不接触凭据。字段契约依据官方开源 CLI 源码（L2）：
`MoonshotAI/kimi-cli`（Python）与 `MoonshotAI/kimi-code`（TS），详见 docs/API_RESEARCH.md §三。

设计要点（官方解析器故意宽松，snake_case/camelCase 都接受）：
- 顶层是对象 {usage?, limits[]?, boosterWallet?}，不是数组。
- usage 行 -> 一个汇总 QuotaWindow；limits[] 每项 -> 一个窗口 QuotaWindow。
- used 主字段；缺失时 used = limit - remaining。
- reset_at 类是 ISO 字符串；reset_in/ttl/window 是秒数。
- 一行同时缺 used 与 limit 才丢弃；used>limit 钳为 limit（剩余 0）。
- 不读取 totalQuota（bug 字段）、used_amount/limit_amount/model_name（旧猜测名）。
- boosterWallet 本期不解析。
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from ..models import QuotaWindow
from . import _parsing
from .base import ContractError

# reset 时间：ISO 字符串字段（按官方优先级排列）。
_RESET_AT_KEYS = ("reset_at", "resetAt", "reset_time", "resetTime")
# reset 时间：整数秒字段（仅当没有 ISO 字段时使用）。
_RESET_IN_SECONDS_KEYS = ("reset_in", "resetIn", "ttl", "window")
# 标签字段（limits 还会查 scope，这里统一在 _label 中处理）。
_LABEL_KEYS_USAGE = ("name", "title")
_LABEL_KEYS_LIMIT = ("name", "title", "scope")


# 数字容忍转换与 ISO 解析已抽取到 _parsing，避免与 glm_parser 漂移。
_to_int = _parsing.to_int



def _parse_iso(value: Any) -> datetime | None:
    """解析 ISO8601 字符串；容忍纳秒精度（截断到微秒）。委托共享实现。"""

    return _parsing.parse_iso_to_utc(value)


def _first_present(data: dict[str, Any], keys: tuple[str, ...]) -> Any:
    for key in keys:
        if key in data:
            return data[key]
    return None


def _reset_value(data: dict[str, Any]) -> datetime | None:
    """优先取 ISO 字段；否则用秒数字段推算。"""

    iso = _first_present(data, _RESET_AT_KEYS)
    parsed = _parse_iso(iso)
    if parsed is not None:
        return parsed
    seconds = _to_int(_first_present(data, _RESET_IN_SECONDS_KEYS))
    if seconds is not None and seconds > 0:
        return datetime.now(timezone.utc).replace(microsecond=0) + timedelta(seconds=seconds)
    return None


def _label(data: dict[str, Any], item: dict[str, Any] | None, default: str, index: int) -> str:
    """官方标签派生：name -> title -> (limits 还查 scope) -> 窗口派生 -> 默认。"""

    keys = _LABEL_KEYS_LIMIT if item is not None else _LABEL_KEYS_USAGE
    # item 优先（limits 场景），再查 data（detail 或 usage 本身）。
    for source in (item, data):
        if source is None:
            continue
        for key in keys:
            val = source.get(key)
            if isinstance(val, str) and val.strip():
                return val.strip()
    # 窗口派生（仅 limits）：尝试 duration + timeUnit。
    if item is not None:
        window = item.get("window")
        if isinstance(window, dict):
            duration = _to_int(window.get("duration") or item.get("duration"))
            unit = window.get("timeUnit") or item.get("timeUnit")
            if duration is not None and isinstance(unit, str):
                return _window_label(duration, unit)
    return default if item is None else f"Limit #{index + 1}"


def _window_label(duration: int, unit: str) -> str:
    u = unit.upper()
    if "MINUTE" in u:
        hours = duration / 60
        return f"{int(hours)}h limit" if duration % 60 == 0 else f"{duration}m limit"
    if "HOUR" in u:
        return f"{duration}h limit"
    if "DAY" in u:
        return f"{duration}d limit"
    return f"{duration}s limit"


def _row_to_window(
    data: dict[str, Any],
    item: dict[str, Any] | None,
    default_label: str,
    index: int,
) -> QuotaWindow | None:
    """把一行（usage 本身，或 limits[].detail/limits[] item）归一为 QuotaWindow。

    返回 None 表示该行应丢弃（同时缺 used 与 limit）。
    """

    limit = _to_int(data.get("limit"))
    used = _to_int(data.get("used"))
    if used is None:
        remaining = _to_int(data.get("remaining"))
        if remaining is not None and limit is not None:
            used = max(limit - remaining, 0)
    # 官方：同时缺 used 与 limit 才丢弃。
    if used is None and limit is None:
        return None
    used = used or 0
    limit = limit or 0
    # used>limit 时钳制（剩余 0）。
    used = min(used, limit) if limit > 0 else used
    label = _label(data, item, default_label, index)
    reset_at = _reset_value(data)
    return QuotaWindow(
        label=label,
        used=float(used),
        limit=float(limit),
        unit="tokens",
        resetAt=reset_at,  # type: ignore[call-arg]
    )


def parse_kimi_usage(payload: Any) -> list[QuotaWindow]:
    """解析 Kimi /coding/v1/usages 响应为 QuotaWindow 列表。

    契约变化（payload 不是对象）抛 ContractError，由聚合层归一为 error。
    """

    if not isinstance(payload, dict):
        raise ContractError("Kimi 响应不是对象")
    windows: list[QuotaWindow] = []

    usage = payload.get("usage")
    if isinstance(usage, dict):
        window = _row_to_window(usage, item=None, default_label="Weekly limit", index=0)
        if window is not None:
            windows.append(window)

    limits = payload.get("limits")
    if isinstance(limits, list):
        for index, item in enumerate(limits):
            if not isinstance(item, dict):
                continue
            detail = item.get("detail")
            row = detail if isinstance(detail, dict) else item
            window = _row_to_window(row, item=item, default_label="Weekly limit", index=index)
            if window is not None:
                windows.append(window)

    return windows
