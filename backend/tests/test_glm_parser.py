"""Stage 6 离线测试：GLM quota/limit 解析器。

字段契约依据官方插件 zai-org/zai-coding-plugins（L2，query-usage.mjs）。
**不发起任何真实请求，不接触凭据**。
覆盖：当前三窗口 percentage=已用比例契约、历史 usage/currentValue 绝对值契约、
nextResetTime 毫秒/秒/ISO、历史 percentage>100 提示、默认 5h 上限、包络兼容。
"""

from __future__ import annotations

import pytest

from app.models import QuotaWindow
from app.providers.base import ContractError
from app.providers.glm_parser import parse_glm_usage


# 官方样例衍生的脱敏响应（data.limits 包络）。
GLM_RESPONSE = {
    "code": 200,
    "msg": "success",
    "data": {
        "code": 200,
        "limits": [
            {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "usage": 40000000,
                "currentValue": 12345678,
                "percentage": 31,
                "nextResetTime": 1760000000000,  # 毫秒
            },
            {
                "type": "TOKENS_LIMIT",
                "unit": 6,
                "usage": 280000000,
                "currentValue": 89000000,
                "percentage": 32,
                "nextResetTime": 1760500000000,
            },
            {
                "type": "TIME_LIMIT",
                "unit": 0,
                "usage": 100,
                "currentValue": 30,
                "percentage": 30,
                "nextResetTime": None,
            },
        ],
    },
}

CURRENT_PERCENTAGE_RESPONSE = {
    "code": 200,
    "success": True,
    "data": {
        "level": "test-plan",
        "limits": [
            {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 111,
                "percentage": 73.5,
                "nextResetTime": 1_768_000_000_000,
            },
            {
                "type": "TOKENS_LIMIT",
                "unit": 6,
                "number": 222,
                "percentage": 42,
                "nextResetTime": 1_768_400_000_000,
            },
            {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 333,
                "percentage": 61,
                "usage": 999,
                "currentValue": 123,
                "remaining": 456,
                "usageDetails": [{"type": "test-tool"}],
                "nextResetTime": 1_768_800_000_000,
            },
        ],
    },
}


# ---- 当前按类型区分 percentage 语义 ----


def test_current_contract_returns_three_percentage_windows() -> None:
    windows = parse_glm_usage(CURRENT_PERCENTAGE_RESPONSE)
    assert [window.label for window in windows] == [
        "5 小时窗口",
        "周窗口",
        "月度/MCP 工具窗口",
    ]
    assert [(window.used, window.limit, window.unit) for window in windows] == [
        (73.5, 100.0, "percent"),
        (42.0, 100.0, "percent"),
        (61.0, 100.0, "percent"),
    ]
    assert all(window.reset_at is not None for window in windows)


def test_current_token_percentage_is_used_not_remaining() -> None:
    windows = parse_glm_usage(CURRENT_PERCENTAGE_RESPONSE)
    five_hour = windows[0]
    weekly = windows[1]
    assert five_hour.used == 73.5
    assert five_hour.limit - five_hour.used == 26.5
    assert weekly.used == 42
    assert weekly.limit - weekly.used == 58
    assert "服务端已用比例" in (five_hour.note or "")
    assert "服务端已用比例" in (weekly.note or "")


def test_current_time_limit_percentage_is_used_not_remaining() -> None:
    windows = parse_glm_usage(CURRENT_PERCENTAGE_RESPONSE)
    tool_window = windows[2]
    # TIME_LIMIT 的绝对字段并非共享百分比的可靠分母；percentage 本身就是已用比例。
    assert tool_window.used == 61
    assert tool_window.limit - tool_window.used == 39
    assert "服务端已用比例" in (tool_window.note or "")


def test_current_contract_rejects_out_of_range_percentage() -> None:
    payload = {
        "data": {
            "limits": [
                {
                    "type": "TOKENS_LIMIT",
                    "unit": 6,
                    "number": 1,
                    "percentage": 101,
                }
            ]
        }
    }
    with pytest.raises(ContractError):
        parse_glm_usage(payload)


# ---- usage=上限 / currentValue=已用（关键字段名误导）----


def test_usage_is_limit_and_current_value_is_used() -> None:
    windows = parse_glm_usage(GLM_RESPONSE)
    by_label = {w.label: w for w in windows}
    five_h = by_label["5 小时窗口"]
    # usage=40000000 是上限，currentValue=12345678 是已用。
    assert five_h.limit == 40000000
    assert five_h.used == 12345678
    assert five_h.unit == "tokens"


def test_unit_labels() -> None:
    windows = parse_glm_usage(GLM_RESPONSE)
    labels = [w.label for w in windows]
    assert "5 小时窗口" in labels
    assert "周窗口" in labels
    assert "月度/MCP 工具窗口" in labels


def test_time_limit_unit_is_calls() -> None:
    windows = parse_glm_usage(GLM_RESPONSE)
    time_window = next(w for w in windows if w.label == "月度/MCP 工具窗口")
    assert time_window.unit == "calls"


# ---- nextResetTime >1e12 启发式 ----


def test_reset_time_milliseconds() -> None:
    windows = parse_glm_usage(GLM_RESPONSE)
    five_h = next(w for w in windows if w.label == "5 小时窗口")
    assert five_h.reset_at is not None
    # 1760000000000 ms -> 2025-10-XX UTC
    assert five_h.reset_at.year == 2025


def test_reset_time_seconds_when_below_threshold() -> None:
    payload = {"data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 10, "nextResetTime": 1760000000}]}}
    windows = parse_glm_usage(payload)
    assert windows[0].reset_at is not None
    assert windows[0].reset_at.year == 2025


def test_reset_time_iso_string() -> None:
    payload = {"data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 10, "nextResetTime": "2026-07-28T00:00:00Z"}]}}
    windows = parse_glm_usage(payload)
    assert windows[0].reset_at is not None
    assert windows[0].reset_at.year == 2026


def test_reset_time_none_allowed() -> None:
    payload = {"data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 10, "nextResetTime": None}]}}
    windows = parse_glm_usage(payload)
    assert windows[0].reset_at is None


# ---- 默认 5h 上限 ----


def test_default_5h_limit_when_usage_missing() -> None:
    payload = {"data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 3, "currentValue": 5000000}]}}
    windows = parse_glm_usage(payload)
    assert len(windows) == 1
    assert windows[0].limit == 40000000
    assert windows[0].used == 5000000


def test_non_5h_without_limit_dropped() -> None:
    # unit=6 且无 usage -> 丢弃（无默认）。
    payload = {"data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 6, "currentValue": 5000000}]}}
    assert parse_glm_usage(payload) == []


# ---- percentage >100 不钳制 ----


def test_over_quota_percentage_noted_not_clamped() -> None:
    payload = {
        "data": {
            "limits": [
                {"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 137, "percentage": 137}
            ]
        }
    }
    windows = parse_glm_usage(payload)
    # used 不钳制（如实保留 137）。
    assert windows[0].used == 137
    assert windows[0].limit == 100
    # note 提示超额。
    assert windows[0].note is not None
    assert "超额" in windows[0].note


# ---- 包络兼容 ----


def test_top_level_limits_envelope_accepted() -> None:
    payload = {"code": 200, "limits": [{"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 10}]}
    windows = parse_glm_usage(payload)
    assert len(windows) == 1


def test_non_object_payload_raises() -> None:
    with pytest.raises(ContractError):
        parse_glm_usage([{"type": "TOKENS_LIMIT"}])  # type: ignore[arg-type]


def test_empty_limits_returns_empty() -> None:
    assert parse_glm_usage({"data": {"limits": []}}) == []
    assert parse_glm_usage({}) == []


def test_unknown_unit_label() -> None:
    payload = {"data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 99, "usage": 100, "currentValue": 10}]}}
    windows = parse_glm_usage(payload)
    assert windows[0].label == "unit 99 窗口"


def test_non_string_type_dropped() -> None:
    payload = {"data": {"limits": [{"unit": 3, "usage": 100, "currentValue": 10}, 42]}}  # type: ignore[list-item]
    assert parse_glm_usage(payload) == []


def test_windows_are_quota_window_type() -> None:
    windows = parse_glm_usage(GLM_RESPONSE)
    assert all(isinstance(w, QuotaWindow) for w in windows)
