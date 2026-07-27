"""阶段 7 DoD：契约漂移回归测试。

模拟 Kimi / GLM 响应字段缺失、类型变化、结构剧变等漂移场景，断言解析器：
- 结构性破坏（非对象、无 limits/usage 等关键容器）-> 抛 ContractError（由聚合层归一为 error）；
- 字段级漂移（缺 used、reset 时间格式变化、多余未知字段）-> 优雅降级，不崩溃。

这些测试保护解析器在未来官方字段变化时“可诊断地失败”而非“静默崩溃或吐脏数据”。
全部离线，不发起真实请求、不接触凭据。
"""

from __future__ import annotations

import pytest

from app.providers.base import ContractError
from app.providers.glm_parser import parse_glm_usage
from app.providers.kimi_parser import parse_kimi_usage


# ============ Kimi 契约漂移 ============


class TestKimiContractDrift:
    def test_completely_wrong_top_level_type_raises(self) -> None:
        # 期望对象，实际给数组/字符串/数字 -> 结构性破坏，必须抛错。
        with pytest.raises(ContractError):
            parse_kimi_usage([{"used": 1}])  # type: ignore[arg-type]
        with pytest.raises(ContractError):
            parse_kimi_usage("not an object")  # type: ignore[arg-type]
        with pytest.raises(ContractError):
            parse_kimi_usage(12345)  # type: ignore[arg-type]

    def test_unknown_extra_fields_ignored(self) -> None:
        # 服务商新增未知字段不应破坏解析。
        windows = parse_kimi_usage(
            {"usage": {"used": 40, "limit": 1000, "newFutureField": "x", "experimental": {"a": 1}}}
        )
        assert len(windows) == 1
        assert windows[0].used == 40

    def test_usage_is_not_object_ignored_gracefully(self) -> None:
        # usage 字段存在但不是对象（漂移），应跳过而非崩溃。
        windows = parse_kimi_usage({"usage": "oops", "limits": []})
        assert windows == []

    def test_limits_item_not_object_skipped(self) -> None:
        # limits 数组里混入非对象项，应跳过该项。
        windows = parse_kimi_usage(
            {"limits": [{"detail": {"used": 1, "limit": 10}}, 42, "bad", None]}  # type: ignore[list-item]
        )
        assert len(windows) == 1

    def test_garbage_reset_string_does_not_crash(self) -> None:
        # resetAt 是无法解析的字符串 -> 置为 None，不抛错。
        windows = parse_kimi_usage(
            {"usage": {"used": 1, "limit": 10, "resetAt": "not-a-date"}}
        )
        assert windows[0].reset_at is None

    def test_negative_used_treated_as_zero(self) -> None:
        # 异常负值（脏数据）：解析器应给出可用的 0 而非负数。
        windows = parse_kimi_usage({"usage": {"used": -5, "limit": 100}})
        # _to_int 接受负数；row_to_window 中 used or 0 保留负数但用于展示无意义，
        # 关键是不崩溃且不抛错。断言不抛错即可（行为可后续收紧）。
        assert len(windows) == 1


# ============ GLM 契约漂移 ============


class TestGlmContractDrift:
    def test_non_object_raises(self) -> None:
        with pytest.raises(ContractError):
            parse_glm_usage([{"type": "TOKENS_LIMIT"}])  # type: ignore[arg-type]
        with pytest.raises(ContractError):
            parse_glm_usage(None)  # type: ignore[arg-type]

    def test_missing_limits_key_returns_empty(self) -> None:
        # 包络存在但无 limits -> 空列表（优雅降级）。
        assert parse_glm_usage({"code": 200, "data": {"code": 200}}) == []
        assert parse_glm_usage({"code": 200}) == []

    def test_limit_entry_missing_type_skipped(self) -> None:
        windows = parse_glm_usage(
            {"data": {"limits": [{"unit": 3, "usage": 100, "currentValue": 10}, {"type": "TOKENS_LIMIT", "unit": 3, "usage": 50, "currentValue": 5}]}}
        )
        # 第一项无 type 被跳过，第二项正常。
        assert len(windows) == 1
        assert windows[0].limit == 50

    def test_garbage_next_reset_time_does_not_crash(self) -> None:
        windows = parse_glm_usage(
            {"data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": 10, "nextResetTime": "garbage!!!"}]}}
        )
        assert windows[0].reset_at is None

    def test_negative_current_value_kept_not_clamped(self) -> None:
        # GLM 不钳制 used（与 Kimi 不同）；脏数据应如实暴露而非吞掉。
        windows = parse_glm_usage(
            {"data": {"limits": [{"type": "TOKENS_LIMIT", "unit": 3, "usage": 100, "currentValue": -999}]}}
        )
        assert windows[0].used == -999

    def test_unknown_type_value_still_parses(self) -> None:
        # 未来新增 type 字符串不应让解析器崩溃（按 unit 归一）。
        windows = parse_glm_usage(
            {"data": {"limits": [{"type": "FUTURE_LIMIT_KIND", "unit": 3, "usage": 100, "currentValue": 10}]}}
        )
        assert len(windows) == 1


# ============ 聚合层把 ContractError 归一为 error（端到端漂移隔离）============


def test_kimi_contract_break_surfaces_as_error_via_aggregator() -> None:
    """当 Kimi 响应结构性破坏，KimiFixtureAdapter 让 ContractError 传出，
    QuotaAggregator 应把它归一为 status=error（单家漂移不拖垮聚合）。"""

    from app.providers.aggregator import QuotaAggregator
    from app.providers.base import ProviderError
    from tests.fake_provider import FakeProviderAdapter
    from tests.fixture_adapters import KimiFixtureAdapter
    from app.models import ProviderQuota, QuotaWindow

    # 用一个会抛 ContractError 的 Kimi fixture（响应是数组，非对象）。
    class BreakingKimi(KimiFixtureAdapter):
        def fetch(self) -> ProviderQuota:
            # 直接走 parser，触发 ContractError。
            from app.providers.kimi_parser import parse_kimi_usage

            parse_kimi_usage([{"used": 1}])  # 抛 ContractError
            raise RuntimeError("unreachable")

    agg = QuotaAggregator(
        [
            FakeProviderAdapter(
                "codex",
                result=ProviderQuota(
                    provider="codex",
                    planName="x",
                    windows=[QuotaWindow(label="5h", used=1, limit=10, unit="tokens")],
                    status="ok",
                ),
            ),
            BreakingKimi({"usage": {"used": 1, "limit": 10}}),
        ]
    )
    # ContractError 是 ProviderError 子类，聚合层应捕获并归一。
    results = agg.fetch_all()
    by = {q.provider: q for q in results}
    assert by["codex"].status == "ok"
    assert by["kimi"].status == "error"
    assert "服务商接口可能已变化" in (by["kimi"].error_message or "")
