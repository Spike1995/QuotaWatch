"""Guards for the clean production Python environment."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
LOCK_FILE = REPO_ROOT / "backend" / "requirements-runtime.lock"
BUILD_SCRIPT = REPO_ROOT / "scripts" / "build_runtime_venv.ps1"
LAUNCH_SCRIPT = REPO_ROOT / "scripts" / "start_quota_watch.ps1"
GITIGNORE = REPO_ROOT / ".gitignore"


def _locked_names() -> set[str]:
    names: set[str] = set()
    for raw_line in LOCK_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        names.add(line.split("==", 1)[0].lower().replace("_", "-"))
    return names


def test_runtime_lock_contains_only_pinned_runtime_dependencies() -> None:
    lines = [
        line.strip()
        for line in LOCK_FILE.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]
    assert lines
    assert all("==" in line for line in lines)

    names = _locked_names()
    assert {"fastapi", "httpx", "pydantic", "uvicorn"} <= names
    assert {"pillow", "pytest", "pygments", "pip"}.isdisjoint(names)


def test_runtime_builder_has_bounded_delete_and_import_validation() -> None:
    source = BUILD_SCRIPT.read_text(encoding="utf-8-sig")

    assert "Assert-ExactRuntimePath" in source
    assert "'.venv-runtime'" in source
    assert "Remove-Item -LiteralPath $resolved -Recurse -Force" in source
    assert "--without-pip" in source
    assert "--no-compile" in source
    assert "--no-deps" in source
    assert "requirements-runtime.lock" in source
    assert "Runtime imports passed." in source
    assert "PYTHONDONTWRITEBYTECODE" in source


def test_generated_runtime_environment_is_ignored() -> None:
    source = GITIGNORE.read_text(encoding="utf-8-sig")

    assert ".venv-runtime/" in source


def test_backend_child_does_not_write_bytecode_into_runtime() -> None:
    source = LAUNCH_SCRIPT.read_text(encoding="utf-8-sig")

    environment_method = source.split(
        "function Set-BackendChildEnvironment",
        1,
    )[1].split("function Start-OwnedBackend", 1)[0]
    assert "'PYTHONDONTWRITEBYTECODE'" in environment_method
    assert "-Value '1'" in environment_method
    backend_arguments = source.split(
        "$arguments = @(",
        1,
    )[1].split(")", 1)[0]
    assert "'-B'" in backend_arguments
    assert backend_arguments.index("'-B'") < backend_arguments.index("'-m'")
