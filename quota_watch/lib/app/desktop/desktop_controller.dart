// ============================================================================
// desktop_controller.dart - 桌面控制器接口
// ============================================================================
//
// 【阶段 9 学习要点】
// - conditional import（条件导入）：在编译期用 `if (dart.library.io)` 选择
//   不同实现，让 Web 构建不会因为引入 window_manager 而失败。
// - Dart 的 io 库只在原生平台（windows/macos/linux/android/ios）可用，
//   Web 上不存在；因此把"需要 io 的桌面窗口代码"隔离到单独文件。
//
// 本文件只定义接口（抽象类）+ 用条件导入拿一个工厂函数。
// 真正的窗口逻辑在 desktop_controller_io.dart，Web 空实现在
// desktop_controller_web.dart（也是默认实现，原生平台会被 io 版覆盖）。
// main.dart 只依赖这里的 DesktopController，不直接 import 平台实现。

import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'desktop_controller_web.dart'
    if (dart.library.io) 'desktop_controller_io.dart' as impl;

/// 桌面控制器：负责窗口尺寸/无边框/置顶 与 系统托盘。
///
/// 在 Windows 上是真实现；在 Web 上是空实现（所有方法 no-op），
/// 这样同一份 main.dart 能同时构建 Web 和 Windows。
abstract class DesktopController {
  /// 单例入口。具体实例由 conditional import 选定的 impl 工厂提供。
  static final DesktopController instance = impl.createDesktopController();

  /// 应用启动时调用一次：初始化窗口与托盘。Web 上为 no-op。
  Future<void> init();

  /// 把窗口隐藏到托盘（不退出进程）。Web 上为 no-op。
  Future<void> hideToTray();

  /// 从托盘恢复显示窗口。Web 上为 no-op。
  Future<void> showFromTray();

  /// 切换显示模式：置顶小窗 / 桌面悬浮插件。Web 上为 no-op。
  Future<void> setDisplayMode(DisplayMode mode);

  /// 当前显示模式（仅 Windows 有意义，Web 恒返回置顶）。
  DisplayMode get displayMode;

  /// 可监听的显示模式；页面据此在桌面组件模式隐藏应用标题栏。
  ValueListenable<DisplayMode> get displayModeListenable;

  /// 根据用户选择把 Windows 小组件切成竖条或横条尺寸；其他平台 no-op。
  Future<void> setLayoutPreference(DesktopLayoutPreference preference);

  /// 把 Windows 桌面组件裁成若干圆角内容区域；Web 上为 no-op。
  Future<void> setDesktopWidgetRegions(
    List<Rect> regions, {
    required double devicePixelRatio,
    double cornerRadius = 18,
  });

  /// 恢复完整矩形窗口；设置页、置顶小窗和非卡片状态使用。
  Future<void> clearDesktopWidgetRegions();

  /// 设置整窗不透明度（0.0～1.0）。这是原生合成器能力：命中区域不变，
  /// 淡出不影响点击命中。闲置淡出用；Web 上为 no-op。
  Future<void> setOpacity(double opacity);

  /// 完全退出应用（销毁窗口与托盘）。Web 上为 no-op。
  Future<void> quit();
}

/// 窗口显示模式。
enum DisplayMode {
  /// 置顶小窗：贴顶、不透明、随时浮在所有窗口之上。
  alwaysOnTop,

  /// 桌面悬浮插件：位于 Windows 桌面正上方的非置顶窗口。
  /// 普通应用会覆盖它，返回桌面时仍存在。
  desktopWidget,
}

enum DesktopLayoutPreference {
  automatic,
  vertical,
  horizontal,
}
