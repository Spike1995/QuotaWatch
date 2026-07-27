"""Provider 解析器的共享底层工具（阶段 6/7）。

Kimi 与 GLM 解析器原本各自重复实现了数字容忍转换与 ISO8601（含纳秒截断）解析，
存在细微漂移风险。本模块抽取为单一来源，供两家复用。

契约依据：
- 数字容忍：官方解析器接受 int/float/数字字符串，拒绝 None/bool/NaN/Inf。
- ISO：官方样例可达纳秒（9 位小数），Python fromisoformat 最多 6 位微秒，截断到微秒。

本模块纯函数、无副作用、无网络/凭据。
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any


def to_number(value: Any) -> float | None:
    """把任意值容忍转换为 float；拒绝 None/bool/非数字字符串/NaN/Inf。"""

    if isinstance(value, bool):  # bool 是 int 子类，必须先排除
        return None
    if isinstance(value, (int, float)):
        if _is_not_finite(value):
            return None
        return float(value)
    if isinstance(value, str):
        try:
            f = float(value)
        except ValueError:
            return None
        if _is_not_finite(f):
            return None
        return f
    return None


def to_int(value: Any) -> int | None:
    """把任意值容忍转换为 int；拒绝 None/bool/非数字字符串/NaN/Inf。

    接受 "42"/42/42.0，拒绝 None/"unknown"/NaN/Infinity。
    """

    num = to_number(value)
    if num is None:
        return None
    return int(num)


def parse_iso_to_utc(value: Any) -> datetime | None:
    """解析 ISO8601 字符串到 UTC datetime；容忍纳秒精度（截断到微秒）。

    非 str / 空串 / 无法解析时返回 None。naive datetime 视作 UTC。
    """

    if not isinstance(value, str):
        return None
    text = value.strip()
    if not text:
        return None
    text = _truncate_subseconds(text)
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


def truncate_subseconds(text: str) -> str:
    """公开别名：把 ISO 字符串的小数部分截断到 6 位（微秒）。"""

    return _truncate_subseconds(text)


def _truncate_subseconds(text: str) -> str:
    """截断 ISO 小数部分到 6 位，保留尾部时区标记。

    时区标记可能是 `Z`，或形如 `+08:00`/`-05:30`/`+0800` 的 UTC 偏移。
    偏移量从 frac 中最后一个 `+`/`-` 开始（不能只匹配固定列表，否则非零偏移会丢失）。
    """

    if "." not in text:
        return text
    head, _, frac = text.partition(".")
    tz_suffix = ""
    if frac.endswith("Z"):
        tz_suffix = "Z"
        frac = frac[:-1]
    else:
        # 查找 frac 中最后一个 + 或 -（UTC 偏移起始）。
        plus_idx = frac.rfind("+")
        minus_idx = frac.rfind("-")
        offset_idx = max(plus_idx, minus_idx)
        if offset_idx > 0:  # 0 不算（那会是 frac 开头，不是偏移）
            tz_suffix = frac[offset_idx:]
            frac = frac[:offset_idx]
    frac = frac[:6]
    return f"{head}.{frac}{tz_suffix}"


def _is_not_finite(value: float) -> bool:
    return value != value or value in (float("inf"), float("-inf"))  # NaN 或 Inf
