"""Headless browser check for Flutter Web -> local FastAPI integration."""

from __future__ import annotations

import os
import time
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from playwright.sync_api import Error, sync_playwright


APP_URL = os.environ.get("QUOTA_WATCH_WEB_URL", "http://127.0.0.1:7357")
E2E_BACKEND_URL = os.environ.get(
    "QUOTA_WATCH_E2E_BACKEND_URL",
    "http://127.0.0.1:8000",
).rstrip("/")
SCREENSHOT = Path(
    os.environ.get(
        "QUOTA_WATCH_E2E_SCREENSHOT",
        r"D:\APPDEsign\docs\evidence\2026-07-25-stage10-safe-all-real.png",
    )
)


def is_all_real_quota_response(response) -> bool:
    """Match the API by parsed path/query instead of fragile string suffixes."""

    parsed = urlparse(response.url)
    return (
        parsed.path == "/api/v1/quotas"
        and parse_qs(parsed.query).get("scenario") == ["all_real"]
    )


def main() -> None:
    console_errors: list[str] = []
    page_errors: list[str] = []

    with sync_playwright() as playwright:
        try:
            browser = playwright.chromium.launch(channel="msedge", headless=True)
        except Error:
            browser = playwright.chromium.launch(headless=True)

        page = browser.new_page(viewport={"width": 1440, "height": 1000})

        # Keep the checked release build unchanged while routing its one quota
        # request to run_e2e.py's isolated, credential-free backend.
        def _route_quota_request(route) -> None:
            parsed = urlparse(route.request.url)
            rewritten = (
                f"{E2E_BACKEND_URL}{parsed.path}"
                f"{'?' + parsed.query if parsed.query else ''}"
            )
            route.continue_(url=rewritten)

        page.route("**/api/v1/quotas?**", _route_quota_request)

        # 仅记录“应用级”控制台错误。资源加载瞬时重试（如 ERR_CONNECTION_CLOSED、
        # net::ERR_*）在 Windows TIME_WAIT 或 keep-alive 关闭时常见，与 Flutter 应用是否
        # 正确无关；真正的 JS 异常由 pageerror 捕获并保持硬失败。
        def _on_console(message) -> None:
            if message.type != "error":
                return
            text = message.text or ""
            if "net::ERR_" in text or "ERR_CONNECTION_" in text:
                return
            console_errors.append(text)

        page.on("console", _on_console)
        page.on("pageerror", lambda error: page_errors.append(str(error)))

        last_error: Error | None = None
        response = None
        for attempt in range(3):
            try:
                # DOMContentLoaded only proves that index.html arrived. Flutter still
                # needs time to boot, so the API response is the real readiness gate.
                with page.expect_response(
                    is_all_real_quota_response,
                    timeout=60_000,
                ) as response_info:
                    page.goto(APP_URL, wait_until="domcontentloaded", timeout=60_000)
                response = response_info.value
                last_error = None
                break
            except Error as error:
                last_error = error
                if attempt < 2:
                    time.sleep(1)
        if last_error is not None:
            raise last_error
        if response is None:
            raise AssertionError("Browser did not request the partial quota scenario")

        # Flutter Web creates semantic DOM nodes after accessibility is enabled.
        placeholder = page.locator("flt-semantics-placeholder")
        placeholder.wait_for(state="attached", timeout=30_000)
        placeholder.evaluate("element => element.click()")
        page.wait_for_timeout(1000)
        SCREENSHOT.parent.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=str(SCREENSHOT), full_page=True)
        # Flutter 3.44 exposes non-interactive semantic labels as textContent
        # rather than aria-label, while buttons still use accessibility
        # attributes.  Match both forms when proving that the app rendered.
        page.locator("flt-semantics").filter(has_text="Codex").last.wait_for(
            state="attached",
            timeout=30_000,
        )

        if response.status != 200:
            raise AssertionError(f"Quota API returned HTTP {response.status}")

        payload = response.json()
        if len(payload) != 3:
            raise AssertionError(f"Expected 3 providers, got {len(payload)}")
        if [item["provider"] for item in payload] != ["codex", "kimi", "glm"]:
            raise AssertionError("Provider order does not match the unified contract")
        if any(item["status"] != "unknown" for item in payload):
            raise AssertionError("Safe E2E backend unexpectedly queried a real provider")

        rendered = page.locator("body").inner_text()
        semantic_nodes = page.locator("flt-semantics, [aria-label]").all()
        semantic_text = "\n".join(
            (
                item.get_attribute("aria-label")
                or item.text_content()
                or ""
            )
            for item in semantic_nodes
        )
        searchable = f"{rendered}\n{semantic_text}"
        for expected in ("Codex", "Kimi", "GLM", "真实查询未启用"):
            if expected not in searchable:
                raise AssertionError(f"Rendered UI is missing: {expected}")

        # 发布包字体清单：证明随包中文字体子集真的进了 build/web。
        # 注意：FontManifest 只能证明“字体被打包、文字数据正确”，
        # 不能证明 Canvas 画出了中文字形，因此最终仍需人工查看截图。
        parsed_base = urlparse(APP_URL)
        manifest_url = f"{parsed_base.scheme}://{parsed_base.netloc}/assets/FontManifest.json"
        with page.expect_response(
            lambda response: urlparse(response.url).path == "/assets/FontManifest.json",
            timeout=15_000,
        ) as manifest_info:
            page.goto(manifest_url, wait_until="domcontentloaded", timeout=15_000)
        manifest = manifest_info.value.json()
        noto_entry = next(
            (entry for entry in manifest if entry.get("family") == "NotoSansSCSubset"),
            None,
        )
        if noto_entry is None:
            raise AssertionError("FontManifest.json missing family 'NotoSansSCSubset'")
        noto_assets = [
            asset.get("asset") for asset in noto_entry.get("fonts", [])
        ]
        if "assets/fonts/NotoSansSC-QuotaWatchSubset.ttf" not in noto_assets:
            raise AssertionError(
                f"FontManifest.json NotoSansSCSubset missing subset asset: {noto_assets}"
            )

        if page_errors:
            raise AssertionError(f"Page errors: {page_errors}")
        if console_errors:
            raise AssertionError(f"Console errors: {console_errors}")

        print("E2E passed: Flutter Web requested isolated FastAPI all_real data.")
        print(f"Screenshot: {SCREENSHOT}")
        browser.close()


if __name__ == "__main__":
    main()
