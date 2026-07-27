// Web 兜底实现：没有原生窗口可拖，直接返回子组件。
import 'package:flutter/widgets.dart';

/// conditional import 协议：返回 child 本身，无任何包裹。
Widget buildDragArea(Widget child) => child;
