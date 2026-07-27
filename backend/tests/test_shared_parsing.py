"""共享解析工具 _parsing 的一致性测试（阶段 7）。

锁定 Kimi 与 GLM 解析器共同依赖的底层行为，防止未来重构两家时产生漂移。
覆盖：数字容忍（int/float/str/bool/None/NaN/Inf）、ISO8601 解析（含纳秒截断、时区标记）。
"""

from __future__ import annotations

import math
from datetime import timezone

import pytest

from app.providers import _parsing


# ---- to_int / to_number 数字容忍 ----


@pytest.mark.parametrize(
    "value, expected",
    [
        (42, 42),
        (42.0, 42),
        (42.9, 42),  # 截断到 int
        ("42", 42),
        ("42.0", 42),
        ("42.9", 42),
        (-5, -5),
        (0, 0),
    ],
)
def test_to_int_accepts_numeric(value, expected: int) -> None:
    assert _parsing.to_int(value) == expected


@pytest.mark.parametrize(
    "value",
    [None, True, False, "unknown", "", "NaN", "Infinity", float("nan"), float("inf"), float("-inf")],
)
def test_to_int_rejects_invalid(value) -> None:
    assert _parsing.to_int(value) is None


@pytest.mark.parametrize(
    "value, expected",
    [
        (42, 42.0),
        (42.5, 42.5),
        ("42.5", 42.5),
    ],
)
def test_to_number_preserves_fraction(value, expected: float) -> None:
    assert _parsing.to_number(value) == expected


def test_to_number_rejects_bool_and_invalid() -> None:
    assert _parsing.to_number(True) is None
    assert _parsing.to_number(float("nan")) is None
    assert _parsing.to_number("not-a-number") is None


# ---- ISO8601 解析（含纳秒截断）----


def test_parse_iso_basic_utc() -> None:
    dt = _parsing.parse_iso_to_utc("2026-07-28T00:00:00Z")
    assert dt is not None
    assert dt.year == 2026
    assert dt.tzinfo == timezone.utc


def test_parse_iso_nanosecond_truncated_to_microsecond() -> None:
    dt = _parsing.parse_iso_to_utc("2025-12-23T05:24:18.443553353Z")
    assert dt is not None
    assert dt.microsecond == 443553  # 9 位纳秒截断到 6 位微秒


def test_parse_iso_naive_treated_as_utc() -> None:
    dt = _parsing.parse_iso_to_utc("2026-07-28T00:00:00")
    assert dt is not None
    assert dt.tzinfo == timezone.utc


def test_parse_iso_date_only() -> None:
    dt = _parsing.parse_iso_to_utc("2026-07-28")
    assert dt is not None
    assert dt.year == 2026


@pytest.mark.parametrize("value", [None, "", "   ", "not-a-date", 12345, []])
def test_parse_iso_rejects_invalid(value) -> None:
    assert _parsing.parse_iso_to_utc(value) is None


def test_parse_iso_offset_marker_preserved() -> None:
    # 带 +00:00 标记的小数也应正确截断。
    dt = _parsing.parse_iso_to_utc("2025-12-23T05:24:18.123456789+00:00")
    assert dt is not None
    assert dt.microsecond == 123456


# ---- 跨解析器一致性：Kimi 与 GLM 对同一 ISO 字符串解析结果相同 ----


def test_kimi_and_glm_parse_iso_consistently() -> None:
    """同一 ISO 字符串经两家解析应得到同一 datetime（秒级一致）。"""

    from app.providers.glm_parser import _parse_reset_time
    from app.providers.kimi_parser import _parse_iso

    iso = "2025-12-23T05:24:18.443553353Z"
    kimi_dt = _parse_iso(iso)
    glm_dt = _parse_reset_time(iso)
    assert kimi_dt is not None and glm_dt is not None
    # 秒级一致（两家都截断到微秒，应完全相等）。
    assert kimi_dt == glm_dt


def test_truncate_subseconds_public_alias() -> None:
    assert _parsing.truncate_subseconds("2025-12-23T05:24:18.443553353Z") == (
        "2025-12-23T05:24:18.443553Z"
    )
    # 无小数部分时原样返回。
    assert _parsing.truncate_subseconds("2026-07-28T00:00:00Z") == "2026-07-28T00:00:00Z"
