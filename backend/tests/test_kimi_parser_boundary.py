"""Kimi parser 边界用例补充（离线，无真实请求/凭据）。

覆盖验证器指出的薄弱点：
- usage 与 limits 同时缺失（空响应）；
- percentage 字段（字符串或数字形式）被解析器忽略，不影响 used/limit；
- 数值边界：limit=0、零额度、极大值、used==limit、reset_in=0、resetAt 仅日期。
- 窗口派生标签的更多 timeUnit（DAY、未知单位、duration 非整除分钟）。
"""

from __future__ import annotations

from app.providers.kimi_parser import parse_kimi_usage


# ---- usage 与 limits 同时缺失 ----


def test_empty_object_returns_empty_without_raising() -> None:
    # usage 和 limits 都不存在 -> 空列表，不抛错（优雅降级）。
    assert parse_kimi_usage({}) == []


def test_usage_and_limits_both_null() -> None:
    assert parse_kimi_usage({"usage": None, "limits": None}) == []


def test_only_unrelated_keys_present() -> None:
    assert parse_kimi_usage({"code": 0, "msg": "ok"}) == []


# ---- percentage 字段被忽略（字符串/数字都不影响 used/limit）----


def test_percentage_numeric_field_ignored() -> None:
    windows = parse_kimi_usage(
        {"usage": {"used": 40, "limit": 1000, "percentage": 4}}
    )
    # used/limit 来自 used/limit，而非 percentage。
    assert windows[0].used == 40
    assert windows[0].limit == 1000


def test_percentage_string_field_ignored() -> None:
    # 服务商有时把 percentage 返回成字符串（如 "4.0"），解析器不应据此改 used/limit。
    windows = parse_kimi_usage(
        {"usage": {"used": 40, "limit": 1000, "percentage": "4.0"}}
    )
    assert windows[0].used == 40
    assert windows[0].limit == 1000


def test_percentage_field_does_not_appear_anywhere_harmful() -> None:
    # 即便 percentage 极大/异常，也不应导致除零或越界。
    windows = parse_kimi_usage(
        {"usage": {"used": 1, "limit": 10, "percentage": 999999}}
    )
    assert windows[0].used == 1
    assert windows[0].limit == 10


# ---- 数值边界 ----


def test_limit_zero_kept_as_zero() -> None:
    # limit=0：官方规则 limit<=0 时占比 0；这里只断言不崩溃且 limit=0。
    windows = parse_kimi_usage({"usage": {"used": 0, "limit": 0}})
    assert windows[0].limit == 0
    assert windows[0].used == 0


def test_used_equals_limit_at_cap() -> None:
    windows = parse_kimi_usage({"usage": {"used": 100, "limit": 100}})
    assert windows[0].used == 100
    assert windows[0].limit == 100


def test_huge_token_values_handled() -> None:
    # 极大 token 值（周窗口量级）。
    windows = parse_kimi_usage(
        {"usage": {"used": 999_999_999_999, "limit": 1_000_000_000_000}}
    )
    assert windows[0].used == 999_999_999_999
    assert windows[0].limit == 1_000_000_000_000


def test_reset_in_zero_yields_no_reset() -> None:
    # reset_in=0：官方只在 >0 时才推算未来时间；0/负数应返回 None。
    windows = parse_kimi_usage({"usage": {"used": 1, "limit": 10, "reset_in": 0}})
    assert windows[0].reset_at is None


def test_reset_in_negative_yields_no_reset() -> None:
    windows = parse_kimi_usage({"usage": {"used": 1, "limit": 10, "reset_in": -100}})
    assert windows[0].reset_at is None


def test_reset_at_date_only_iso_accepted() -> None:
    # 仅日期（无时间分量）的 ISO 也应可解析。
    windows = parse_kimi_usage(
        {"usage": {"used": 1, "limit": 10, "resetAt": "2026-07-28"}}
    )
    assert windows[0].reset_at is not None
    assert windows[0].reset_at.year == 2026


# ---- 窗口派生标签的更多 timeUnit ----


def test_day_window_label() -> None:
    payload = {
        "limits": [
            {"detail": {"used": 1, "limit": 100}, "window": {"duration": 7, "timeUnit": "DAY"}}
        ]
    }
    assert parse_kimi_usage(payload)[0].label == "7d limit"


def test_unknown_time_unit_label() -> None:
    payload = {
        "limits": [
            {"detail": {"used": 1, "limit": 100}, "window": {"duration": 2, "timeUnit": "WEEK"}}
        ]
    }
    # 未知单位走默认分支 -> "Ns limit"。
    assert parse_kimi_usage(payload)[0].label == "2s limit"


def test_minute_non_hour_divisible_label() -> None:
    # duration=90 分钟，不能整除 60 -> "90m limit"。
    payload = {
        "limits": [
            {"detail": {"used": 1, "limit": 100}, "window": {"duration": 90, "timeUnit": "MINUTE"}}
        ]
    }
    assert parse_kimi_usage(payload)[0].label == "90m limit"


def test_limits_item_without_detail_uses_item_fields() -> None:
    # 无 detail 时直接读 item 本身作为 quota 行。
    payload = {
        "limits": [
            {"used": 5, "limit": 50, "name": "Direct", "window": {"duration": 5, "timeUnit": "HOUR"}}
        ]
    }
    windows = parse_kimi_usage(payload)
    assert windows[0].label == "Direct"
    assert windows[0].used == 5
    assert windows[0].limit == 50


def test_limits_with_many_items_preserves_count() -> None:
    payload = {
        "limits": [
            {"detail": {"used": i, "limit": 100}, "window": {"duration": 1, "timeUnit": "HOUR"}}
            for i in range(1, 6)
        ]
    }
    windows = parse_kimi_usage(payload)
    assert len(windows) == 5
    assert [w.used for w in windows] == [1.0, 2.0, 3.0, 4.0, 5.0]
