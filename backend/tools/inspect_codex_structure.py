"""一次性脱敏结构实验（已获用户授权，2026-07-23）。

只回答一个问题：官方 app-server 的 ``account/rateLimits/read`` 快照里
实际存在哪些字段（路径 + JSON 类型），credits/到期相关字段在不在。

安全约束（与 GLM 脱敏实验先例一致）：
- 只打印字段路径与类型名；绝不打印任何字段值（数字、字符串、时间一律不输出）。
- 原始响应不落盘、不写日志、不进 Git；进程结束后内存即释放。
- 凭据完全由官方 ``codex app-server`` 进程自管，本脚本不读 auth.json、不接触 token。
"""

from __future__ import annotations

import sys
from pathlib import Path

# 让脚本可以直接用 backend 包；不修改任何安装状态。
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.providers.base import ProviderError  # noqa: E402
from app.providers.codex_app_server import CodexAppServerClient  # noqa: E402

# 只关心这些词根是否出现在字段路径中（存在性判断，不取值）。
_KEYWORDS = ("credit", "expir", "subscri", "until", "plan", "renew", "remain")


def describe(value: object, path: str, out: list[tuple[str, str]]) -> None:
    """把 JSON 结构压平成 (路径, 类型) 列表；值本身从不进入列表。"""
    if isinstance(value, dict):
        out.append((path, "object"))
        for key in sorted(value):
            describe(value[key], f"{path}.{key}", out)
    elif isinstance(value, list):
        out.append((path, f"array[{len(value)}]"))
        # 数组元素只描述结构：合并所有 dict 元素的键集合，不取任何元素值。
        merged: dict[str, object] = {}
        for item in value:
            if isinstance(item, dict):
                for key, item_value in item.items():
                    merged.setdefault(key, item_value)
        if merged:
            describe(merged, f"{path}[]", out)
        elif value:
            describe(value[0], f"{path}[]", out)
    else:
        out.append((path, type(value).__name__))


def main() -> int:
    try:
        payload = CodexAppServerClient(timeout_seconds=12.0).read_rate_limits()
    except ProviderError as error:
        # 错误类型名本身不含凭据或响应内容，可以安全显示。
        print(f"调用失败：{type(error).__name__}")
        return 1

    flattened: list[tuple[str, str]] = []
    describe(payload, "$", flattened)

    print("=== 字段结构（仅路径 + 类型，无任何值） ===")
    for path, type_name in flattened:
        print(f"{type_name:<10} {path}")

    print("\n=== 关键词存在性（只回答是/否与路径） ===")
    for keyword in _KEYWORDS:
        hits = [path for path, _ in flattened if keyword in path.lower()]
        print(f"{keyword:<10} {'无' if not hits else '有：' + '，'.join(hits)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
