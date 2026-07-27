// ============================================================================
// desktop_controller_io.dart - Windows（原生）桌面控制器真实现
// ============================================================================
//
// 【阶段 9 学习要点】
// - window_manager：控制窗口尺寸/无边框/置顶/隐藏。
// - tray_manager：系统托盘图标 + 右键菜单 + 点击事件。
// - 二者都是 platform plugin，靠 MethodChannel 与原生（C++/Win32）通信，
//   因此必须先 ensureInitialized 再使用。
//
// 凭据边界（硬规则）：本文件只操作"窗口/托盘"的可视行为，绝不读取环境变量、
// 绝不接触 API key。key 由启动脚本注入到 backend 子进程。

import 'dart:io' show Platform, exit, stderr;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/router/app_router.dart';
import 'desktop_controller.dart';
import 'window_native_io.dart';

/// 小组件窗口的目标尺寸（逻辑像素）。
///
/// 360×680 形成靠右停放的竖向信息条，三张紧凑订阅磁贴可以优先在一屏内
/// 展开；仍保留滚动，兼容较小工作区、系统大字体和额外状态文案。
const _kWindowWidth = 360.0;
const _kWindowHeight = 680.0;
const _kHorizontalWindowWidth = 1120.0;
const _kHorizontalWindowHeight = 340.0;
const _kOpaqueWindowBackground = Color(0xFF121318);

/// 托盘图标在 assets 下的路径（pubspec 已注册 assets/logos/）。
/// 注意：Windows 托盘的 LoadImage 只接受 .ico，png 会让图标加载失败显示空白。
/// 这个百分比环图标代表 Quota Watch 本身（查看额度消耗），不偏向任一服务商。
/// 由 scripts/Pillow 生成多分辨率 .ico（16/24/32/48/64/128/256）。
const _kTrayIconAsset = 'assets/logos/quota_watch_icon.ico';

/// Windows 上的桌面控制器真实现。
///
/// 同时混入 WindowListener（拦截关闭按钮）与 TrayListener（托盘点击）。
class IoDesktopController
    with WindowListener, TrayListener
    implements DesktopController {
  IoDesktopController();

  /// Windows 在 init() 中默认切到桌面悬浮插件；对象构造时先保持普通窗口，
  /// 让 Web、Android 与不执行真实桌面初始化的 Widget 测试不受影响。
  DisplayMode _mode = DisplayMode.alwaysOnTop;
  DesktopLayoutPreference _layoutPreference = _initialLayoutPreference();
  final ValueNotifier<DisplayMode> _displayModeListenable =
      ValueNotifier(DisplayMode.alwaysOnTop);

  @override
  DisplayMode get displayMode => _mode;

  @override
  ValueListenable<DisplayMode> get displayModeListenable =>
      _displayModeListenable;

  @override
  Future<void> setDesktopWidgetRegions(
    List<Rect> regions, {
    required double devicePixelRatio,
    double cornerRadius = 18,
  }) async {
    if (!Platform.isWindows) return;
    // 必须等 Flutter 已经画出磁贴并准备应用原生区域后，才关闭顶层窗口
    // 的 Accent 底色。若在启动阶段直接使用透明 WindowOptions，实机曾
    // 出现整个 Flutter surface 不可见；这里的时序只让区域外露出桌面。
    await _setNativeWindowBackground(Colors.transparent);
    await WindowNative.setWindowRegions(
      regions,
      devicePixelRatio: devicePixelRatio,
      cornerRadius: cornerRadius,
    );
  }

  @override
  Future<void> clearDesktopWidgetRegions() async {
    if (!Platform.isWindows) return;
    // 先恢复安全的不透明底色，再清除区域。设置页、加载/错误状态和
    // 置顶小窗因此不会短暂出现整块透明窗口。
    await _setNativeWindowBackground(_kOpaqueWindowBackground);
    await WindowNative.setWindowRegions(
      const [],
      devicePixelRatio: 1,
    );
  }

  Future<void> _setNativeWindowBackground(Color color) async {
    try {
      await windowManager.setBackgroundColor(color);
    } on MissingPluginException {
      // Widget/Golden 测试没有注册 Windows 插件；区域通道同样按 no-op 处理。
    } on PlatformException {
      // 背景切换失败不应让页面状态或托盘恢复路径崩溃。
    }
  }

  @override
  Future<void> setOpacity(double opacity) async {
    if (!Platform.isWindows) return;
    // 整窗不透明度由原生合成器处理，命中区域不受影响。
    try {
      await windowManager.setOpacity(opacity);
    } on MissingPluginException {
      // Widget/Golden 测试没有注册 Windows 插件；按 no-op 处理。
    } on PlatformException {
      // 透明度切换失败不应让 hover/淡出路径崩溃。
    }
  }

  @override
  Future<void> init() async {
    // 仅桌面原生平台生效。
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return;
    }

    // —— 1) 窗口 ——
    await windowManager.ensureInitialized();
    windowManager.addListener(this); // 监听 onWindowClose 等

    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: _targetWindowSize,
        titleBarStyle: TitleBarStyle.hidden,
        // Windows 原生透明背景会启用 composition/layered 路径；与 Flutter
        // 桌面渲染组合后曾出现“窗口存在但画面全透明”。使用不透明底色，
        // Material Scaffold 仍会按亮/暗主题覆盖它。
        backgroundColor: _kOpaqueWindowBackground,
        skipTaskbar: false,
        alwaysOnTop: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
        await windowManager.center();
        // 必须在窗口就绪后就 setPreventClose(true)：原生侧只有在
        // IsPreventClose()==true 时，点关闭✕才会回调 onWindowClose 而非直接销毁。
        // 若放到 onWindowClose 内部设置，彼时已是 false，窗口会被直接关掉。
        await windowManager.setPreventClose(true);
      },
    );

    // —— 2) 托盘 ——
    // 尽早注册托盘，让窗口隐藏后仍有稳定的恢复入口。此前的桌面宿主实验会
    // 改变 GA_ROOT，因此这里继续保留“托盘先于显示模式”的安全顺序。
    // 用 try-catch 包住：任一步失败都不应拖垮窗口初始化。
    trayManager.addListener(this);
    await _setupTray();

    // —— 3) 初始显示模式（支持 dart-define，便于自动化启动验证）——
    // Windows 默认直接以桌面悬浮插件启动；仍可用 QUOTA_DISPLAY_MODE
    // 显式覆盖为 always_on_top，便于诊断和自动化验证。
    const initialModeName = String.fromEnvironment(
      'QUOTA_DISPLAY_MODE',
      defaultValue: 'desktop_widget',
    );
    if (Platform.isWindows && initialModeName != 'always_on_top') {
      await setDisplayMode(DisplayMode.desktopWidget);
      // Flutter runner 会在首帧再次 Show 主窗口，可能覆盖之前的尺寸与
      // z-order。post-frame 内再让出一个事件循环，等原生 next-frame Show
      // 完成后，最后重放桌面模式。
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(Duration.zero);
        if (_mode == DisplayMode.desktopWidget) {
          await _applyDisplayMode();
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  Future<void> _setupTray() async {
    try {
      await trayManager.setIcon(_kTrayIconAsset);
      await trayManager.setToolTip('Quota Watch');
      await trayManager.setContextMenu(_buildMenu());
    } catch (e, st) {
      // 托盘失败不应拖垮窗口；打印到 stderr 便于 release 排查。
      stderr.writeln('[QW] tray setup error: $e\n$st');
    }
  }

  /// 构建托盘右键菜单：显示 / 显示模式切换 / 设置 / 退出。
  Menu _buildMenu() {
    return Menu(items: [
      MenuItem(
        key: 'show',
        label: '显示 Quota Watch',
        onClick: (_) => showFromTray(),
      ),
      MenuItem.separator(),
      // 显示模式：用 checkbox 标记当前模式，点另一项即切换。
      MenuItem.checkbox(
        key: 'mode_top',
        label: '置顶小窗',
        checked: _mode == DisplayMode.alwaysOnTop,
        onClick: (_) => setDisplayMode(DisplayMode.alwaysOnTop),
      ),
      MenuItem.checkbox(
        key: 'mode_widget',
        label: '桌面悬浮插件',
        checked: _mode == DisplayMode.desktopWidget,
        onClick: (_) => setDisplayMode(DisplayMode.desktopWidget),
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'settings',
        label: '数据设置…',
        onClick: (_) {
          // 经现成的全局 navigatorKey 跨 widget 树跳转，无需 BuildContext。
          AppRouter.navigatorKey.currentState?.pushNamed('/settings');
          showFromTray(); // 跳转同时把窗口带到前台
        },
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'quit',
        label: '退出',
        onClick: (_) => quit(),
      ),
    ]);
  }

  // ---- WindowListener：拦截原生关闭按钮 ----

  @override
  void onWindowClose() async {
    // preventClose 已在 init 时置 true，故原生会回调到这里而不是直接关窗。
    // 这里只隐藏到托盘，保留进程常驻。
    await hideToTray();
  }

  // ---- TrayListener：托盘点击 ----

  @override
  void onTrayIconMouseDown() {
    // 左键单击托盘：切换显示/隐藏。
    // 这里简单恢复显示；详细切换在 showFromTray。
    showFromTray();
  }

  @override
  void onTrayIconRightMouseDown() {
    _showTrayMenu();
  }

  Future<void> _showTrayMenu() async {
    if (Platform.isWindows) {
      // Windows runner 用初始化时保存的应用 HWND 显示菜单，并直接返回
      // 用户选择的命令，避免恢复/样式切换后 popup owner 漂移。
      final command = await WindowNative.showTrayMenu(
        desktopWidget: _mode == DisplayMode.desktopWidget,
      );
      switch (command) {
        case 1:
          await showFromTray();
          break;
        case 2:
          await setDisplayMode(DisplayMode.alwaysOnTop);
          break;
        case 3:
          await setDisplayMode(DisplayMode.desktopWidget);
          break;
        case 4:
          AppRouter.navigatorKey.currentState?.pushNamed('/settings');
          await showFromTray();
          break;
        case 5:
          await quit();
          break;
      }
      return;
    }

    // 其他桌面平台沿用 tray_manager 自身的弹出菜单实现。
    // ignore: deprecated_member_use
    await trayManager.popUpContextMenu(bringAppToFront: true);
  }

  // ---- DesktopController 接口 ----

  @override
  Future<void> setDisplayMode(DisplayMode mode) async {
    final modeChanged = mode != _mode;
    _mode = mode;
    if (modeChanged) {
      // 先通知 Flutter 页面切换标题栏，再重放对应的原生窗口属性。
      _displayModeListenable.value = mode;
    }

    // 选择显示模式本身也是一次明确的“显示窗口”动作。即使用户点的是当前
    // 已勾选模式，也必须把之前隐藏的窗口重新显示，不能因模式相同而 no-op。
    await windowManager.show();
    await _applyDisplayMode();
    // 选择桌面组件会把它送回桌面层；只有置顶模式需要立即抢占前台。
    if (_mode == DisplayMode.alwaysOnTop) {
      await windowManager.focus();
    }
    if (modeChanged) {
      // 切换后刷新托盘菜单（让"当前模式"项的勾选状态正确）。
      await trayManager.setContextMenu(_buildMenu());
    }
  }

  @override
  Future<void> setLayoutPreference(
    DesktopLayoutPreference preference,
  ) async {
    _layoutPreference = preference;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return;
    }
    await windowManager.setSize(_targetWindowSize);
    if (_mode == DisplayMode.desktopWidget) {
      await WindowNative.positionDesktopWidget();
    }
  }

  Size get _targetWindowSize {
    return _layoutPreference == DesktopLayoutPreference.horizontal
        ? const Size(_kHorizontalWindowWidth, _kHorizontalWindowHeight)
        : const Size(_kWindowWidth, _kWindowHeight);
  }

  /// 把当前 displayMode 落到窗口属性上。
  Future<void> _applyDisplayMode() async {
    // 始终按用户布局偏好恢复窗口尺寸：切换模式或从托盘恢复后，
    // 系统可能因样式变化（如 WS_EX_TOOLWINDOW）而重置窗口尺寸，这里强制还原。
    await windowManager.setSize(_targetWindowSize);
    switch (_mode) {
      case DisplayMode.alwaysOnTop:
        // 置顶模式：普通顶层窗口、显示任务栏按钮并保持置顶。
        await clearDesktopWidgetRegions();
        await WindowNative.setDesktopWidget(false);
        // 桌面模式使用真正 frameless 客户区；退出时恢复 hidden 标题栏，
        // 让置顶小窗继续拥有系统缩放边界和既有窗口行为。
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        await WindowNative.setToolWindow(false);
        await windowManager.setAlwaysOnBottom(false);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSkipTaskbar(false);
      case DisplayMode.desktopWidget:
        // 桌面悬浮插件：保持不透明、无 parent/owner 的 Flutter 顶层窗口，
        // 并插到最高 Explorer 桌面合成层正上方。Win+D 期间由原生
        // sentinel/helper 临时跟随被抬起的桌面，平时仍允许普通应用覆盖。
        await windowManager.setAlwaysOnBottom(false);
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setSkipTaskbar(true);
        // TitleBarStyle.hidden 在 Windows 插件内仍会保留约 8px 的
        // WM_NCCALCSIZE 缩放边界。真正 frameless 才能让 360×680
        // Flutter 客户区与外窗一致，避免磁贴周围露出黑色非客户区。
        await windowManager.setAsFrameless();
        await windowManager.setHasShadow(false);
        await WindowNative.setToolWindow(false);
        final attached = await WindowNative.setDesktopWidget(true);
        if (!attached) {
          stderr.writeln(
            '[QW] desktop widget layer setup failed; using normal window',
          );
        }
        await WindowNative.positionDesktopWidget();
    }
  }

  @override
  Future<void> hideToTray() async {
    // 真正隐藏而不是最小化；Shell 托盘图标独立存在并继续投递点击消息。
    await windowManager.hide();
  }

  @override
  Future<void> showFromTray() async {
    // 恢复后重放当前模式。显式“显示”会临时聚焦窗口；用户切回其他
    // 应用后，桌面悬浮模式仍回到允许普通应用覆盖的桌面层。
    await windowManager.show();
    await _applyDisplayMode();
    await windowManager.focus();
  }

  @override
  Future<void> quit() async {
    // 退出前先移除监听、销毁托盘，避免任务栏/托盘残留图标。
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    // windowManager.destroy 不会终止 Dart isolate，需 exit 确保进程结束。
    // backend 子进程由启动脚本在其 finally 中管理，这里不触碰它。
    exit(0);
  }
}

/// conditional import 协议要求的工厂函数：返回原生实现。
DesktopController createDesktopController() => IoDesktopController();

DesktopLayoutPreference _initialLayoutPreference() {
  const layout = String.fromEnvironment(
    'QUOTA_LAYOUT_MODE',
    defaultValue: 'auto',
  );
  return switch (layout) {
    'horizontal' => DesktopLayoutPreference.horizontal,
    'vertical' => DesktopLayoutPreference.vertical,
    _ => DesktopLayoutPreference.automatic,
  };
}
