"""Kimi/GLM 解析器内部辅助函数直接单元测试（阶段 7）。

此前这些 helper 仅经 parse_* 主入口间接测试；本文件直接锁定其契约边界，便于未来重构。
覆盖：Kimi `_window_label`（DAY/未知单位/分钟非整除）、`_label` 默认回退；
GLM `_extract_limits`（data.limits 优先、顶层 limits 兜底、两者都缺、data 非 dict）。
全部离线，无真实请求/凭据。
"""

from __future__ import annotations

import pytest

from app.providers.glm_parser import _extract_limits
from app.providers.kimi_parser import _label, _window_label

# ---- Kimi _window_label ----


@pytest.mark.parametrize(
    "duration, unit, expected",
    [
        (5, "HOUR", "5h limit"),
        (24, "HOUR", "24h limit"),
        (300, "MINUTE", "5h limit"),  # 300 分钟整除 60 -> 5h
        (90, "MINUTE", "90m limit"),  # 90 分钟不整除 -> 90m
        (7, "DAY", "7d limit"),
        (45, "mInUtE", "45m limit"),  # 大小写不敏感
        (2, "WEEK", "2s limit"),  # 未知单位 -> 默认 Ns
        (1, "MONTH", "1s limit"),
    ],
)
def test_window_label(duration: int, unit: str, expected: str) -> None:
    assert _window_label(duration, unit) == expected


def test_window_label_zero_duration() -> None:
    # duration=0 的边界（不应崩溃）。
    assert _window_label(0, "HOUR") == "0h limit"


# ---- Kimi _label ----


def test_label_usage_row_with_name() -> None:
    # usage 行（item=None）：name 优先。
    assert _label({"name": "Weekly"}, item=None, default="Weekly limit", index=0) == "Weekly"


def test_label_usage_row_default_when_no_name() -> None:
    assert _label({}, item=None, default="Weekly limit", index=0) == "Weekly limit"


def test_label_limit_item_scope_fallback() -> None:
    # limits 行：item.name -> item.title -> item.scope。
    assert (
        _label({}, item={"scope": "daily"}, default="x", index=0) == "daily"
    )


def test_label_limit_item_index_fallback() -> None:
    # 无任何名称字段、也无窗口派生 -> "Limit #N"。
    assert _label({}, item={}, default="x", index=2) == "Limit #3"


def test_label_item_takes_precedence_over_data() -> None:
    # item 与 data 都有 name 时，item 优先。
    assert (
        _label({"name": "from-data"}, item={"name": "from-item"}, default="x", index=0)
        == "from-item"
    )


# ---- GLM _extract_limits ----


def test_extract_limits_prefers_data_limits() -> None:
    payload = {
        "limits": [{"type": "X", "usage": 1, "currentValue": 1}],  # 应被忽略
        "data": {"limits": [{"type": "Y", "usage": 2, "currentValue": 2}]},
    }
    result = _extract_limits(payload)
    assert len(result) == 1
    assert result[0]["type"] == "Y"


def test_extract_limits_falls_back_to_top_level() -> None:
    payload = {"limits": [{"type": "Z", "usage": 3, "currentValue": 3}]}
    result = _extract_limits(payload)
    assert len(result) == 1
    assert result[0]["type"] == "Z"


def test_extract_limits_data_present_but_no_limits_key() -> None:
    # data 是 dict 但无 limits 键 -> 回退顶层。
    payload = {"data": {"code": 200}, "limits": [{"type": "TOP"}]}
    result = _extract_limits(payload)
    assert len(result) == 1


def test_extract_limits_neither_present() -> None:
    assert _extract_limits({}) == []
    assert _extract_limits({"data": {}}) == []


def test_extract_limits_data_not_dict_ignored() -> None:
    # data 是非 dict（漂移）-> 不抛错，回退顶层。
    payload = {"data": "oops", "limits": [{"type": "OK"}]}
    assert _extract_limits(payload) == [{"type": "OK"}]


def test_extract_limits_top_level_not_list_ignored() -> None:
    # 顶层 limits 非 list -> 返回空。
    assert _extract_limits({"limits": "not-a-list"}) == []


def test_extract_limits_data_limits_not_list_ignored_falls_back() -> None:
    # data.limits 非 list -> 回退顶层 limits。
    payload = {"data": {"limits": "bad"}, "limits": [{"type": "OK"}]}
    assert _extract_limits(payload) == [{"type": "OK"}]
