"""Windows-only lifecycle tests for the one-click Quota Watch launcher."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = REPO_ROOT / "scripts" / "start_quota_watch.ps1"
WRAPPER = REPO_ROOT / "启动 Quota Watch.cmd"
EXE_SOURCE = REPO_ROOT / "scripts" / "launcher" / "QuotaWatchLauncher.cs"
EXE_BUILD_SCRIPT = REPO_ROOT / "scripts" / "build_windows_launcher.ps1"
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)

pytestmark = pytest.mark.skipif(
    os.name != "nt",
    reason="The launcher intentionally targets Windows PowerShell.",
)


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def _build_fake_desktop_exe(tmp_path: Path) -> Path:
    source = tmp_path / "FakeDesktop.cs"
    executable = tmp_path / "fake-desktop.exe"
    source.write_text(
        "using System;\n"
        "using System.IO;\n"
        "using System.Threading;\n"
        "internal static class FakeDesktop\n"
        "{\n"
        "    [STAThread]\n"
        "    private static int Main()\n"
        "    {\n"
        "        string marker = Environment.GetEnvironmentVariable(\n"
        '            "QUOTA_WATCH_TEST_DESKTOP_MARKER"\n'
        "        );\n"
        "        File.WriteAllText(marker, \"started\");\n"
        "        string environmentMarker = Environment.GetEnvironmentVariable(\n"
        '            "QUOTA_WATCH_TEST_ENVIRONMENT_MARKER"\n'
        "        );\n"
        "        if (!String.IsNullOrWhiteSpace(environmentMarker))\n"
        "        {\n"
        "            File.WriteAllText(\n"
        "                environmentMarker,\n"
        '                "KIMI_CODING_API_KEY=" +\n'
        '                (Environment.GetEnvironmentVariable("KIMI_CODING_API_KEY") ?? "") +\n'
        '                "\\nGLM_API_KEY=" +\n'
        '                (Environment.GetEnvironmentVariable("GLM_API_KEY") ?? "") +\n'
        '                "\\nQUOTA_WATCH_KIMI_API_KEY=" +\n'
        '                (Environment.GetEnvironmentVariable("QUOTA_WATCH_KIMI_API_KEY") ?? "") +\n'
        '                "\\nQUOTA_WATCH_GLM_API_KEY=" +\n'
        '                (Environment.GetEnvironmentVariable("QUOTA_WATCH_GLM_API_KEY") ?? "")\n'
        "            );\n"
        "        }\n"
        "        // Stay alive past the one-second bootstrap observation so\n"
        "        // the C# launcher must supervise an externally started PID.\n"
        "        Thread.Sleep(1500);\n"
        "        return 0;\n"
        "    }\n"
        "}\n",
        encoding="utf-8",
    )
    windows_directory = Path(os.environ["WINDIR"])
    compiler_candidates = [
        Path(
            r"C:\Program Files\Microsoft Visual Studio"
            r"\18\Community\MSBuild\Current\Bin\Roslyn\csc.exe"
        ),
        windows_directory
        / "Microsoft.NET"
        / "Framework64"
        / "v4.0.30319"
        / "csc.exe",
        windows_directory
        / "Microsoft.NET"
        / "Framework"
        / "v4.0.30319"
        / "csc.exe",
    ]
    compiler = next(
        (candidate for candidate in compiler_candidates if candidate.is_file()),
        None,
    )
    assert compiler is not None, "C# compiler is required for launcher tests"
    build = subprocess.run(
        [
            str(compiler),
            "/nologo",
            "/target:winexe",
            f"/out:{executable}",
            str(source),
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        creationflags=CREATE_NO_WINDOW,
        check=False,
    )
    assert build.returncode == 0, build.stderr
    return executable


def _run_launcher(
    *arguments: str,
    timeout: int = 60,
    extra_environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    # Obvious markers prove that validation/smoke-test output never prints values.
    environment["KIMI_CODING_API_KEY"] = "test-kimi-launcher-secret-marker"
    environment["GLM_API_KEY"] = "test-glm-launcher-secret-marker"
    if extra_environment:
        environment.update(extra_environment)
    return subprocess.run(
        [
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(LAUNCHER),
            *arguments,
        ],
        cwd=REPO_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        # PowerShell 在中文 Windows 上可能输出 GBK 编码的报错文案，
        # 而测试进程可能运行在 UTF-8 模式（PYTHONUTF8）。显式指定 errors="replace"
        # 避免解码异常淹没真正的退出码断言。
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        creationflags=CREATE_NO_WINDOW,
        check=False,
    )


class _ProbeHandler(BaseHTTPRequestHandler):
    quota_watch = False

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if self.quota_watch and self.path == "/health":
            payload = {"status": "ok"}
        elif self.quota_watch and self.path == "/openapi.json":
            payload = {"info": {"title": "Quota Watch Local Backend"}}
        else:
            payload = {"status": "other"}
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, _format: str, *_args: object) -> None:
        return


def _start_probe(
    *,
    quota_watch: bool,
) -> tuple[ThreadingHTTPServer, threading.Thread]:
    handler = type("ConfiguredProbeHandler", (_ProbeHandler,), {})
    handler.quota_watch = quota_watch
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def test_validate_only_checks_dependencies_without_printing_keys() -> None:
    port = _free_port()

    result = _run_launcher("-ValidateOnly", "-BackendPort", str(port))

    assert result.returncode == 0, result.stderr
    assert "Launcher validation passed" in result.stdout
    assert "test-kimi-launcher-secret-marker" not in result.stdout + result.stderr
    assert "test-glm-launcher-secret-marker" not in result.stdout + result.stderr


def test_smoke_test_starts_offline_backend_and_cleans_up() -> None:
    port = _free_port()

    result = _run_launcher(
        "-Desktop",
        "-SmokeTest",
        "-BackendPort",
        str(port),
    )

    assert result.returncode == 0, result.stderr
    assert "Smoke test forced every real provider off" in result.stdout
    assert "Offline smoke test passed" in result.stdout
    assert "test-kimi-launcher-secret-marker" not in result.stdout + result.stderr
    assert "test-glm-launcher-secret-marker" not in result.stdout + result.stderr
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client:
        assert client.connect_ex(("127.0.0.1", port)) != 0


def test_validate_only_reuses_existing_quota_watch_backend() -> None:
    server, thread = _start_probe(quota_watch=True)
    try:
        port = int(server.server_address[1])

        result = _run_launcher("-ValidateOnly", "-BackendPort", str(port))

        assert result.returncode == 0, result.stderr
        assert "reusable Quota Watch backend" in result.stdout
        assert thread.is_alive()
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_unrelated_port_owner_is_not_stopped() -> None:
    server, thread = _start_probe(quota_watch=False)
    try:
        port = int(server.server_address[1])

        result = _run_launcher("-ValidateOnly", "-BackendPort", str(port))

        assert result.returncode == 1
        assert "occupied by another program" in result.stderr
        assert thread.is_alive()
        with socket.create_connection(("127.0.0.1", port), timeout=2):
            pass
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def test_double_click_wrapper_calls_the_powershell_launcher() -> None:
    wrapper = WRAPPER.read_text(encoding="utf-8")

    assert "powershell.exe" in wrapper
    assert r"scripts\start_quota_watch.ps1" in wrapper
    assert "%~dp0" in wrapper


def test_exe_launcher_source_uses_lightweight_runtime_handoff() -> None:
    source = EXE_SOURCE.read_text(encoding="utf-8")
    build_script = EXE_BUILD_SCRIPT.read_text(encoding="utf-8-sig")
    powershell_source = LAUNCHER.read_text(encoding="utf-8-sig")

    assert "start_quota_watch.ps1" in source
    assert "CanUseBootstrapRuntime" in source
    assert "RunBootstrapRuntime" in source
    assert "-Desktop -BootstrapDesktop" in source
    assert "-RuntimeHandoffPath" in source
    assert "TryParseRuntimeHandoff" in source
    assert "backendStartedUtcTicks" in source
    assert "WaitForExternalProcessExit" in source
    assert "GetExitCodeProcess" in source
    assert "StopOwnedBackend" in source
    assert "StopProcessTree" in source
    assert "powershell.exe" in source
    assert "CreateNoWindow = true" in source
    assert "WindowStyle = ProcessWindowStyle.Hidden" in source
    # Redirected output remains only for short-lived developer fallbacks.
    assert "RedirectStandardOutput = true" in source
    assert "MessageBox.Show" in source
    assert "QuotaWatchDesktopLauncher" in source
    assert "QuotaWatchDesktopLauncherTest" in source
    assert "new Mutex" in source
    assert "ActivateExistingQuotaWatch()" in source
    assert "mutex.WaitOne(250)" in source
    assert "AbandonedMutexException" in source
    assert "Quota Watch is still starting or shutting down." in source
    assert 'Process.GetProcessesByName("quota_watch")' in source
    assert "EnumChildWindows(" in source
    assert "FLUTTER_RUNNER_WIN32_WINDOW" in source
    assert "TrayCallbackMessage" in source
    assert "LeftButtonUpMessage" in source
    assert "PostMessage(" in source
    assert "QuotaWatchLauncher.cs" in build_script
    assert "quota_watch_icon.ico" in build_script
    assert "/target:winexe" in build_script
    assert "/reference:System.Windows.Forms.dll" in build_script
    assert "[switch]$BootstrapDesktop" in powershell_source
    assert "[string]$RuntimeHandoffPath" in powershell_source
    assert r".venv\Scripts\pythonw.exe" in powershell_source
    assert "Start-SafeDesktopProcess" in powershell_source
    assert "QUOTA_WATCH_RUNTIME_HANDOFF" in powershell_source
    assert "Desktop runtime handed off to the GUI launcher" in powershell_source


def test_built_exe_launcher_forwards_to_desktop_lifecycle(
    tmp_path: Path,
) -> None:
    port = _free_port()
    launcher_exe = tmp_path / "quota-watch-launcher.exe"
    marker = tmp_path / "exe-desktop-started.txt"
    environment_marker = tmp_path / "exe-desktop-environment.txt"
    fake_desktop = _build_fake_desktop_exe(tmp_path)
    build = subprocess.run(
        [
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(EXE_BUILD_SCRIPT),
            "-OutputPath",
            str(launcher_exe),
            "-TestBuild",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        creationflags=CREATE_NO_WINDOW,
        check=False,
    )
    assert build.returncode == 0, build.stderr
    executable = launcher_exe.read_bytes()
    pe_offset = int.from_bytes(executable[0x3C:0x40], "little")
    subsystem_offset = pe_offset + 24 + 68
    subsystem = int.from_bytes(
        executable[subsystem_offset : subsystem_offset + 2],
        "little",
    )
    assert subsystem == 2  # IMAGE_SUBSYSTEM_WINDOWS_GUI

    environment = os.environ.copy()
    environment["KIMI_CODING_API_KEY"] = "test-kimi-launcher-secret-marker"
    environment["GLM_API_KEY"] = "test-glm-launcher-secret-marker"
    environment["QUOTA_WATCH_TEST_DESKTOP_MARKER"] = str(marker)
    environment["QUOTA_WATCH_TEST_ENVIRONMENT_MARKER"] = str(
        environment_marker
    )
    result = subprocess.run(
        [
            str(launcher_exe),
            "-BackendPort",
            str(port),
            "-DesktopExecutable",
            str(fake_desktop),
        ],
        cwd=REPO_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        creationflags=CREATE_NO_WINDOW,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert marker.read_text(encoding="utf-8").strip() == "started"
    child_environment = environment_marker.read_text(encoding="utf-8")
    assert "test-kimi-launcher-secret-marker" not in child_environment
    assert "test-glm-launcher-secret-marker" not in child_environment
    assert child_environment.splitlines() == [
        "KIMI_CODING_API_KEY=",
        "GLM_API_KEY=",
        "QUOTA_WATCH_KIMI_API_KEY=",
        "QUOTA_WATCH_GLM_API_KEY=",
    ]
    assert "Offline smoke test" not in result.stdout
    assert "test-kimi-launcher-secret-marker" not in result.stdout + result.stderr
    assert "test-glm-launcher-secret-marker" not in result.stdout + result.stderr
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client:
        assert client.connect_ex(("127.0.0.1", port)) != 0


def test_desktop_mode_starts_backend_and_cleans_up_after_frontend_exit(
    tmp_path: Path,
) -> None:
    port = _free_port()
    marker = tmp_path / "desktop-started.txt"
    fake_desktop = tmp_path / "fake-desktop.cmd"
    fake_desktop.write_text(
        "@echo off\r\n"
        '> "%QUOTA_WATCH_TEST_DESKTOP_MARKER%" echo started\r\n'
        "exit /b 0\r\n",
        encoding="ascii",
    )

    result = _run_launcher(
        "-Desktop",
        "-BackendPort",
        str(port),
        "-DesktopExecutable",
        str(fake_desktop),
        extra_environment={
            "QUOTA_WATCH_TEST_DESKTOP_MARKER": str(marker),
        },
    )

    assert result.returncode == 0, result.stderr
    assert marker.read_text(encoding="utf-8").strip() == "started"
    assert "Starting the Windows desktop app" in result.stdout
    assert "test-kimi-launcher-secret-marker" not in result.stdout + result.stderr
    assert "test-glm-launcher-secret-marker" not in result.stdout + result.stderr
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client:
        assert client.connect_ex(("127.0.0.1", port)) != 0


def test_daily_mode_starts_backend_and_passes_all_real_flutter_arguments(
    tmp_path: Path,
) -> None:
    port = _free_port()
    arguments_file = tmp_path / "flutter-arguments.txt"
    fake_flutter = tmp_path / "fake-flutter.cmd"
    fake_flutter.write_text(
        "@echo off\r\n"
        "> \"%QUOTA_WATCH_TEST_ARGUMENTS_FILE%\" echo %*\r\n"
        "exit /b 0\r\n",
        encoding="ascii",
    )

    result = _run_launcher(
        "-BackendPort",
        str(port),
        "-FlutterCommand",
        str(fake_flutter),
        extra_environment={
            "QUOTA_WATCH_TEST_ARGUMENTS_FILE": str(arguments_file),
        },
    )

    assert result.returncode == 0, result.stderr
    arguments = arguments_file.read_text(encoding="utf-8").strip()
    assert "run -d edge" in arguments
    assert "--dart-define=QUOTA_DATA_MODE=backend" in arguments
    assert "--dart-define=QUOTA_SCENARIO=all_real" in arguments
    assert (
        f"--dart-define=QUOTA_BACKEND_URL=http://127.0.0.1:{port}"
        in arguments
    )
    assert "test-kimi-launcher-secret-marker" not in result.stdout + result.stderr
    assert "test-glm-launcher-secret-marker" not in result.stdout + result.stderr
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client:
        assert client.connect_ex(("127.0.0.1", port)) != 0
