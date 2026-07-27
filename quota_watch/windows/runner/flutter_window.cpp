#include "flutter_window.h"

#include <algorithm>
#include <cmath>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <memory>
#include <optional>
#include <string>
#include <vector>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"

struct DesktopWidgetState {
  bool attached = false;
  bool show_desktop = false;
  bool frame_style_saved = false;
  LONG_PTR original_style = 0;
  LONG_PTR original_ex_style = 0;
  HWND bottom_sentinel = nullptr;
  HWND topmost_helper = nullptr;
};

namespace {

constexpr UINT_PTR kDesktopStateTimerId = 0x5157;
constexpr UINT kDesktopCheckIntervalMs = 250;
constexpr UINT kRestoreCheckIntervalMs = 100;

struct DesktopHostSearch {
  DWORD shell_process_id = 0;
  HWND host = nullptr;
};

bool ReadNumber(const flutter::EncodableMap &map, const char *key,
                double *value) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) {
    return false;
  }
  if (const auto *number = std::get_if<double>(&it->second)) {
    *value = *number;
    return std::isfinite(*value);
  }
  if (const auto *number = std::get_if<int32_t>(&it->second)) {
    *value = static_cast<double>(*number);
    return true;
  }
  if (const auto *number = std::get_if<int64_t>(&it->second)) {
    *value = static_cast<double>(*number);
    return true;
  }
  return false;
}

bool ClearWindowRegions(HWND window) {
  return SetWindowRgn(window, nullptr, TRUE) != 0;
}

bool ApplyWindowRegions(HWND window,
                        const flutter::EncodableMap *arguments) {
  if (arguments == nullptr) {
    return false;
  }

  auto regions_it =
      arguments->find(flutter::EncodableValue("regions"));
  if (regions_it == arguments->end()) {
    return false;
  }
  const auto *regions =
      std::get_if<flutter::EncodableList>(&regions_it->second);
  if (regions == nullptr) {
    return false;
  }
  if (regions->empty()) {
    return ClearWindowRegions(window);
  }

  double scale = 1.0;
  double corner_radius = 18.0;
  if (!ReadNumber(*arguments, "devicePixelRatio", &scale) || scale <= 0.0 ||
      !ReadNumber(*arguments, "cornerRadius", &corner_radius) ||
      corner_radius < 0.0) {
    return false;
  }

  RECT window_rect{};
  POINT client_origin{0, 0};
  if (!GetWindowRect(window, &window_rect) ||
      !ClientToScreen(window, &client_origin)) {
    return false;
  }
  const int window_width = window_rect.right - window_rect.left;
  const int window_height = window_rect.bottom - window_rect.top;
  const int client_offset_x = client_origin.x - window_rect.left;
  const int client_offset_y = client_origin.y - window_rect.top;

  HRGN combined = CreateRectRgn(0, 0, 0, 0);
  if (combined == nullptr) {
    return false;
  }

  bool has_valid_region = false;
  for (const auto &encoded_region : *regions) {
    const auto *region =
        std::get_if<flutter::EncodableMap>(&encoded_region);
    if (region == nullptr) {
      continue;
    }

    double logical_left = 0.0;
    double logical_top = 0.0;
    double logical_right = 0.0;
    double logical_bottom = 0.0;
    if (!ReadNumber(*region, "left", &logical_left) ||
        !ReadNumber(*region, "top", &logical_top) ||
        !ReadNumber(*region, "right", &logical_right) ||
        !ReadNumber(*region, "bottom", &logical_bottom) ||
        logical_right <= logical_left || logical_bottom <= logical_top) {
      continue;
    }

    const int left = std::clamp(
        client_offset_x +
            static_cast<int>(std::floor(logical_left * scale)),
        0, window_width);
    const int top = std::clamp(
        client_offset_y +
            static_cast<int>(std::floor(logical_top * scale)),
        0, window_height);
    const int right = std::clamp(
        client_offset_x +
            static_cast<int>(std::ceil(logical_right * scale)),
        0, window_width);
    const int bottom = std::clamp(
        client_offset_y +
            static_cast<int>(std::ceil(logical_bottom * scale)),
        0, window_height);
    if (right <= left || bottom <= top) {
      continue;
    }

    const int diameter = std::max(
        1, std::min(
               static_cast<int>(std::lround(corner_radius * scale * 2.0)),
               std::min(right - left, bottom - top)));
    HRGN tile =
        CreateRoundRectRgn(left, top, right + 1, bottom + 1, diameter, diameter);
    if (tile == nullptr) {
      continue;
    }
    const int combine_result = CombineRgn(combined, combined, tile, RGN_OR);
    DeleteObject(tile);
    if (combine_result == ERROR) {
      DeleteObject(combined);
      return false;
    }
    has_valid_region = true;
  }

  if (!has_valid_region) {
    DeleteObject(combined);
    return ClearWindowRegions(window);
  }

  // On success Windows owns the region handle. The Flutter surface remains
  // opaque; only the top-level window's visible and hit-test area is shaped.
  if (SetWindowRgn(window, combined, TRUE) == 0) {
    DeleteObject(combined);
    return false;
  }
  return true;
}

bool SetDesktopFrameStyle(HWND window,
                          DesktopWidgetState *state,
                          bool frameless) {
  const bool saved_for_this_change =
      frameless && !state->frame_style_saved;
  if (frameless && !state->frame_style_saved) {
    state->original_style = GetWindowLongPtr(window, GWL_STYLE);
    state->original_ex_style = GetWindowLongPtr(window, GWL_EXSTYLE);
    state->frame_style_saved = true;
  }
  if (!frameless && !state->frame_style_saved) {
    return true;
  }

  LONG_PTR style = state->original_style;
  LONG_PTR ex_style = state->original_ex_style;
  if (frameless) {
    constexpr DWORD kDesktopFrameStyles =
        WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX |
        WS_MAXIMIZEBOX;
    constexpr DWORD kDesktopExtendedEdges =
        WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE |
        WS_EX_STATICEDGE;
    style &= ~static_cast<LONG_PTR>(kDesktopFrameStyles);
    style |= static_cast<LONG_PTR>(static_cast<DWORD>(WS_POPUP));
    ex_style &= ~static_cast<LONG_PTR>(kDesktopExtendedEdges);
  }

  SetLastError(ERROR_SUCCESS);
  const LONG_PTR previous_style =
      SetWindowLongPtr(window, GWL_STYLE, style);
  if (previous_style == 0 && GetLastError() != ERROR_SUCCESS) {
    if (saved_for_this_change) {
      state->frame_style_saved = false;
    }
    return false;
  }
  SetLastError(ERROR_SUCCESS);
  const LONG_PTR previous_ex_style =
      SetWindowLongPtr(window, GWL_EXSTYLE, ex_style);
  if (previous_ex_style == 0 && GetLastError() != ERROR_SUCCESS) {
    SetWindowLongPtr(window, GWL_STYLE, previous_style);
    if (saved_for_this_change) {
      state->frame_style_saved = false;
    }
    return false;
  }

  const bool updated =
      SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOACTIVATE | SWP_FRAMECHANGED) != FALSE;
  if (!updated) {
    SetWindowLongPtr(window, GWL_STYLE, previous_style);
    SetWindowLongPtr(window, GWL_EXSTYLE, previous_ex_style);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                     SWP_NOACTIVATE | SWP_FRAMECHANGED);
    if (saved_for_this_change) {
      state->frame_style_saved = false;
    }
    return false;
  }
  if (!frameless) {
    state->frame_style_saved = false;
  }
  return true;
}

BOOL CALLBACK FindTopmostDesktopHost(HWND window, LPARAM parameter) {
  auto *search = reinterpret_cast<DesktopHostSearch *>(parameter);
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id != search->shell_process_id) {
    return TRUE;
  }

  wchar_t class_name[64] = {};
  if (GetClassNameW(window, class_name, 64) == 0) {
    return TRUE;
  }
  if (lstrcmpW(class_name, L"WorkerW") == 0 ||
      lstrcmpW(class_name, L"Progman") == 0) {
    search->host = window;
    return FALSE;
  }
  return TRUE;
}

HWND GetDesktopHost() {
  HWND shell_window = GetShellWindow();
  if (shell_window == nullptr) {
    shell_window = FindWindow(L"Progman", nullptr);
  }
  if (shell_window == nullptr) {
    return nullptr;
  }

  DesktopHostSearch search;
  GetWindowThreadProcessId(shell_window, &search.shell_process_id);
  EnumWindows(FindTopmostDesktopHost, reinterpret_cast<LPARAM>(&search));
  return search.host != nullptr ? search.host : shell_window;
}

bool BelongsToSameProcess(HWND first, HWND second) {
  DWORD first_process_id = 0;
  DWORD second_process_id = 0;
  GetWindowThreadProcessId(first, &first_process_id);
  GetWindowThreadProcessId(second, &second_process_id);
  return first_process_id != 0 && first_process_id == second_process_id;
}

HWND GetDesktopIconsHost() {
  HWND shell_window = GetShellWindow();
  if (shell_window == nullptr) {
    shell_window = FindWindow(L"Progman", nullptr);
  }
  if (shell_window == nullptr) {
    return nullptr;
  }

  // Windows 11 24H2 hosts SHELLDLL_DefView directly under Progman. Older
  // releases commonly host it under a visible Explorer WorkerW instead.
  if (FindWindowExW(shell_window, nullptr, L"SHELLDLL_DefView", nullptr) !=
      nullptr) {
    return shell_window;
  }

  HWND worker = nullptr;
  while ((worker =
              FindWindowExW(nullptr, worker, L"WorkerW", nullptr)) != nullptr) {
    if (BelongsToSameProcess(shell_window, worker) &&
        FindWindowExW(worker, nullptr, L"SHELLDLL_DefView", nullptr) !=
            nullptr) {
      return worker;
    }
  }
  return nullptr;
}

bool PositionDesktopWidget(HWND window) {
  RECT window_rect{};
  if (!GetWindowRect(window, &window_rect)) {
    return false;
  }
  const int width = window_rect.right - window_rect.left;
  const int height = window_rect.bottom - window_rect.top;

  POINT cursor_position{};
  HMONITOR monitor = nullptr;
  if (GetCursorPos(&cursor_position)) {
    monitor =
        MonitorFromPoint(cursor_position, MONITOR_DEFAULTTOPRIMARY);
  } else {
    monitor = MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY);
  }
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return false;
  }

  constexpr LONG kDesktopMargin = 24;
  POINT position{
      monitor_info.rcWork.right - width - kDesktopMargin,
      monitor_info.rcWork.top + kDesktopMargin,
  };
  const LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
  const bool is_child = (style & WS_CHILD) != 0;
  HWND coordinate_parent = is_child ? GetParent(window) : nullptr;
  if (is_child && coordinate_parent != nullptr) {
    MapWindowPoints(HWND_DESKTOP, coordinate_parent, &position, 1);
  }

  UINT flags = SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED;
  HWND insert_after = HWND_TOP;
  if (!is_child) {
    flags |= SWP_NOZORDER;
    insert_after = nullptr;
  }
  return SetWindowPos(window, insert_after, position.x, position.y, width,
                      height, flags) != FALSE;
}

constexpr wchar_t kStartupRegistryPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kStartupValueName[] = L"Quota Watch";
constexpr wchar_t kLauncherFileName[] =
    L"\u542f\u52a8 Quota Watch.exe";

bool IsExistingFile(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::optional<std::wstring> FindQuotaWatchLauncher() {
  std::vector<wchar_t> module_path(32768);
  const DWORD length = GetModuleFileNameW(
      nullptr, module_path.data(), static_cast<DWORD>(module_path.size()));
  if (length == 0 || length >= module_path.size()) {
    return std::nullopt;
  }

  std::wstring directory(module_path.data(), length);
  const size_t executable_separator = directory.find_last_of(L"\\/");
  if (executable_separator == std::wstring::npos) {
    return std::nullopt;
  }
  directory.resize(executable_separator);

  // The release runner normally lives below
  // quota_watch\build\windows\<arch>\runner\Release. Walking upward keeps
  // this independent of the repository's absolute path and architecture.
  for (int level = 0; level < 8 && !directory.empty(); ++level) {
    const std::wstring launcher =
        directory + L"\\" + kLauncherFileName;
    const std::wstring script =
        directory + L"\\scripts\\start_quota_watch.ps1";
    if (IsExistingFile(launcher) && IsExistingFile(script)) {
      return launcher;
    }
    const size_t separator = directory.find_last_of(L"\\/");
    if (separator == std::wstring::npos) {
      break;
    }
    directory.resize(separator);
  }
  return std::nullopt;
}

std::wstring QuoteStartupCommand(const std::wstring& launcher) {
  return L"\"" + launcher + L"\"";
}

bool ReadStartupEnabled(bool* enabled) {
  const auto launcher = FindQuotaWatchLauncher();
  if (!launcher.has_value()) {
    return false;
  }

  HKEY key = nullptr;
  const LONG open_result =
      RegOpenKeyExW(HKEY_CURRENT_USER, kStartupRegistryPath, 0,
                    KEY_QUERY_VALUE, &key);
  if (open_result == ERROR_FILE_NOT_FOUND) {
    *enabled = false;
    return true;
  }
  if (open_result != ERROR_SUCCESS) {
    return false;
  }

  DWORD type = 0;
  DWORD byte_count = 0;
  LONG query_result =
      RegQueryValueExW(key, kStartupValueName, nullptr, &type, nullptr,
                       &byte_count);
  if (query_result == ERROR_FILE_NOT_FOUND) {
    RegCloseKey(key);
    *enabled = false;
    return true;
  }
  if (query_result != ERROR_SUCCESS || type != REG_SZ ||
      byte_count < sizeof(wchar_t)) {
    RegCloseKey(key);
    *enabled = false;
    return query_result == ERROR_SUCCESS;
  }

  std::vector<wchar_t> command(byte_count / sizeof(wchar_t) + 1, L'\0');
  query_result = RegQueryValueExW(
      key, kStartupValueName, nullptr, &type,
      reinterpret_cast<LPBYTE>(command.data()), &byte_count);
  RegCloseKey(key);
  if (query_result != ERROR_SUCCESS) {
    return false;
  }

  const std::wstring expected = QuoteStartupCommand(*launcher);
  *enabled = _wcsicmp(command.data(), expected.c_str()) == 0;
  return true;
}

bool WriteStartupEnabled(bool enable) {
  HKEY key = nullptr;
  if (!enable) {
    const LONG open_result =
        RegOpenKeyExW(HKEY_CURRENT_USER, kStartupRegistryPath, 0,
                      KEY_SET_VALUE, &key);
    if (open_result == ERROR_FILE_NOT_FOUND) {
      return true;
    }
    if (open_result != ERROR_SUCCESS) {
      return false;
    }
    const LONG delete_result = RegDeleteValueW(key, kStartupValueName);
    RegCloseKey(key);
    return delete_result == ERROR_SUCCESS ||
           delete_result == ERROR_FILE_NOT_FOUND;
  }

  const auto launcher = FindQuotaWatchLauncher();
  if (!launcher.has_value()) {
    return false;
  }
  DWORD disposition = 0;
  const LONG create_result =
      RegCreateKeyExW(HKEY_CURRENT_USER, kStartupRegistryPath, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, &disposition);
  if (create_result != ERROR_SUCCESS) {
    return false;
  }
  const std::wstring command = QuoteStartupCommand(*launcher);
  const DWORD byte_count =
      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t));
  const LONG set_result = RegSetValueExW(
      key, kStartupValueName, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(command.c_str()), byte_count);
  RegCloseKey(key);
  return set_result == ERROR_SUCCESS;
}

bool PlaceOnDesktopLayer(HWND window, bool show_window = true) {
  HWND desktop_host = GetDesktopHost();
  if (desktop_host == nullptr) {
    return false;
  }

  // Windows 11 may stack several Explorer WorkerW composition surfaces above
  // Progman. GetDesktopHost returns the highest such Shell surface. Inserting
  // directly above it keeps every desktop layer below Quota Watch while
  // leaving ordinary application windows above it.
  HWND insert_after = GetWindow(desktop_host, GW_HWNDPREV);
  if (insert_after == nullptr || insert_after == window) {
    return insert_after == window;
  }
  UINT flags =
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER;
  if (show_window) {
    flags |= SWP_SHOWWINDOW;
  }
  return SetWindowPos(window, insert_after, 0, 0, 0, 0, flags) != FALSE;
}

void DestroyDesktopTrackingWindows(DesktopWidgetState *state) {
  if (state->topmost_helper != nullptr) {
    DestroyWindow(state->topmost_helper);
    state->topmost_helper = nullptr;
  }
  if (state->bottom_sentinel != nullptr) {
    DestroyWindow(state->bottom_sentinel);
    state->bottom_sentinel = nullptr;
  }
  state->show_desktop = false;
}

bool CreateDesktopTrackingWindows(DesktopWidgetState *state) {
  if (IsWindow(state->bottom_sentinel) &&
      IsWindow(state->topmost_helper)) {
    return true;
  }

  DestroyDesktopTrackingWindows(state);
  HINSTANCE instance = GetModuleHandle(nullptr);
  constexpr DWORD ex_style = WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
  constexpr DWORD style = WS_POPUP | WS_DISABLED;
  state->bottom_sentinel = CreateWindowExW(
      ex_style, L"STATIC", L"QuotaWatchDesktopBottomSentinel", style, 0, 0, 0,
      0, nullptr, nullptr, instance, nullptr);
  state->topmost_helper = CreateWindowExW(
      ex_style, L"STATIC", L"QuotaWatchDesktopTopmostHelper", style, 0, 0, 0,
      0, nullptr, nullptr, instance, nullptr);
  if (state->bottom_sentinel == nullptr ||
      state->topmost_helper == nullptr) {
    DestroyDesktopTrackingWindows(state);
    return false;
  }

  constexpr UINT flags =
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER;
  SetWindowPos(state->bottom_sentinel, HWND_BOTTOM, 0, 0, 0, 0, flags);
  SetWindowPos(state->topmost_helper, HWND_BOTTOM, 0, 0, 0, 0, flags);
  return true;
}

bool IsWindowBelow(HWND reference, HWND candidate) {
  for (HWND current = GetWindow(reference, GW_HWNDNEXT); current != nullptr;
       current = GetWindow(current, GW_HWNDNEXT)) {
    if (current == candidate) {
      return true;
    }
  }
  return false;
}

bool PlaceAboveRaisedDesktop(HWND window, DesktopWidgetState *state) {
  HWND desktop_icons_host = GetDesktopIconsHost();
  if (desktop_icons_host == nullptr) {
    return false;
  }

  constexpr UINT flags =
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER;
  if (!SetWindowPos(state->topmost_helper, HWND_TOPMOST, 0, 0, 0, 0,
                    flags)) {
    return false;
  }

  // Show Desktop raises the desktop above every normal window. Put a hidden
  // helper at the back of the topmost band, below existing topmost apps, then
  // place the widget immediately behind that helper.
  for (HWND current = GetWindow(desktop_icons_host, GW_HWNDPREV);
       current != nullptr; current = GetWindow(current, GW_HWNDPREV)) {
    if (current == window || current == state->topmost_helper ||
        current == state->bottom_sentinel) {
      continue;
    }
    if ((GetWindowLongPtr(current, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0) {
      if (SetWindowPos(state->topmost_helper, current, 0, 0, 0, 0, flags)) {
        break;
      }
    }
  }

  return SetWindowPos(window, state->topmost_helper, 0, 0, 0, 0, flags) !=
         FALSE;
}

bool RefreshDesktopWidgetLayer(HWND window, DesktopWidgetState *state,
                               bool force) {
  if (!state->attached || !IsWindow(state->bottom_sentinel) ||
      !IsWindow(state->topmost_helper)) {
    return false;
  }

  HWND desktop_icons_host = GetDesktopIconsHost();
  const bool show_desktop =
      desktop_icons_host != nullptr && IsWindowVisible(desktop_icons_host) &&
      IsWindowBelow(desktop_icons_host, state->bottom_sentinel);
  if (!force && show_desktop == state->show_desktop) {
    return true;
  }

  state->show_desktop = show_desktop;
  if (show_desktop) {
    SetTimer(window, kDesktopStateTimerId, kRestoreCheckIntervalMs, nullptr);
    return PlaceAboveRaisedDesktop(window, state);
  }

  constexpr UINT flags =
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER;
  SetWindowPos(state->topmost_helper, HWND_BOTTOM, 0, 0, 0, 0, flags);
  SetTimer(window, kDesktopStateTimerId, kDesktopCheckIntervalMs, nullptr);
  return PlaceOnDesktopLayer(window, false);
}

int ShowTrayMenu(HWND window, bool desktop_widget) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return 0;
  }

  AppendMenuW(menu, MF_STRING, 1, L"\u663e\u793a Quota Watch");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING | (desktop_widget ? 0 : MF_CHECKED), 2,
              L"\u7f6e\u9876\u5c0f\u7a97");
  AppendMenuW(menu, MF_STRING | (desktop_widget ? MF_CHECKED : 0), 3,
              L"\u684c\u9762\u60ac\u6d6e\u63d2\u4ef6");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 4,
              L"\u6570\u636e\u8bbe\u7f6e\u2026");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 5, L"\u9000\u51fa");

  POINT cursor_position{};
  GetCursorPos(&cursor_position);
  SetForegroundWindow(window);
  const UINT command = TrackPopupMenu(
      menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY, cursor_position.x,
      cursor_position.y, 0, window, nullptr);
  PostMessage(window, WM_NULL, 0, 0);
  DestroyMenu(menu);
  return static_cast<int>(command);
}

bool AttachToDesktop(HWND window, DesktopWidgetState *state) {
  if (!SetDesktopFrameStyle(window, state, true)) {
    return false;
  }
  if (state->attached) {
    return RefreshDesktopWidgetLayer(window, state, true);
  }
  if (!CreateDesktopTrackingWindows(state)) {
    SetDesktopFrameStyle(window, state, false);
    return false;
  }

  state->attached = true;
  SetTimer(window, kDesktopStateTimerId, kDesktopCheckIntervalMs, nullptr);
  if (PositionDesktopWidget(window) &&
      RefreshDesktopWidgetLayer(window, state, true)) {
    return true;
  }

  KillTimer(window, kDesktopStateTimerId);
  DestroyDesktopTrackingWindows(state);
  state->attached = false;
  SetDesktopFrameStyle(window, state, false);
  return false;
}

bool DetachFromDesktop(HWND window, DesktopWidgetState *state) {
  ClearWindowRegions(window);
  const bool frame_restored = SetDesktopFrameStyle(window, state, false);
  if (!state->attached) {
    return frame_restored;
  }

  KillTimer(window, kDesktopStateTimerId);
  DestroyDesktopTrackingWindows(state);

  RECT window_rect{};
  if (!GetWindowRect(window, &window_rect)) {
    return false;
  }
  const int width = window_rect.right - window_rect.left;
  const int height = window_rect.bottom - window_rect.top;

  constexpr UINT flags =
      SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED | SWP_NOOWNERZORDER;
  SetWindowPos(window, HWND_NOTOPMOST, window_rect.left, window_rect.top, width,
               height, flags);
  SetWindowPos(window, HWND_TOP, window_rect.left, window_rect.top, width,
               height, flags);
  state->attached = false;
  return frame_restored;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project),
      desktop_widget_state_(std::make_unique<DesktopWidgetState>()) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Stage 9: custom platform channel for the fixed-HWND tray popup and native
  // positioning. Desktop-widget mode keeps the unmodified Flutter top-level
  // surface and parks it immediately above Progman in z-order.
  auto *engine = flutter_controller_->engine();
  auto *channel = new flutter::MethodChannel<flutter::EncodableValue>(
      engine->messenger(), "quota_watch/window",
      &flutter::StandardMethodCodec::GetInstance());
  HWND main_hwnd = GetHandle();
  channel->SetMethodCallHandler(
      [this, main_hwnd](
          const flutter::MethodCall<flutter::EncodableValue> &call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == "showTrayMenu") {
          const auto *args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          bool desktop_widget = false;
          if (args != nullptr) {
            auto it = args->find(flutter::EncodableValue("desktopWidget"));
            if (it != args->end()) {
              desktop_widget = std::get<bool>(it->second);
            }
          }
          result->Success(flutter::EncodableValue(
              ShowTrayMenu(main_hwnd, desktop_widget)));
          return;
        }
        if (call.method_name() == "positionDesktopWidget") {
          result->Success(
              flutter::EncodableValue(PositionDesktopWidget(main_hwnd)));
          return;
        }
        if (call.method_name() == "getStartupEnabled") {
          bool enabled = false;
          if (!ReadStartupEnabled(&enabled)) {
            result->Error(
                "startup_unavailable",
                "The Quota Watch launcher or Windows startup setting "
                "could not be read.");
          } else {
            result->Success(flutter::EncodableValue(enabled));
          }
          return;
        }
        if (call.method_name() == "setStartupEnabled") {
          const auto *args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          bool enable = false;
          if (args == nullptr) {
            result->Error("invalid_arguments",
                          "The startup setting is missing.");
            return;
          }
          auto it = args->find(flutter::EncodableValue("enable"));
          if (it == args->end()) {
            result->Error("invalid_arguments",
                          "The startup setting is missing.");
            return;
          }
          const auto *requested = std::get_if<bool>(&it->second);
          if (requested == nullptr) {
            result->Error("invalid_arguments",
                          "The startup setting must be a boolean.");
            return;
          }
          enable = *requested;
          if (!WriteStartupEnabled(enable)) {
            result->Error(
                "startup_write_failed",
                "The Windows startup setting could not be changed.");
          } else {
            result->Success(flutter::EncodableValue(true));
          }
          return;
        }
        if (call.method_name() == "setWindowRegions") {
          const auto *args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          result->Success(
              flutter::EncodableValue(ApplyWindowRegions(main_hwnd, args)));
          return;
        }
        if (call.method_name() == "setToolWindow" ||
            call.method_name() == "setDesktopWidget") {
          const auto *args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          bool enable = false;
          if (args != nullptr) {
            auto it = args->find(flutter::EncodableValue("enable"));
            if (it != args->end()) {
              enable = std::get<bool>(it->second);
            }
          }
          if (call.method_name() == "setDesktopWidget") {
            const bool success = enable
                                     ? AttachToDesktop(
                                           main_hwnd,
                                           desktop_widget_state_.get())
                                     : DetachFromDesktop(
                                           main_hwnd,
                                           desktop_widget_state_.get());
            if (success) {
              desktop_widget_mode_ = enable;
            }
            result->Success(flutter::EncodableValue(success));
            return;
          }
          LONG_PTR ex = GetWindowLongPtr(main_hwnd, GWL_EXSTYLE);
          const LONG_PTR tool = WS_EX_TOOLWINDOW;
          LONG_PTR new_ex = enable ? (ex | tool) : (ex & ~tool);
          SetWindowLongPtr(main_hwnd, GWL_EXSTYLE, new_ex);
          // Notify the shell to re-evaluate the window's taskbar state.
          SetWindowPos(main_hwnd, nullptr, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                           SWP_NOACTIVATE | SWP_FRAMECHANGED);
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), kDesktopStateTimerId);
  if (desktop_widget_state_) {
    DestroyDesktopTrackingWindows(desktop_widget_state_.get());
    desktop_widget_state_->attached = false;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Show Desktop sends ordinary application windows a minimize command.
  // Desktop widgets must remain available when the other windows are hidden.
  if (desktop_widget_mode_ && message == WM_SYSCOMMAND &&
      (wparam & 0xFFF0) == SC_MINIMIZE) {
    return 0;
  }
  if (desktop_widget_mode_ && message == WM_TIMER &&
      wparam == kDesktopStateTimerId && desktop_widget_state_) {
    RefreshDesktopWidgetLayer(hwnd, desktop_widget_state_.get(), false);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
