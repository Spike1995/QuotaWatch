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

// ThemeData、ColorScheme、Color 等全局视觉类型来自 Material 库。
import 'package:flutter/material.dart';

// 主题集中在一个类中，页面只读取主题，不各自硬编码整套视觉规则。
class AppTheme {
  // 统一视觉骨架：深海蓝负责结构，安全绿只表达正常/可信状态。
  static const vaultBlue = Color(0xFF1E3A5F);
  static const slateBlue = Color(0xFF334155);
  // emerald-700 在浅色卡片上的正文对比度更稳，暗色主题另用更亮变体。
  static const secureGreen = Color(0xFF047857);

  // 三家服务的主题色（后面 UI 会用到）
  static const codexColor = Color(0xFF10A37F); // OpenAI 绿
  static const kimiColor = Color(0xFF1D9BF0); // Kimi 蓝
  static const glmColor = Color(0xFF615CED); // 智谱紫

  // 通用色
  static const warningColor = Color(0xFFF59E0B); // 额度告警（橙）
  static const dangerColor = Color(0xFFEF4444); // 额度耗尽（红）
  static const successColor = Color(0xFF22C55E); // 额度充足（绿）

  // 卡片圆角的唯一来源：Flutter 卡片、原生窗口区域通道共用同一数值，
  // 保证屏幕上的卡片形状与 Windows 裁剪出的圆角区域一致。
  static const double cardRadius = 18;

  // `static` 方法可以直接写 AppTheme.light() 调用；返回值类型是 ThemeData。
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: vaultBlue,
      brightness: Brightness.light,
    ).copyWith(
      primary: vaultBlue,
      secondary: slateBlue,
      tertiary: secureGreen,
      surface: const Color(0xFFF4F7FB),
      surfaceContainerHighest: const Color(0xFFFFFFFF),
      outline: const Color(0xFF66758A),
      outlineVariant: const Color(0xFFD2DAE5),
    );
    return _build(colorScheme);
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: vaultBlue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF8EB9E8),
      secondary: const Color(0xFFA9B8CA),
      tertiary: const Color(0xFF4FD1A5),
      surface: const Color(0xFF0F172A),
      surfaceContainerHighest: const Color(0xFF162238),
      outline: const Color(0xFFA7B3C3),
      outlineVariant: const Color(0xFF3A4A61),
    );
    return _build(colorScheme);
  }

  // `_build` 是私有辅助方法：亮色和暗色共用卡片、AppBar 等结构，只更换 ColorScheme。
  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 随包字体子集保证 Flutter Web 发布包离线渲染中文，不依赖系统 fallback。
      fontFamily: 'NotoSansSCSubset',
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        // 桌面磁贴只保留约 45%（暗色）/ 53%（亮色）不透明度；
        // 文字仍使用高对比的 onSurface/onSurfaceVariant。
        // 桌面模式还会移除磁贴背后的页面底色，让这里的 alpha 真正透出桌面。
        color: scheme.brightness == Brightness.dark
            ? const Color(0x68162238)
            : const Color(0x76FFFFFF),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface.withValues(alpha: 0.94),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: 'NotoSansSCSubset',
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        thickness: 0.8,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }
}
