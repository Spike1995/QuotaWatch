// ============================================================================
// desktop_controller_web.dart - Web 上的桌面控制器空实现（也是默认实现）
// ============================================================================
//
// 【阶段 9 学习要点】
// - 这是 conditional import 的"兜底"实现：当不在原生平台时使用它。
// - 所有方法都是 no-op（什么都不做），保证 Web 构建不会因为缺少
//   window_manager 这类原生插件而失败。
// - 函数签名 createDesktopController() 是接口与实现之间的"协议"：
//   desktop_controller.dart 用条件导入从对应文件拿这个函数。

import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'desktop_controller.dart';

/// Web 上的控制器：什么都不做。浏览器里没有"原生窗口/托盘"概念。
class WebDesktopController implements DesktopController {
  const WebDesktopController();

  static final ValueNotifier<DisplayMode> _displayModeListenable =
      ValueNotifier(DisplayMode.alwaysOnTop);

  @override
  Future<void> init() async {
    // 故意留空：Web 平台无需窗口管理。
  }

  @override
  Future<void> hideToTray() async {}

  @override
  Future<void> showFromTray() async {}

  @override
  Future<void> setDisplayMode(DisplayMode mode) async {}

  @override
  Future<void> setLayoutPreference(
    DesktopLayoutPreference preference,
  ) async {}

  @override
  DisplayMode get displayMode => DisplayMode.alwaysOnTop;

  @override
  ValueListenable<DisplayMode> get displayModeListenable =>
      _displayModeListenable;

  @override
  Future<void> setDesktopWidgetRegions(
    List<Rect> regions, {
    required double devicePixelRatio,
    double cornerRadius = 18,
  }) async {}

  @override
  Future<void> clearDesktopWidgetRegions() async {}

  @override
  Future<void> setOpacity(double opacity) async {}

  @override
  Future<void> quit() async {}
}

/// conditional import 协议要求的工厂函数。
DesktopController createDesktopController() => const WebDesktopController();
