"""Offline parser for GLM Coding Plan /api/monitor/usage/quota/limit (stage 6).

把 GLM 的 JSON 响应归一化成统一契约的 QuotaWindow 列表。
本模块**只解析**，不发起任何网络请求、不接触凭据。字段契约依据官方开源插件
`zai-org/zai-coding-plugins`（L2，query-usage.mjs），详见 docs/API_RESEARCH.md §四。

重要：
- 当前真实契约（2026-07-23）：TOKENS_LIMIT 只提供 `number`、`percentage`；TIME_LIMIT 使用
  unit=5 并提供 `percentage`、`remaining`、`usageDetails`。
- 当前 TOKENS_LIMIT 与 TIME_LIMIT 的 `percentage` 都是已用比例，直接写入统一契约，不能取反。
- 历史契约仍兼容：`usage` = 上限（LIMIT）；`currentValue` = 已用（USED）。
- `unit`：3=5h、6=周、0/5=月/MCP-工具。
- `nextResetTime`：用 >1e12 启发式——数值 >1e12 视为毫秒，<=1e12 视为秒，非数字则按 ISO 解析。
- 当前 percentage 必须在 0～100；历史绝对值契约仍允许超额。
- `unit===3` 且上限缺失/0 时用默认上限 40,000,000 tokens。

合规：GLM Coding Plan 官方 FAQ 明确套餐仅限官方指定工具，真实查询默认禁用；
本解析器仅作离线契约文档/回归资产，不改变默认禁用状态。
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..models import QuotaWindow
from . import _parsing
from .base import ContractError

_UNIT_LABELS = {
    3: "5 小时窗口",
    6: "周窗口",
    0: "月度/MCP 工具窗口",
    5: "月度/MCP 工具窗口",
}
_DEFAULT_5H_TOKEN_LIMIT = 40_000_000
_MS_THRESHOLD = 1e12


# 数字容忍转换已抽取到 _parsing（与 kimi_parser 共享，避免漂移）。
_to_number = _parsing.to_number


def _parse_reset_time(value: Any) -> datetime | None:
    """官方 >1e12 启发式：数值 >1e12 视为毫秒，<=1e12 视为秒，非数字则按 ISO。"""

    if value is None:
        return None
    num = _to_number(value)
    if num is not None:
        seconds = num / 1000 if num > _MS_THRESHOLD else num
        try:
            return datetime.fromtimestamp(seconds, tz=timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None
    # 非数字字符串走共享 ISO 解析（含纳秒截断）。
    return _parsing.parse_iso_to_utc(value)


def _unit_label(unit: int | None, type_: str) -> str:
    # 当前 TIME_LIMIT 的 unit 是 5，历史样例曾使用 0。type 比 unit 更稳定。
    if type_ == "TIME_LIMIT" and unit in (None, 0, 5):
        return "月度/MCP 工具窗口"
    if unit is None:
        return type_
    return _UNIT_LABELS.get(unit, f"unit {unit} 窗口")


def parse_glm_usage(payload: Any) -> list[QuotaWindow]:
    """解析 GLM quota/limit 响应为 QuotaWindow 列表。

    契约变化（非对象、无 limits）抛 ContractError。
    同时处理 TOKENS_LIMIT 与 TIME_LIMIT。当前百分比契约归一为 percent；历史绝对值契约保留
    tokens/calls 单位。
    """

    if not isinstance(payload, dict):
        raise ContractError("GLM 响应不是对象")
    limits = _extract_limits(payload)
    windows: list[QuotaWindow] = []
    for item in limits:
        if not isinstance(item, dict):
            continue
        window = _item_to_window(item)
        if window is not None:
            windows.append(window)
    return windows


def _extract_limits(payload: dict[str, Any]) -> list[Any]:
    """官方容忍 data.limits 或顶层 limits 两种包络。"""

    data = payload.get("data")
    if isinstance(data, dict):
        limits = data.get("limits")
        if isinstance(limits, list):
            return limits
    limits = payload.get("limits")
    return limits if isinstance(limits, list) else []


def _item_to_window(item: dict[str, Any]) -> QuotaWindow | None:
    type_ = item.get("type")
    if not isinstance(type_, str):
        return None
    unit = _to_number(item.get("unit"))
    unit_int = int(unit) if unit is not None else None

    if _uses_percentage_contract(item, type_, unit_int):
        return _percentage_window(item, type_, unit_int)

    # 历史契约：usage = 上限；currentValue = 已用（字段名具误导性）。
    limit = _to_number(item.get("usage"))
    used = _to_number(item.get("currentValue"))
    if limit is None or limit <= 0:
        # 历史 unit===3 且 currentValue 存在时才使用旧插件的默认上限。当前百分比契约不能
        # 套用 40M，否则会把真实比例错误显示为 0/40M。
        if unit_int == 3 and used is not None:
            limit = float(_DEFAULT_5H_TOKEN_LIMIT)
        else:
            return None
    used = used or 0.0
    # 不钳制 used（GLM 允许超额，percentage 可 >100）；但用于展示时 used>limit 也如实保留。

    reset_at = _parse_reset_time(item.get("nextResetTime"))
    label = _unit_label(unit_int, type_)
    unit_str = "tokens" if type_ == "TOKENS_LIMIT" else "calls"
    note = None
    # 把服务端算好的 percentage（若存在且 >100）写进 note，供前端提示“超额”。
    percentage = _to_number(item.get("percentage"))
    if percentage is not None and percentage > 100:
        note = f"已超额（{percentage:.0f}%）"

    return QuotaWindow(
        label=label,
        used=used,
        limit=limit,
        unit=unit_str,
        resetAt=reset_at,  # type: ignore[call-arg]
        note=note,
    )


def _uses_percentage_contract(
    item: dict[str, Any],
    type_: str,
    unit: int | None,
) -> bool:
    """按字段形状识别当前契约，不依赖任何账号的实际数值。"""

    if _to_number(item.get("percentage")) is None:
        return False
    if type_ == "TOKENS_LIMIT":
        return (
            "number" in item
            or (
                _to_number(item.get("usage")) is None
                and _to_number(item.get("currentValue")) is None
            )
        )
    if type_ == "TIME_LIMIT":
        return (
            unit == 5
            or "remaining" in item
            or isinstance(item.get("usageDetails"), list)
        )
    return False


def _percentage_window(
    item: dict[str, Any],
    type_: str,
    unit: int | None,
) -> QuotaWindow:
    """按 Provider item 类型把当前 percentage 归一为已用比例。"""

    percentage = _to_number(item.get("percentage"))
    if percentage is None or percentage < 0 or percentage > 100:
        # 宁可明确报契约变化，也不钳制成一个看似正常但错误的额度。
        raise ContractError()

    return QuotaWindow(
        label=_unit_label(unit, type_),
        used=percentage,
        limit=100.0,
        unit="percent",
        resetAt=_parse_reset_time(item.get("nextResetTime")),  # type: ignore[call-arg]
        note="按 GLM 服务端已用比例",
    )
