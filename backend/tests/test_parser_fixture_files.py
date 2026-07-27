"""基于官方源码衍生的脱敏 Fixture 文件回归测试（离线）。

读取 backend/fixtures/{kimi,glm}/*.json，验证解析器对每个官方衍生样例的解析结果。
这些 fixture 把“官方契约”固化为仓库内文件，未来官方字段变化时这些回归会先失败。
全部离线，无真实请求/凭据。
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.providers.glm_parser import parse_glm_usage
from app.providers.kimi_parser import parse_kimi_usage

KIMI_DIR = Path(__file__).resolve().parents[1] / "fixtures" / "kimi"
GLM_DIR = Path(__file__).resolve().parents[1] / "fixtures" / "glm"


def _load(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    data.pop("_comment", None)
    return data


# ---- Kimi fixtures ----


def test_kimi_fixture_typical() -> None:
    windows = parse_kimi_usage(_load(KIMI_DIR / "usage_typical.json"))
    assert [w.label for w in windows] == ["Weekly limit", "5h limit"]
    weekly = windows[0]
    assert weekly.used == 320000000
    assert weekly.limit == 1000000000
    assert weekly.reset_at is not None and weekly.reset_at.year == 2026


def test_kimi_fixture_remaining_fallback() -> None:
    windows = parse_kimi_usage(_load(KIMI_DIR / "usage_remaining_fallback.json"))
    assert windows[0].used == 800  # 1000 - 200
    assert windows[0].limit == 1000


def test_kimi_fixture_only_5h_limit() -> None:
    windows = parse_kimi_usage(_load(KIMI_DIR / "usage_only_5h_limit.json"))
    # 无 usage 汇总行，只有 limits 的 5h。
    assert len(windows) == 1
    assert windows[0].label == "5h limit"
    assert windows[0].used == 12000000
    assert windows[0].limit == 40000000


def test_kimi_fixture_nanosecond_reset_truncated() -> None:
    windows = parse_kimi_usage(_load(KIMI_DIR / "usage_nanosecond_reset.json"))
    assert windows[0].reset_at is not None
    # 纳秒 443553353 截断到微秒 443553。
    assert windows[0].reset_at.microsecond == 443553


# ---- GLM fixtures ----


def test_glm_fixture_typical_two_token_windows() -> None:
    windows = parse_glm_usage(_load(GLM_DIR / "usage_typical.json"))
    labels = [w.label for w in windows]
    assert "5 小时窗口" in labels
    assert "周窗口" in labels
    five_h = next(w for w in windows if w.label == "5 小时窗口")
    # usage=上限, currentValue=已用。
    assert five_h.limit == 40000000
    assert five_h.used == 12345678
    assert five_h.reset_at is not None and five_h.reset_at.year == 2025


def test_glm_fixture_with_details_and_time_limit() -> None:
    windows = parse_glm_usage(_load(GLM_DIR / "usage_with_details.json"))
    labels = [w.label for w in windows]
    # TOKENS_LIMIT 5h + TIME_LIMIT 月度。
    assert "5 小时窗口" in labels
    assert "月度/MCP 工具窗口" in labels
    # usageDetails 子明细本期不解析为额外窗口（只归一顶层 limit 条目）。
    five_h = next(w for w in windows if w.label == "5 小时窗口")
    assert five_h.used == 12345678
    time_window = next(w for w in windows if w.label == "月度/MCP 工具窗口")
    assert time_window.unit == "calls"
    assert time_window.reset_at is None  # nextResetTime: null


def test_glm_fixture_current_percentage_contract() -> None:
    windows = parse_glm_usage(_load(GLM_DIR / "usage_current_percentage.json"))
    assert [window.label for window in windows] == [
        "5 小时窗口",
        "周窗口",
        "月度/MCP 工具窗口",
    ]
    assert all(window.unit == "percent" for window in windows)
    assert [window.used for window in windows] == [75, 50, 25]


# ---- 所有 fixture 文件可被枚举（防止新增文件忘了写测试）----


@pytest.mark.parametrize(
    "path",
    sorted(KIMI_DIR.glob("*.json")),
    ids=lambda p: f"kimi/{p.name}",
)
def test_all_kimi_fixtures_parse_without_error(path: Path) -> None:
    windows = parse_kimi_usage(_load(path))
    # 每个 fixture 至少应被解析（可能为空，但不能抛错）。
    assert isinstance(windows, list)


@pytest.mark.parametrize(
    "path",
    sorted(GLM_DIR.glob("*.json")),
    ids=lambda p: f"glm/{p.name}",
)
def test_all_glm_fixtures_parse_without_error(path: Path) -> None:
    windows = parse_glm_usage(_load(path))
    assert isinstance(windows, list)


# ---- 契约形状：fixture 的原始结构必须符合官方解析器期望 ----


def test_kimi_fixtures_conform_to_object_envelope() -> None:
    """Kimi 顶层必须是对象，且至少含 usage(对象) 或 limits(数组) 之一。"""

    for path in sorted(KIMI_DIR.glob("*.json")):
        data = _load(path)
        assert isinstance(data, dict), f"{path.name}: 顶层必须是对象"
        has_usage = isinstance(data.get("usage"), dict)
        has_limits = isinstance(data.get("limits"), list)
        assert has_usage or has_limits, f"{path.name}: 至少含 usage 或 limits"


def test_glm_fixtures_conform_to_limits_envelope() -> None:
    """GLM 必须有 limits；条目符合当前 percentage 或历史绝对值契约。"""

    for path in sorted(GLM_DIR.glob("*.json")):
        data = _load(path)
        assert isinstance(data, dict), f"{path.name}: 顶层必须是对象"
        limits = None
        inner = data.get("data")
        if isinstance(inner, dict) and isinstance(inner.get("limits"), list):
            limits = inner["limits"]
        elif isinstance(data.get("limits"), list):
            limits = data["limits"]
        assert limits is not None, f"{path.name}: 缺 data.limits 或顶层 limits"
        for item in limits:
            if not isinstance(item, dict):
                continue
            # 官方解析器只处理有 type 的条目；fixture 里至少 type 应存在。
            assert "type" in item, f"{path.name}: limit 条目缺 type"
            has_current_percentage = (
                "percentage" in item
                and (
                    "number" in item
                    or item.get("unit") == 5
                    or "remaining" in item
                )
            )
            has_legacy_absolute = "usage" in item
            assert has_current_percentage or has_legacy_absolute, (
                f"{path.name}: limit 条目不符合当前 percentage 或历史绝对值契约"
            )


def test_glm_fixtures_usage_means_limit_not_used() -> None:
    """GLM 的 usage=上限、currentValue=已用（字段名误导）。fixture 必须遵守这一官方语义。"""

    for path in sorted(GLM_DIR.glob("*.json")):
        data = _load(path)
        limits = []
        inner = data.get("data")
        if isinstance(inner, dict) and isinstance(inner.get("limits"), list):
            limits = inner["limits"]
        elif isinstance(data.get("limits"), list):
            limits = data["limits"]
        for item in limits:
            if not isinstance(item, dict) or "usage" not in item:
                continue
            # usage（上限）应 >= currentValue（已用）；fixture 数据须自洽。
            usage = item["usage"]
            used = item.get("currentValue", 0)
            assert usage >= used, f"{path.name}: usage(上限) < currentValue(已用)，数据不自洽"
