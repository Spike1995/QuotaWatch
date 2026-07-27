"""对本地后端路由输出做“键路径 + 类型”级脱敏检查（不落盘、不打印任何值）。

用途：验证真实场景路由（如 codex_real）的 JSON 里是否存在预期字段，
同时保证响应中的数字、字符串、时间一律不进入终端、日志或文件。

用法：
    backend/.venv/Scripts/python.exe backend/tools/inspect_route_structure.py \
        http://127.0.0.1:8791/api/v1/quotas?scenario=codex_real
"""

from __future__ import annotations

import json
import sys
import urllib.request


def describe(value: object, path: str, out: list[tuple[str, str]]) -> None:
    """把 JSON 结构压平成 (路径, 类型) 列表；值本身从不进入列表。"""
    if isinstance(value, dict):
        out.append((path, "object"))
        for key in sorted(value):
            describe(value[key], f"{path}.{key}", out)
    elif isinstance(value, list):
        out.append((path, f"array[{len(value)}]"))
        for index, item in enumerate(value):
            describe(item, f"{path}[{index}]", out)
    else:
        out.append((path, type(value).__name__))


def main() -> int:
    if len(sys.argv) != 2:
        print("用法：inspect_route_structure.py <本地URL>")
        return 2
    url = sys.argv[1]
    if not url.startswith(("http://127.0.0.1", "http://localhost")):
        # 脱敏工具只允许打本机地址，避免被误用于外发请求。
        print("只允许本机 URL")
        return 2

    with urllib.request.urlopen(url, timeout=40) as response:
        print(f"HTTP {response.status}")
        payload = json.load(response)

    flattened: list[tuple[str, str]] = []
    describe(payload, "$", flattened)
    for path, type_name in flattened:
        print(f"{type_name:<10} {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
