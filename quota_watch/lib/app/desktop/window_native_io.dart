// ============================================================================
// window_native_io.dart - 原生窗口扩展样式控制（仅 Windows，方法通道）
// ============================================================================
//
// 【阶段 9 学习要点】
// - MethodChannel：Flutter 与原生（这里是 C++ runner）通信的标准通道。
//   Dart 侧调 invokeMethod，原生侧用 SetMethodCallHandler 接收。
// - 为什么需要它：真正的桌面组件需要 Win32 Shell-relative z-order；这种关系
//   不能只靠 Flutter widget 或 window_manager 表达。
//
// 仅 Windows runner 注册了 'quota_watch/window' 通道；其他平台调用是 no-op。

import 'package:flutter/services.dart';

class WindowNative {
  static const MethodChannel _channel = MethodChannel('quota_watch/window');

  /// 读取当前 Windows 用户是否已把根目录 GUI 启动器注册为登录启动项。
  ///
  /// `null` 表示当前平台不支持，或原生层无法安全确认状态。
  static Future<bool?> getStartupEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('getStartupEnabled');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 开启或关闭当前 Windows 用户的登录启动项。
  ///
  /// 只把根目录 `启动 Quota Watch.exe` 的路径交给 Windows，不携带任何
  /// Provider Key、额度数据或后端参数。
  static Future<bool> setStartupEnabled(bool enable) async {
    try {
      return await _channel.invokeMethod<bool>(
            'setStartupEnabled',
            <String, dynamic>{'enable': enable},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Reads one whitelisted Provider key from Windows Credential Manager.
  ///
  /// The native runner only accepts `kimi` or `glm` and maps them to the fixed
  /// Quota Watch targets. The returned value is held only for the immediate
  /// provider request and must never be logged, persisted, or surfaced in UI.
  static Future<String?> readProviderApiKey(String provider) async {
    if (provider != 'kimi' && provider != 'glm') return null;
    try {
      return await _channel.invokeMethod<String>(
        'readProviderApiKey',
        <String, dynamic>{'provider': provider},
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> writeProviderApiKey(
    String provider,
    String secret,
  ) async {
    if (provider != 'kimi' && provider != 'glm') return false;
    try {
      return await _channel.invokeMethod<bool>(
            'writeProviderApiKey',
            <String, dynamic>{'provider': provider, 'secret': secret},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> deleteProviderApiKey(String provider) async {
    if (provider != 'kimi' && provider != 'glm') return false;
    try {
      return await _channel.invokeMethod<bool>(
            'deleteProviderApiKey',
            <String, dynamic>{'provider': provider},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String?> readCredentialMetadata() async {
    try {
      return await _channel.invokeMethod<String>('readCredentialMetadata');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> writeCredentialMetadata(String contents) async {
    try {
      return await _channel.invokeMethod<bool>(
            'writeCredentialMetadata',
            <String, dynamic>{'contents': contents},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 设置窗口是否为"工具窗口"（WS_EX_TOOLWINDOW）。
  /// 工具窗口通常会从任务栏和 Alt+Tab 列表消失；当前生产路径保持 false，
  /// 因为实机运行期切换曾让 Flutter surface 变透明。
  /// 非 Windows 平台或通道未注册时静默忽略错误。
  static Future<void> setToolWindow(bool enable) async {
    try {
      await _channel.invokeMethod<bool>(
        'setToolWindow',
        <String, dynamic>{'enable': enable},
      );
    } on MissingPluginException {
      // 非 Windows 平台或 runner 未注册通道：安全忽略。
    } on PlatformException {
      // 原生调用失败不应拖垮应用。
    }
  }

  /// 把顶层窗口插到 Windows 桌面正上方，并跟踪 Show Desktop 状态；
  /// 关闭时恢复普通窗口 z-order。
  ///
  /// 窗口不改变 parent、owner 或 style，因此不会破坏 Flutter renderer。
  static Future<bool> setDesktopWidget(bool enable) async {
    try {
      return await _channel.invokeMethod<bool>(
            'setDesktopWidget',
            <String, dynamic>{'enable': enable},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 在首帧布局后，把小组件放到当前显示器工作区右上角。
  static Future<bool> positionDesktopWidget() async {
    try {
      return await _channel.invokeMethod<bool>('positionDesktopWidget') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 用多个圆角矩形裁剪窗口。空列表表示恢复完整矩形。
  ///
  /// 这不启用原生透明窗口，而是让 Windows 只保留磁贴实际占用的区域；
  /// Flutter surface 继续走已经验证的不透明渲染路径。
  static Future<bool> setWindowRegions(
    List<Rect> regions, {
    required double devicePixelRatio,
    double cornerRadius = 18,
  }) async {
    try {
      return await _channel.invokeMethod<bool>(
            'setWindowRegions',
            <String, dynamic>{
              'devicePixelRatio': devicePixelRatio,
              'cornerRadius': cornerRadius,
              'regions': [
                for (final region in regions)
                  <String, double>{
                    'left': region.left,
                    'top': region.top,
                    'right': region.right,
                    'bottom': region.bottom,
                  },
              ],
            },
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 用保存的 Quota Watch HWND 弹出 Windows 托盘菜单。
  ///
  /// 原生实现始终使用初始化时保存的应用 HWND，并直接返回命令编号。
  static Future<int?> showTrayMenu({required bool desktopWidget}) async {
    try {
      return await _channel.invokeMethod<int>(
        'showTrayMenu',
        <String, dynamic>{'desktopWidget': desktopWidget},
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
