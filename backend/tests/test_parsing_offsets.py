"""_parsing 非零 UTC 偏移回归测试（阶段 6/7）。

锁定截断纳秒时不丢失时区偏移（此前 +08:00/+05:30 会被错误剥离，导致本地时间被当作 UTC）。
对中国区 GLM/Kimi 响应（可能带本地偏移）至关重要。全部离线。
"""

from __future__ import annotations

from datetime import timezone

import pytest

from app.providers import _parsing


def test_truncate_preserves_plus_8_offset() -> None:
    assert _parsing.truncate_subseconds("2025-12-23T05:24:18.443553353+08:00") == (
        "2025-12-23T05:24:18.443553+08:00"
    )


def test_truncate_preserves_negative_offset() -> None:
    assert _parsing.truncate_subseconds("2025-12-23T05:24:18.123456789-05:30") == (
        "2025-12-23T05:24:18.123456-05:30"
    )


def test_truncate_preserves_short_offset() -> None:
    # +0800（无冒号）形式也应保留。
    assert _parsing.truncate_subseconds("2025-12-23T05:24:18.999999999+0800") == (
        "2025-12-23T05:24:18.999999+0800"
    )


def test_parse_nonzero_offset_yields_correct_utc_moment() -> None:
    """+08:00 的 05:24:18 等于 UTC 21:24:18（前一天）。"""

    dt = _parsing.parse_iso_to_utc("2025-12-23T05:24:18.443553+08:00")
    assert dt is not None
    # 转为 UTC 后应为前一天 21:24:18。
    assert dt.utcoffset() is not None
    utc = dt.astimezone(timezone.utc)
    assert utc.day == 22
    assert utc.hour == 21
    assert utc.minute == 24


def test_parse_zero_offset_unchanged() -> None:
    dt = _parsing.parse_iso_to_utc("2025-12-23T05:24:18.443553353+00:00")
    assert dt is not None
    utc = dt.astimezone(timezone.utc)
    assert utc.day == 23
    assert utc.hour == 5


def test_parse_zulu_unchanged() -> None:
    dt = _parsing.parse_iso_to_utc("2025-12-23T05:24:18.999999999Z")
    assert dt is not None
    assert dt.astimezone(timezone.utc).hour == 5


@pytest.mark.parametrize(
    "iso, expected_offset_minutes",
    [
        ("2025-12-23T05:24:18.1+08:00", 480),
        ("2025-12-23T05:24:18.1+05:30", 330),
        ("2025-12-23T05:24:18.1-05:00", -300),
        ("2025-12-23T05:24:18.1+00:00", 0),
    ],
)
def test_offset_preserved_after_truncation(iso: str, expected_offset_minutes: int) -> None:
    dt = _parsing.parse_iso_to_utc(iso)
    assert dt is not None
    offset = dt.utcoffset()
    assert offset is not None
    assert int(offset.total_seconds() // 60) == expected_offset_minutes


def test_cross_parser_offset_consistency() -> None:
    """Kimi 与 GLM 解析同一带偏移 ISO 字符串结果一致。"""

    from app.providers.glm_parser import _parse_reset_time
    from app.providers.kimi_parser import _parse_iso

    iso = "2025-12-23T05:24:18.443553353+08:00"
    kimi_dt = _parse_iso(iso)
    glm_dt = _parse_reset_time(iso)
    assert kimi_dt is not None and glm_dt is not None
    assert kimi_dt == glm_dt
