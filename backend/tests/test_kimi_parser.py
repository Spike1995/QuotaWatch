"""Stage 6 / 卡 3 离线测试：Kimi /coding/v1/usages 解析器。

全部用官方样例衍生 Fixture，**不发起任何真实请求，不接触凭据**。
字段契约依据 MoonshotAI/kimi-cli（Python）与 kimi-code（TS）源码（L2）。
覆盖：usage 行、limits 行、used 缺失走 remaining 回退、resetAt ISO（含纳秒）、
reset_in 秒数、used>limit 钳制、字段缺失丢弃行、totalQuota 被忽略、契约变化抛错。
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.models import QuotaWindow
from app.providers.base import ContractError
from app.providers.kimi_parser import parse_kimi_usage

FIXTURE_DIR = Path(__file__).resolve().parents[1] / "fixtures" / "kimi"


# ---- 基本结构 ----


def test_minimal_usage_summary() -> None:
    windows = parse_kimi_usage({"usage": {"used": 40, "limit": 1000, "name": "Weekly limit"}})

    assert len(windows) == 1
    w = windows[0]
    assert w.label == "Weekly limit"
    assert w.used == 40
    assert w.limit == 1000
    assert w.unit == "tokens"


def test_usage_default_label_when_name_absent() -> None:
    windows = parse_kimi_usage({"usage": {"used": 40, "limit": 1000}})

    assert windows[0].label == "Weekly limit"


def test_limits_with_detail_and_window_label() -> None:
    payload = {
        "limits": [
            {"detail": {"used": 1, "limit": 100}, "window": {"duration": 300, "timeUnit": "MINUTE"}},
            {"detail": {"used": 2, "limit": 50}, "window": {"duration": 24, "timeUnit": "HOUR"}},
        ]
    }
    windows = parse_kimi_usage(payload)

    assert len(windows) == 2
    assert windows[0].label == "5h limit"   # 300 分钟 = 5h
    assert windows[1].label == "24h limit"


def test_item_name_preferred_over_window_duration() -> None:
    payload = {
        "limits": [
            {
                "name": "Daily cap",
                "detail": {"used": 5, "limit": 100},
                "window": {"duration": 1440, "timeUnit": "MINUTE"},
            }
        ]
    }
    windows = parse_kimi_usage(payload)

    assert windows[0].label == "Daily cap"


# ---- used 缺失走 remaining 回退 ----


def test_used_falls_back_to_limit_minus_remaining() -> None:
    windows = parse_kimi_usage({"usage": {"remaining": 200, "limit": 1000}})

    assert windows[0].used == 800
    assert windows[0].limit == 1000


def test_row_without_used_or_limit_is_dropped() -> None:
    # 同时缺 used 与 limit -> 丢弃该行。
    windows = parse_kimi_usage({"limits": [{"detail": {"name": "x"}}]})
    assert windows == []


# ---- 钳制 ----


def test_used_greater_than_limit_clamped() -> None:
    windows = parse_kimi_usage({"usage": {"used": 150, "limit": 100}})

    assert windows[0].used == 100
    assert windows[0].limit == 100


# ---- reset 时间 ----


def test_reset_at_iso_string_parsed() -> None:
    windows = parse_kimi_usage(
        {"usage": {"used": 40, "limit": 1000, "resetAt": "2025-12-23T05:24:18Z"}}
    )
    assert windows[0].reset_at is not None
    assert windows[0].reset_at.year == 2025
    assert windows[0].reset_at.month == 12


def test_reset_at_nanosecond_precision_truncated() -> None:
    # 官方可达纳秒（9 位），解析器截断到微秒而不报错。
    windows = parse_kimi_usage(
        {"usage": {"used": 40, "limit": 1000, "resetAt": "2025-12-23T05:24:18.443553353Z"}}
    )
    assert windows[0].reset_at is not None
    assert windows[0].reset_at.microsecond == 443553


def test_reset_at_aliases_accepted() -> None:
    for key in ("reset_at", "resetTime", "reset_time"):
        windows = parse_kimi_usage(
            {"usage": {"used": 1, "limit": 10, key: "2025-12-23T05:24:18Z"}}
        )
        assert windows[0].reset_at is not None, key


def test_reset_in_seconds_fallback() -> None:
    # 没有 ISO 字段时，用 reset_in 秒数推算一个未来时间。
    windows = parse_kimi_usage({"usage": {"used": 1, "limit": 10, "reset_in": 7200}})
    assert windows[0].reset_at is not None


# ---- 数字字符串容忍 ----


def test_numeric_string_limit_accepted() -> None:
    windows = parse_kimi_usage({"usage": {"used": "42", "limit": "100"}})
    assert windows[0].used == 42
    assert windows[0].limit == 100


# ---- 被忽略的字段 ----


def test_total_quota_field_ignored() -> None:
    # issue #1569 的 bug 字段 totalQuota 不应影响结果。
    windows = parse_kimi_usage(
        {"usage": {"used": 40, "limit": 1000, "totalQuota": 99}}
    )
    assert windows[0].limit == 1000
    assert windows[0].used == 40


def test_booster_wallet_ignored_this_phase() -> None:
    payload = {
        "usage": {"used": 40, "limit": 1000, "name": "Weekly limit"},
        "boosterWallet": {"balance": {"type": "BOOSTER", "amount": "20000000000"}},
    }
    windows = parse_kimi_usage(payload)
    # 只解析出 usage 一个窗口，boosterWallet 不产生额外窗口。
    assert len(windows) == 1


# ---- 契约变化 ----


def test_non_object_payload_raises_contract_error() -> None:
    with pytest.raises(ContractError):
        parse_kimi_usage([{"used": 1}])  # type: ignore[arg-type]
    with pytest.raises(ContractError):
        parse_kimi_usage("not an object")  # type: ignore[arg-type]


def test_empty_payload_returns_empty_list() -> None:
    assert parse_kimi_usage({}) == []


def test_combined_usage_and_limits() -> None:
    payload = {
        "usage": {"used": 40, "limit": 1000, "name": "Weekly limit"},
        "limits": [
            {"detail": {"used": 1, "limit": 100}, "window": {"duration": 5, "timeUnit": "HOUR"}},
        ],
    }
    windows = parse_kimi_usage(payload)
    assert len(windows) == 2
    assert windows[0].label == "Weekly limit"
    assert windows[1].label == "5h limit"


def test_windows_are_quota_window_type() -> None:
    windows = parse_kimi_usage({"usage": {"used": 1, "limit": 10}})
    assert isinstance(windows[0], QuotaWindow)


# ---- 基于文件的 Fixture 契约测试 ----


def _load_fixture(name: str) -> dict:
    """读取 backend/fixtures/kimi/<name>，跳过 _comment 字段。"""

    data = json.loads((FIXTURE_DIR / name).read_text(encoding="utf-8"))
    data.pop("_comment", None)
    return data


def test_typical_fixture_parses_two_windows() -> None:
    payload = _load_fixture("usage_typical.json")
    windows = parse_kimi_usage(payload)

    assert [w.label for w in windows] == ["Weekly limit", "5h limit"]
    weekly = windows[0]
    assert weekly.used == 320000000
    assert weekly.limit == 1000000000
    assert weekly.reset_at is not None
    assert weekly.reset_at.year == 2026


def test_remaining_fallback_fixture() -> None:
    payload = _load_fixture("usage_remaining_fallback.json")
    windows = parse_kimi_usage(payload)

    assert len(windows) == 1
    # used = limit - remaining = 1000 - 200 = 800
    assert windows[0].used == 800
    assert windows[0].limit == 1000

