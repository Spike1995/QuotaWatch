"""Static Android boundary checks; no SDK, device, or network is required."""

from __future__ import annotations

from pathlib import Path
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[2]
ANDROID = ROOT / "quota_watch" / "android"
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


def test_android_manifest_has_network_permission_and_product_identity() -> None:
    manifest = ElementTree.parse(
        ANDROID / "app" / "src" / "main" / "AndroidManifest.xml",
    ).getroot()
    permissions = {
        item.attrib[f"{ANDROID_NS}name"]
        for item in manifest.findall("uses-permission")
    }
    application = manifest.find("application")

    assert "android.permission.INTERNET" in permissions
    assert application is not None
    assert application.attrib[f"{ANDROID_NS}label"] == "Quota Watch"
    assert (
        application.attrib[f"{ANDROID_NS}networkSecurityConfig"]
        == "@xml/network_security_config"
    )

    gradle = (ANDROID / "app" / "build.gradle.kts").read_text(encoding="utf-8")
    assert 'applicationId = "com.quotawatch.app"' in gradle
    assert 'namespace = "com.quotawatch.app"' in gradle


def test_android_cleartext_is_loopback_only() -> None:
    config = ElementTree.parse(
        ANDROID
        / "app"
        / "src"
        / "main"
        / "res"
        / "xml"
        / "network_security_config.xml",
    ).getroot()
    base = config.find("base-config")
    domains = {
        domain.text
        for domain in config.findall("./domain-config/domain")
    }

    assert base is not None
    assert base.attrib["cleartextTrafficPermitted"] == "false"
    assert domains == {"127.0.0.1", "localhost"}


def test_android_sources_do_not_embed_provider_secret_variables() -> None:
    forbidden = (
        "QUOTA_WATCH_KIMI_API_KEY",
        "QUOTA_WATCH_GLM_API_KEY",
        "KIMI_CODING_API_KEY",
        "GLM_API_KEY",
    )
    for path in (ANDROID / "app" / "src").rglob("*"):
        if path.is_file():
            text = path.read_text(encoding="utf-8", errors="ignore")
            assert not any(marker in text for marker in forbidden), path
