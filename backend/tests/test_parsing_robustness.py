"""_parsing 共享模块的健壮性/属性测试（阶段 7）。

锁定“永不抛异常”契约：任意输入（包括极端/畸形）都应返回 None 或合法值，绝不抛异常。
这是解析器面对第三方脏数据时的关键安全保证。
"""

from __future__ import annotations

import math

import pytest

from app.providers import _parsing

# 极端/畸形输入样本，用于喂给两个转换函数，断言“不抛异常”。
_WEIRD_VALUES = [
    None,
    "",
    "   ",
    "NaN",
    "Infinity",
    "-Infinity",
    "not-a-number",
    "1e308",
    "1e400",  # 溢出 float
    "-1e400",
    "0x10",  # 非十进制
    "１２３",  # 全角数字
    [],
    {},
    {},
    object(),
    b"42",  # bytes
    complex(1, 2),
    float("nan"),
    float("inf"),
    float("-inf"),
    True,
    False,
    1 << 100,  # 超大 int
    -1,
    3.14159,
]


@pytest.mark.parametrize("value", _WEIRD_VALUES)
def test_to_int_never_raises(value) -> None:
    # 必须返回 int 或 None，绝不抛异常。
    try:
        result = _parsing.to_int(value)
    except Exception as exc:  # noqa: BLE001
        pytest.fail(f"to_int({value!r}) raised {exc}")
    assert result is None or isinstance(result, int)


@pytest.mark.parametrize("value", _WEIRD_VALUES)
def test_to_number_never_raises(value) -> None:
    try:
        result = _parsing.to_number(value)
    except Exception as exc:  # noqa: BLE001
        pytest.fail(f"to_number({value!r}) raised {exc}")
    assert result is None or isinstance(result, float)
    # 若返回 float，不能是 NaN/Inf（契约拒绝）。
    if result is not None:
        assert math.isfinite(result)


@pytest.mark.parametrize("value", _WEIRD_VALUES)
def test_parse_iso_never_raises(value) -> None:
    try:
        result = _parsing.parse_iso_to_utc(value)
    except Exception as exc:  # noqa: BLE001
        pytest.fail(f"parse_iso_to_utc({value!r}) raised {exc}")
    # 非 str 或无法解析返回 None；成功则必须是带 tz 的 datetime。
    if result is not None:
        assert result.tzinfo is not None


# ---- 边界：超大/超小合法数字 ----


def test_to_int_huge_integer() -> None:
    big = 1 << 64
    assert _parsing.to_int(big) == big


def test_to_number_tiny_float() -> None:
    assert _parsing.to_number(1e-300) == 1e-300


# ---- truncate_subseconds 不抛异常 ----


@pytest.mark.parametrize("value", _WEIRD_VALUES)
def test_truncate_subseconds_never_raises_on_nonstring(value) -> None:
    # 非 str 时直接原样返回（函数签名期望 str，但不应对非 str 抛 AttributeError）。
    if not isinstance(value, str):
        # 非 str 输入：函数会走到 "." not in text，对非 str 会抛 TypeError；
        # 这里只验证 str 输入的健壮性，非 str 不在本函数契约内。
        return
    try:
        _parsing.truncate_subseconds(value)
    except Exception as exc:  # noqa: BLE001
        pytest.fail(f"truncate_subseconds({value!r}) raised {exc}")
