"""Offline JSONL stand-in for Codex app-server subprocess tests.

This helper contains no credentials and never opens a network connection.
"""

from __future__ import annotations

import json
import sys
import time


def _send(payload: object) -> None:
    print(json.dumps(payload, separators=(",", ":")), flush=True)


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "success"
    initialized = False

    for raw_line in sys.stdin:
        message = json.loads(raw_line)
        method = message.get("method")
        if method == "initialize":
            _send(
                {
                    "id": message["id"],
                    "result": {
                        "userAgent": "fake",
                        "codexHome": "fake",
                        "platformFamily": "windows",
                        "platformOs": "windows",
                    },
                }
            )
            continue
        if method == "initialized":
            initialized = True
            continue
        if method != "account/rateLimits/read":
            continue

        if not initialized:
            _send(
                {
                    "id": message["id"],
                    "error": {"code": -32000, "message": "Not initialized"},
                }
            )
            continue
        if mode == "timeout":
            time.sleep(2)
            continue
        if mode == "invalid_json":
            print("{broken", flush=True)
            continue
        if mode == "oversized_line":
            print('"' + ("x" * (1024 * 1024 + 1)) + '"', flush=True)
            continue
        if mode == "auth_error":
            _send(
                {
                    "id": message["id"],
                    "error": {"code": -32000, "message": "Login required"},
                }
            )
            continue

        # A notification before the response proves the client safely ignores
        # unrelated messages without retaining or logging their payloads.
        _send({"method": "account/rateLimits/updated", "params": {}})
        _send(
            {
                "id": message["id"],
                "result": {
                    "rateLimits": {
                        "limitId": "codex",
                        "planType": "pro",
                        "primary": {
                            "usedPercent": 25,
                            "windowDurationMins": 300,
                            "resetsAt": 1760000000,
                        },
                        "secondary": {
                            "usedPercent": 40,
                            "windowDurationMins": 10080,
                            "resetsAt": 1760500000,
                        },
                    }
                },
            }
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
