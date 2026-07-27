// Windows 原生实现：用 window_manager 的 DragToMoveArea 赋予移动能力。
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// conditional import 协议：把 child 包进 DragToMoveArea，
/// 用户按住该区域即可拖动整个窗口（无标题栏窗口必需）。
/// 注意：DragToMoveArea 负责"移动"窗口；DragToResizeArea 才是"拉伸边缘"，
/// 二者不要混用。
Widget buildDragArea(Widget child) {
  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
    return child;
  }
  return DragToMoveArea(child: child);
}
