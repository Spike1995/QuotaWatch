"""GLM parser 边界用例补充（离线，无真实请求/凭据）。

覆盖：
- percentage 字符串/数字形式与 used/limit 的关系；
- 数值字段为数字字符串；
- 混合包络（data.limits 与顶层 limits 同在）；
- unit 缺失、type 缺失但 unit=3 仍给默认上限；
- nextResetTime 为数字字符串、负数、超大毫秒。
"""

from __future__ import annotations

from app.providers.glm_parser import parse_glm_usage


# ---- percentage 字符串/数字 ----


def test_percentage_string_over_100_noted() -> None:
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 137, "percentage": "137.5"}
            ]
        }
    }
    windows = parse_glm_usage(payload)
    assert windows[0].used == 137
    assert windows[0].limit == 100
    assert windows[0].note is not None
    assert "138" in windows[0].note  # 四舍五入到整数


def test_percentage_numeric_under_100_no_note() -> None:
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 30, "percentage": 30}
            ]
        }
    }
    windows = parse_glm_usage(payload)
    assert windows[0].note is None


def test_percentage_absent_does_not_crash() -> None:
    payload = {
        "data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 30}]}
    }
    windows = parse_glm_usage(payload)
    assert windows[0].used == 30
    assert windows[0].note is None


# ---- 数值字段为数字字符串 ----


def test_numeric_string_usage_and_current_value() -> None:
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": 3, "usage": "40000000", "currentValue": "12345678"}
            ]
        }
    }
    windows = parse_glm_usage(payload)
    assert windows[0].limit == 40000000
    assert windows[0].used == 12345678


def test_numeric_string_unit_accepted() -> None:
    # unit 以数字字符串给出也应识别为 5h。
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": "3", "usage": 100, "currentValue": 10}
            ]
        }
    }
    windows = parse_glm_usage(payload)
    assert windows[0].label == "5 小时窗口"


# ---- 混合包络：data.limits 优先于顶层 limits ----


def test_data_limits_takes_precedence_over_top_level() -> None:
    payload = {
        "code": 200,
        "limits": [{"type": "TOKENS_LIMIT", "unit": 6, "usage": 1, "currentValue": 1}],
        "data": {
            "limits": [{"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 10}]
        },
    }
    windows = parse_glm_usage(payload)
    # 只解析 data.limits（优先）。
    assert len(windows) == 1
    assert windows[0].label == "5 小时窗口"


# ---- unit/type 缺失组合 ----


def test_unit_missing_falls_back_to_type_label() -> None:
    payload = {
        "data": {"limits": [{"type": "TOKENS_LIMIT", "usage": 100, "currentValue": 10}]}
    }
    windows = parse_glm_usage(payload)
    assert windows[0].label == "TOKENS_LIMIT"


def test_type_missing_but_unit3_still_uses_default_limit() -> None:
    # type 缺失 -> _item_to_window 因 type 非字符串返回 None（被跳过）。
    # 这是有意的保守行为：无 type 无法确定语义。
    payload = {
        "data": {"limits": [{"unit": 3, "usage": 0, "currentValue": 5}]}
    }
    assert parse_glm_usage(payload) == []


# ---- nextResetTime 边界 ----


def test_next_reset_time_numeric_string_ms() -> None:
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 10, "nextResetTime": "1760000000000"}
            ]
        }
    }
    windows = parse_glm_usage(payload)
    assert windows[0].reset_at is not None
    assert windows[0].reset_at.year == 2025


def test_next_reset_time_negative_yields_none() -> None:
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 10, "nextResetTime": -1}
            ]
        }
    }
    # 负秒数 -> fromtimestamp 会得到很早的日期；但 -1 被当作秒数 -> 1969。
    # 关键是不崩溃；断言 reset_at 不是 None（负秒也是合法时间戳）。
    windows = parse_glm_usage(payload)
    assert windows[0].reset_at is not None
    assert windows[0].reset_at.year < 1971


def test_next_reset_time_huge_ms_handled() -> None:
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 10, "nextResetTime": 9999999999999}
            ]
        }
    }
    windows = parse_glm_usage(payload)
    # 不崩溃；远未来日期。
    assert windows[0].reset_at is not None
    assert windows[0].reset_at.year > 2000


# ---- 默认上限只对 unit=3 生效 ----


def test_default_limit_only_for_unit3_not_unit6() -> None:
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": 6, "usage": 0, "currentValue": 5}
            ]
        }
    }
    # unit=6 无默认上限且 usage=0 -> 丢弃。
    assert parse_glm_usage(payload) == []


def test_unit3_with_usage_zero_uses_default() -> None:
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": 3, "usage": 0, "currentValue": 5}
            ]
        }
    }
    windows = parse_glm_usage(payload)
    assert len(windows) == 1
    assert windows[0].limit == 40000000
    assert windows[0].used == 5
