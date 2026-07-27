"""Start both local servers, run the browser check, and always stop them."""

from __future__ import annotations

import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_ROOT = REPO_ROOT / "backend"
WEB_ROOT = REPO_ROOT / "quota_watch" / "build" / "web"
BACKEND_PYTHON = BACKEND_ROOT / ".venv" / "Scripts" / "python.exe"
BROWSER_CHECK = Path(__file__).with_name("e2e_web_check.py")
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


def find_free_loopback_port() -> int:
    """Reserve an available port number for the short-lived test process."""

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def wait_for(url: str) -> None:
    last_error: Exception | None = None
    for _ in range(40):
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                if response.status == 200:
                    return
        except Exception as error:  # noqa: BLE001 - preserve the final startup error
            last_error = error
            time.sleep(0.5)
    raise RuntimeError(f"Server did not become ready: {url}") from last_error


def stop(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def main() -> None:
    backend_port = find_free_loopback_port()
    web_port = find_free_loopback_port()
    child_environment = os.environ.copy()
    for name in (
        "QUOTA_WATCH_CODEX_REAL",
        "QUOTA_WATCH_KIMI_REAL",
        "QUOTA_WATCH_KIMI_API_KEY",
        "KIMI_CODING_API_KEY",
        "QUOTA_WATCH_GLM_REAL",
        "QUOTA_WATCH_GLM_API_KEY",
        "GLM_API_KEY",
    ):
        child_environment.pop(name, None)

    # The released Web build normally points at port 8000.  The browser check
    # rewrites only its quota request to this isolated port, so an already
    # running desktop instance is never stopped or queried.
    with tempfile.TemporaryDirectory(prefix="quota-watch-e2e-") as temp_root:
        metadata_path = Path(temp_root) / "credential_profiles.json"
        bootstrap = (
            "import sys;"
            "from pathlib import Path;"
            "from app import main;"
            "from app.credential_profiles import "
            "CredentialProfileManager,MemorySecretStore;"
            "main._credential_profiles=CredentialProfileManager("
            "secret_store=MemorySecretStore(),metadata_path=Path(sys.argv[2]));"
            "import uvicorn;"
            "uvicorn.run(main.app,host='127.0.0.1',port=int(sys.argv[1]),"
            "log_level='warning')"
        )
        backend = subprocess.Popen(
            [
                str(BACKEND_PYTHON),
                "-c",
                bootstrap,
                str(backend_port),
                str(metadata_path),
            ],
            cwd=BACKEND_ROOT,
            env=child_environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=CREATE_NO_WINDOW,
        )
        web = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "http.server",
                str(web_port),
                "--bind",
                "127.0.0.1",
                "--directory",
                str(WEB_ROOT),
            ],
            cwd=REPO_ROOT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=CREATE_NO_WINDOW,
        )

        try:
            wait_for(f"http://127.0.0.1:{backend_port}/health")
            wait_for(f"http://127.0.0.1:{web_port}/")
            check_environment = child_environment.copy()
            check_environment["QUOTA_WATCH_WEB_URL"] = (
                f"http://127.0.0.1:{web_port}"
            )
            check_environment["QUOTA_WATCH_E2E_BACKEND_URL"] = (
                f"http://127.0.0.1:{backend_port}"
            )
            subprocess.run(
                [sys.executable, str(BROWSER_CHECK)],
                check=True,
                env=check_environment,
            )
        finally:
            stop(web)
            stop(backend)


if __name__ == "__main__":
    main()
