"""Production GUI launcher tests after the single-process Dart migration."""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EXE_SOURCE = REPO_ROOT / "scripts" / "launcher" / "QuotaWatchLauncher.cs"
EXE_BUILD_SCRIPT = REPO_ROOT / "scripts" / "build_windows_launcher.ps1"
CREATE_NO_WINDOW = 0x08000000


def _compiler() -> Path:
    windows_directory = Path(os.environ["WINDIR"])
    candidates = [
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
    compiler = next((path for path in candidates if path.is_file()), None)
    assert compiler is not None, "C# compiler is required for launcher tests"
    return compiler


def _build_fake_desktop(tmp_path: Path) -> Path:
    source = tmp_path / "FakeDesktop.cs"
    executable = tmp_path / "fake-desktop.exe"
    source.write_text(
        "using System;\n"
        "using System.IO;\n"
        "using System.Threading;\n"
        "internal static class FakeDesktop {\n"
        "  private static int Main() {\n"
        "    File.WriteAllText(\n"
        '      Environment.GetEnvironmentVariable("QW_TEST_MARKER"),\n'
        '      "started"\n'
        "    );\n"
        "    File.WriteAllText(\n"
        '      Environment.GetEnvironmentVariable("QW_TEST_ENV_MARKER"),\n'
        '      "KIMI_CODING_API_KEY=" +\n'
        '      (Environment.GetEnvironmentVariable("KIMI_CODING_API_KEY") ?? "") +\n'
        '      "\\nGLM_API_KEY=" +\n'
        '      (Environment.GetEnvironmentVariable("GLM_API_KEY") ?? "") +\n'
        '      "\\nQUOTA_WATCH_KIMI_API_KEY=" +\n'
        '      (Environment.GetEnvironmentVariable("QUOTA_WATCH_KIMI_API_KEY") ?? "") +\n'
        '      "\\nQUOTA_WATCH_GLM_API_KEY=" +\n'
        '      (Environment.GetEnvironmentVariable("QUOTA_WATCH_GLM_API_KEY") ?? "")\n'
        "    );\n"
        "    Thread.Sleep(3000);\n"
        "    return 0;\n"
        "  }\n"
        "}\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        [
            str(_compiler()),
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
    assert result.returncode == 0, result.stderr
    return executable


def _build_launcher(tmp_path: Path) -> Path:
    executable = tmp_path / "quota-watch-launcher.exe"
    result = subprocess.run(
        [
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(EXE_BUILD_SCRIPT),
            "-OutputPath",
            str(executable),
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
    assert result.returncode == 0, result.stderr
    return executable


def test_launcher_source_is_direct_single_process_and_has_safe_failure_path() -> None:
    source = EXE_SOURCE.read_text(encoding="utf-8")

    assert "FindDesktopExecutable" in source
    assert '"Release"' in source
    assert '"quota_watch.exe"' in source
    assert "Process.Start(startInfo)" in source
    assert "desktop.WaitForExit(1500)" in source
    assert "CreateNoWindow = true" in source
    assert "UseShellExecute = false" in source
    assert "ClearProviderEnvironment" in source
    assert "MessageBox.Show" in source
    assert "WriteDiagnosticLog" in source
    assert "QuotaWatchDesktopLauncher" in source
    assert "new Mutex" in source
    assert "ActivateExistingQuotaWatch" in source
    assert 'Process.GetProcessesByName("quota_watch")' in source
    assert "FLUTTER_RUNNER_WIN32_WINDOW" in source
    assert "PostMessage(" in source
    assert "powershell.exe" not in source.lower()
    assert "start_quota_watch.ps1" not in source
    assert "uvicorn" not in source.lower()
    assert "StartOwnedBackend" not in source
    assert "StopOwnedBackend" not in source
    assert "RuntimeHandoff" not in source


def test_launcher_builds_as_a_windows_gui_executable(tmp_path: Path) -> None:
    executable = _build_launcher(tmp_path).read_bytes()
    pe_offset = int.from_bytes(executable[0x3C:0x40], "little")
    subsystem_offset = pe_offset + 24 + 68
    subsystem = int.from_bytes(
        executable[subsystem_offset : subsystem_offset + 2],
        "little",
    )
    assert subsystem == 2


def test_built_launcher_starts_only_desktop_then_exits_and_clears_keys(
    tmp_path: Path,
) -> None:
    launcher = _build_launcher(tmp_path)
    desktop = _build_fake_desktop(tmp_path)
    marker = tmp_path / "desktop-started.txt"
    environment_marker = tmp_path / "desktop-environment.txt"
    environment = os.environ.copy()
    environment.update(
        {
            "QW_TEST_MARKER": str(marker),
            "QW_TEST_ENV_MARKER": str(environment_marker),
            "KIMI_CODING_API_KEY": "test-kimi-launcher-secret-marker",
            "GLM_API_KEY": "test-glm-launcher-secret-marker",
            "QUOTA_WATCH_KIMI_API_KEY": "test-kimi-direct-secret-marker",
            "QUOTA_WATCH_GLM_API_KEY": "test-glm-direct-secret-marker",
        }
    )

    started = time.monotonic()
    result = subprocess.run(
        [
            str(launcher),
            "-BackendPort",
            "18080",
            "-DesktopExecutable",
            str(desktop),
        ],
        cwd=REPO_ROOT,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=10,
        creationflags=CREATE_NO_WINDOW,
        check=False,
    )
    elapsed = time.monotonic() - started

    assert result.returncode == 0
    assert elapsed < 2.5
    assert marker.read_text(encoding="utf-8") == "started"
    assert environment_marker.read_text(encoding="utf-8").splitlines() == [
        "KIMI_CODING_API_KEY=",
        "GLM_API_KEY=",
        "QUOTA_WATCH_KIMI_API_KEY=",
        "QUOTA_WATCH_GLM_API_KEY=",
    ]


def test_launcher_binary_does_not_embed_secret_values(tmp_path: Path) -> None:
    executable = _build_launcher(tmp_path).read_bytes()
    assert b"test-kimi-launcher-secret-marker" not in executable
    assert b"test-glm-launcher-secret-marker" not in executable
    assert "test-kimi-launcher-secret-marker".encode("utf-16le") not in executable
    assert "test-glm-launcher-secret-marker".encode("utf-16le") not in executable
