// ============================================================================
// app_theme.dart - 全局主题（颜色、字体、圆角）
// ============================================================================
//
// 【阶段 1 学习要点】
// - ThemeData 集中管理视觉风格，改一处全局生效
// - ColorScheme 是 Material 3 的颜色体系（primary/secondary/surface...）
// - 把颜色单独抽出来，方便后面做"每家服务一种主题色"
//
// ============================================================================

import 'package:flutter/material.dart';

class AppTheme {
  // 三家服务的主题色（后面 UI 会用到）
  static const codexColor = Color(0xFF10A37F);   // OpenAI 绿
  static const kimiColor = Color(0xFF1D9BF0);    // Kimi 蓝
  static const glmColor = Color(0xFF615CED);     // 智谱紫

  // 通用色
  static const warningColor = Color(0xFFF59E0B); // 额度告警（橙）
  static const dangerColor = Color(0xFFEF4444);  // 额度耗尽（红）
  static const successColor = Color(0xFF22C55E); // 额度充足（绿）

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),  // 主色：靛蓝
      brightness: Brightness.light,
    );
    return _build(colorScheme);
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),
      brightness: Brightness.dark,
    );
    return _build(colorScheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: scheme.surfaceContainerHighest.withOpacity(0.5),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
