// ============================================================================
// window_drag_area.dart - 无标题栏窗口的拖拽区
// ============================================================================
//
// 【阶段 9 学习要点】
// - 去掉原生标题栏后（desktop_controller_io 里 titleBarStyle hidden），
//   窗口就没有"可拖动的把手"了。需要手动给一块 UI 区域赋予"拖动窗口"的能力。
// - window_manager 提供 DragToResizeArea：按住它拖动即可移动整个窗口。
// - 同样用 conditional import 隔离 Web：浏览器里没有原生窗口可拖，
//   直接把子组件原样返回。

import 'package:flutter/widgets.dart';

import 'window_drag_area_web.dart'
    if (dart.library.io) 'window_drag_area_io.dart' as impl;

/// 一个让用户按住即可拖动整个窗口的区域。
///
/// 用法：把它包在 AppBar 或自定义标题栏外层。
/// Web 上等同于直接返回 child（无效果）。
class WindowDragArea extends StatelessWidget {
  final Widget child;

  const WindowDragArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 委托给平台实现：原生用 DragToResizeArea，Web 直接返回 child。
    return impl.buildDragArea(child);
  }
}
