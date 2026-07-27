"""Source-level guards for the Windows tray and desktop-host integration."""

from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = (
    REPO_ROOT
    / "quota_watch"
    / "lib"
    / "app"
    / "desktop"
    / "desktop_controller_io.dart"
)
NATIVE_DART = (
    REPO_ROOT
    / "quota_watch"
    / "lib"
    / "app"
    / "desktop"
    / "window_native_io.dart"
)
NATIVE_CPP = (
    REPO_ROOT
    / "quota_watch"
    / "windows"
    / "runner"
    / "flutter_window.cpp"
)
WINDOW_NATIVE_DART = (
    REPO_ROOT
    / "quota_watch"
    / "lib"
    / "app"
    / "desktop"
    / "window_native_io.dart"
)
WINDOW_RUNNER_CMAKE = (
    REPO_ROOT
    / "quota_watch"
    / "windows"
    / "runner"
    / "CMakeLists.txt"
)
HOME_PAGE = (
    REPO_ROOT
    / "quota_watch"
    / "lib"
    / "presentation"
    / "pages"
    / "home_page.dart"
)


def test_tray_is_initialized_before_initial_display_mode() -> None:
    source = CONTROLLER.read_text(encoding="utf-8")

    tray_setup = source.index("await _setupTray();")
    desktop_mode = source.index(
        "await setDisplayMode(DisplayMode.desktopWidget);",
        tray_setup,
    )

    assert tray_setup < desktop_mode


def test_desktop_mode_is_reapplied_after_the_first_flutter_frame() -> None:
    source = CONTROLLER.read_text(encoding="utf-8")
    initial_mode = source.index(
        "await setDisplayMode(DisplayMode.desktopWidget);",
    )
    callback_start = source.index(
        "WidgetsBinding.instance.addPostFrameCallback",
        initial_mode,
    )
    callback = source.split(
        "WidgetsBinding.instance.addPostFrameCallback",
        1,
    )[1].split("WidgetsBinding.instance.ensureVisualUpdate();", 1)[0]

    assert initial_mode < callback_start
    assert "await Future<void>.delayed(Duration.zero);" in callback
    assert "if (_mode == DisplayMode.desktopWidget)" in callback
    assert "await _applyDisplayMode()" in callback
    assert "WidgetsBinding.instance.ensureVisualUpdate();" in source


def test_windows_starts_in_desktop_widget_mode_by_default() -> None:
    source = CONTROLLER.read_text(encoding="utf-8")

    assert "defaultValue: 'desktop_widget'" in source
    assert (
        "if (Platform.isWindows && initialModeName != 'always_on_top')"
        in source
    )
    assert "await setDisplayMode(DisplayMode.desktopWidget);" in source


def test_windows_tray_menu_uses_saved_application_window() -> None:
    controller = CONTROLLER.read_text(encoding="utf-8")
    native_dart = NATIVE_DART.read_text(encoding="utf-8")
    native_cpp = NATIVE_CPP.read_text(encoding="utf-8")

    callback = controller.index("void onTrayIconRightMouseDown()")
    popup = controller.index("WindowNative.showTrayMenu(", callback)

    assert popup > callback
    assert "'showTrayMenu'" in native_dart
    assert 'call.method_name() == "showTrayMenu"' in native_cpp
    assert "ShowTrayMenu(main_hwnd, desktop_widget)" in native_cpp
    assert "TPM_RETURNCMD" in native_cpp


def test_windows_autostart_uses_current_user_gui_launcher_only() -> None:
    native_dart = WINDOW_NATIVE_DART.read_text(encoding="utf-8")
    native_cpp = NATIVE_CPP.read_text(encoding="utf-8")
    cmake = WINDOW_RUNNER_CMAKE.read_text(encoding="utf-8")

    assert "'getStartupEnabled'" in native_dart
    assert "'setStartupEnabled'" in native_dart
    assert '"getStartupEnabled"' in native_cpp
    assert '"setStartupEnabled"' in native_cpp
    assert "HKEY_CURRENT_USER" in native_cpp
    assert "HKEY_LOCAL_MACHINE" not in native_cpp
    assert "Microsoft\\\\Windows\\\\CurrentVersion\\\\Run" in native_cpp
    assert 'kStartupValueName[] = L"Quota Watch"' in native_cpp
    assert "kLauncherFileName" in native_cpp
    assert "scripts\\\\start_quota_watch.ps1" not in native_cpp
    assert "RegSetValueExW" in native_cpp
    assert "RegDeleteValueW" in native_cpp
    assert "advapi32" in cmake


def test_provider_credential_bridge_is_fixed_target_read_only_and_never_logged() -> None:
    native_dart = WINDOW_NATIVE_DART.read_text(encoding="utf-8")
    native_cpp = NATIVE_CPP.read_text(encoding="utf-8")

    assert "'readProviderApiKey'" in native_dart
    assert '"readProviderApiKey"' in native_cpp
    assert 'L"QuotaWatch/Kimi"' in native_cpp
    assert 'L"QuotaWatch/GLM"' in native_cpp
    assert "CredReadW" in native_cpp
    assert "CredFree" in native_cpp
    assert "CredEnumerateW" not in native_cpp
    assert "std::cout" not in native_cpp
    assert "printf(" not in native_cpp


def test_provider_credential_mutations_and_metadata_use_fixed_native_boundaries() -> None:
    native_dart = WINDOW_NATIVE_DART.read_text(encoding="utf-8")
    native_cpp = NATIVE_CPP.read_text(encoding="utf-8")

    for method in (
        "writeProviderApiKey",
        "deleteProviderApiKey",
        "readCredentialMetadata",
        "writeCredentialMetadata",
    ):
        assert method in native_dart
        assert f'"{method}"' in native_cpp
    assert "CredWriteW" in native_cpp
    assert "CredDeleteW" in native_cpp
    assert "CRED_PERSIST_LOCAL_MACHINE" in native_cpp
    assert "credential_profiles.json" in native_cpp
    assert "MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH" in native_cpp
    assert "kMaxPersistedCredentialBytes = 2048" in native_cpp


def test_hide_to_tray_does_not_minimize_the_widget_window() -> None:
    source = CONTROLLER.read_text(encoding="utf-8")
    hide_method = source.split("Future<void> hideToTray() async", 1)[1].split(
        "Future<void> showFromTray() async",
        1,
    )[0]

    assert "windowManager.hide()" in hide_method
    assert "windowManager.minimize()" not in hide_method


def test_show_from_tray_reapplies_the_current_floating_mode() -> None:
    source = CONTROLLER.read_text(encoding="utf-8")
    show_method = source.split("Future<void> showFromTray() async", 1)[1].split(
        "Future<void> quit() async",
        1,
    )[0]

    assert "await _applyDisplayMode()" in show_method
    assert "setDisplayMode(DisplayMode.alwaysOnTop)" not in show_method
    assert "windowManager.focus()" in show_method


def test_selecting_the_current_mode_still_reveals_the_window() -> None:
    controller = CONTROLLER.read_text(encoding="utf-8")
    mode_method = controller.split(
        "Future<void> setDisplayMode(DisplayMode mode) async",
        1,
    )[1].split(
        "Future<void> _applyDisplayMode() async",
        1,
    )[0]

    assert "if (mode == _mode) return" not in mode_method
    assert "await windowManager.show()" in mode_method
    assert "await _applyDisplayMode()" in mode_method
    assert "if (_mode == DisplayMode.alwaysOnTop)" in mode_method
    assert "await windowManager.focus()" in mode_method


def test_desktop_mode_tracks_show_desktop_without_reparenting_flutter() -> None:
    controller = CONTROLLER.read_text(encoding="utf-8")
    native_dart = NATIVE_DART.read_text(encoding="utf-8")
    native_cpp = NATIVE_CPP.read_text(encoding="utf-8")

    desktop_case = controller.split("case DisplayMode.desktopWidget:", 1)[1]
    assert "setAlwaysOnBottom(true)" not in desktop_case
    assert "WindowNative.setDesktopWidget(true)" in desktop_case
    assert "windowManager.setAlwaysOnTop(false)" in desktop_case
    assert "windowManager.setAlwaysOnTop(true)" not in desktop_case
    assert "windowManager.setSkipTaskbar(true)" in desktop_case
    assert "WindowNative.setToolWindow(true)" not in desktop_case
    assert "WindowNative.setToolWindow(false)" in desktop_case
    assert "windowManager.setOpacity(" not in desktop_case
    assert "_kOpaqueWindowBackground = Color(0xFF121318)" in controller
    assert "backgroundColor: _kOpaqueWindowBackground" in controller
    assert "WindowNative.positionDesktopWidget()" in controller
    assert "'positionDesktopWidget'" in native_dart
    assert 'call.method_name() == "positionDesktopWidget"' in native_cpp
    assert "MonitorFromPoint" in native_cpp
    assert "SWP_NOZORDER" in native_cpp
    assert "MONITORINFO" in native_cpp
    assert "EnumWindows(FindTopmostDesktopHost" in native_cpp
    assert "GetWindowThreadProcessId(shell_window" in native_cpp
    assert 'lstrcmpW(class_name, L"WorkerW")' in native_cpp
    assert 'lstrcmpW(class_name, L"Progman")' in native_cpp
    assert "GetWindow(desktop_host, GW_HWNDPREV)" in native_cpp
    assert "SWP_NOOWNERZORDER" in native_cpp
    assert "SetParent(" not in native_cpp
    assert "GWLP_HWNDPARENT" not in native_cpp
    assert "child_style" not in native_cpp
    assert "GetDesktopIconsHost()" in native_cpp
    assert 'L"SHELLDLL_DefView"' in native_cpp
    assert "bottom_sentinel" in native_cpp
    assert "topmost_helper" in native_cpp
    assert "IsWindowBelow(desktop_icons_host, state->bottom_sentinel)" in native_cpp
    assert "SetTimer(window, kDesktopStateTimerId" in native_cpp
    assert "PlaceAboveRaisedDesktop(window, state)" in native_cpp
    assert "HWND_TOPMOST" in native_cpp
    assert "HWND_NOTOPMOST" in native_cpp
    assert "message == WM_SYSCOMMAND" in native_cpp
    assert "SC_MINIMIZE" in native_cpp


def test_seamless_tiles_shape_the_opaque_window_without_layered_composition() -> None:
    controller = CONTROLLER.read_text(encoding="utf-8")
    native_dart = NATIVE_DART.read_text(encoding="utf-8")
    native_cpp = NATIVE_CPP.read_text(encoding="utf-8")
    home_page = HOME_PAGE.read_text(encoding="utf-8")

    assert "setDesktopWidgetRegions" in controller
    assert "'setWindowRegions'" in native_dart
    assert 'call.method_name() == "setWindowRegions"' in native_cpp
    assert "CreateRoundRectRgn" in native_cpp
    assert "CombineRgn(combined, combined, tile, RGN_OR)" in native_cpp
    assert "SetWindowRgn(window, combined, TRUE)" in native_cpp
    assert "SetWindowRgn(window, nullptr, TRUE)" in native_cpp
    assert "WS_EX_LAYERED" not in native_cpp
    # Stage 12 floating UX intentionally fades the complete native window on
    # idle. This uses window_manager's compositor opacity and must not restore
    # the old per-pixel WS_EX_LAYERED rendering path.
    assert "await windowManager.setOpacity(opacity)" in controller
    assert "_cardKeys" in home_page
    assert "localToGlobal(Offset.zero)" in home_page
    assert "with RouteAware" in home_page


def test_desktop_tiles_remove_and_restore_native_non_client_edges() -> None:
    controller = CONTROLLER.read_text(encoding="utf-8")
    native_cpp = NATIVE_CPP.read_text(encoding="utf-8")
    frame_style_block = native_cpp.split("bool SetDesktopFrameStyle", 1)[1].split(
        "BOOL CALLBACK", 1
    )[0]
    top_case = controller.split("case DisplayMode.alwaysOnTop:", 1)[1].split(
        "case DisplayMode.desktopWidget:", 1
    )[0]
    desktop_case = controller.split("case DisplayMode.desktopWidget:", 1)[1]
    region_method = controller.split(
        "Future<void> setDesktopWidgetRegions", 1
    )[1].split("@override", 1)[0]
    clear_method = controller.split(
        "Future<void> clearDesktopWidgetRegions", 1
    )[1].split("@override", 1)[0]

    assert "windowManager.setAsFrameless()" in desktop_case
    assert "windowManager.setHasShadow(false)" in desktop_case
    assert "windowManager.setTitleBarStyle(TitleBarStyle.hidden)" in top_case
    background_helper = controller.split(
        "Future<void> _setNativeWindowBackground", 1
    )[1].split("@override", 1)[0]

    assert "_setNativeWindowBackground(Colors.transparent)" in region_method
    assert (
        "_setNativeWindowBackground(_kOpaqueWindowBackground)" in clear_method
    )
    assert (
        region_method.index("_setNativeWindowBackground(Colors.transparent)")
        < region_method.index("WindowNative.setWindowRegions")
    )
    assert (
        clear_method.index("_setNativeWindowBackground(_kOpaqueWindowBackground)")
        < clear_method.index("WindowNative.setWindowRegions")
    )
    assert "windowManager.setBackgroundColor(color)" in background_helper
    assert "on MissingPluginException" in background_helper
    assert "on PlatformException" in background_helper
    assert "SetDesktopFrameStyle" in native_cpp
    assert "frame_style_saved" in native_cpp
    assert "original_style" in native_cpp
    assert "original_ex_style" in native_cpp
    assert "WS_CAPTION | WS_THICKFRAME" in native_cpp
    assert "WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE" in native_cpp
    assert (
        "style |= static_cast<LONG_PTR>(static_cast<DWORD>(WS_POPUP))"
        in native_cpp
    )
    assert "SWP_NOACTIVATE | SWP_FRAMECHANGED" in native_cpp
    assert "SetDesktopFrameStyle(window, state, true)" in native_cpp
    assert "SetDesktopFrameStyle(window, state, false)" in native_cpp
    assert "WS_CHILD" not in frame_style_block
