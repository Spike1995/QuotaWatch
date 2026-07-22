// ============================================================================
// quota_models.dart - 数据模型（前后端契约）
// ============================================================================
//
// 【阶段 1 学习要点】
// - 用 class 定义数据结构，类似其他语言的 interface/struct
// - Dart 3 的 class 构造函数语法：参数默认值、命名参数、required 关键字
// - copyWith() 是 Flutter 项目里改数据的标准模式（数据不可变，安全）
//
// 【重要】这个文件是【前端唯一的数据契约】。
// 阶段 3/5 读取 fixture 或本地假后端 JSON 时，解析后填进这些类即可，
// UI 代码完全不用改。
//
// ============================================================================

import 'package:flutter/material.dart';

/// 服务商枚举（用 enum 而不是字符串，编译器能帮我们查错）
enum Provider {
  codex('Codex', 'OpenAI ChatGPT 套餐'),
  kimi('Kimi', 'Moonshot Kimi 编程套餐'),
  glm('GLM', '智谱 GLM Coding Plan');

  final String displayName;
  final String description;
  const Provider(this.displayName, this.description);

  /// 每家的主题色（在 app_theme 里定义的常量）
  Color get brandColor {
    // 这里用 switch 表达式（Dart 3 语法）
    return switch (this) {
      Provider.codex => const Color(0xFF10A37F),
      Provider.kimi => const Color(0xFF1D9BF0),
      Provider.glm => const Color(0xFF615CED),
    };
  }

  /// 每家的 logo（先用首字母占位，阶段 5 再换真实 logo）
  String get initial => displayName[0];
}

/// 查询状态
enum QuotaStatus {
  ok,        // 正常
  degraded,  // 部分窗口数据缺失
  error,     // 查询失败
  loading,   // 加载中
  unknown,   // 未配置（没填 key）
}

/// 单个额度窗口（比如 Codex 的"5 小时窗口"、"7 天窗口"）
class QuotaWindow {
  final String label;        // "5 小时窗口"、"周窗口"
  final double used;         // 已用
  final double limit;        // 上限
  final String unit;         // "tokens"、"次"、"%"（用来显示单位）
  final DateTime? resetAt;   // 重置时间
  final String? note;        // 备注（比如 GLM 的"高峰3倍扣费"）

  QuotaWindow({
    required this.label,
    required this.used,
    required this.limit,
    required this.unit,
    this.resetAt,
    this.note,
  });

  // 派生属性：剩余
  double get remaining => (limit - used).clamp(0, limit);

  // 派生属性：使用百分比（0-100）
  double get usedPercent {
    if (limit == 0) return 0;
    return (used / limit * 100).clamp(0, 100);
  }

  // 派生属性：是否告警（>80%）
  bool get isWarning => usedPercent >= 80 && usedPercent < 95;

  // 派生属性：是否耗尽/接近耗尽
  bool get isCritical => usedPercent >= 95;

  // 派生属性：剩余时间（秒），用于倒计时
  int? get resetsInSeconds {
    if (resetAt == null) return null;
    return resetAt!.difference(DateTime.now()).inSeconds.clamp(0, 1 << 31);
  }

  QuotaWindow copyWith({
    String? label,
    double? used,
    double? limit,
    String? unit,
    DateTime? resetAt,
    String? note,
  }) {
    return QuotaWindow(
      label: label ?? this.label,
      used: used ?? this.used,
      limit: limit ?? this.limit,
      unit: unit ?? this.unit,
      resetAt: resetAt ?? this.resetAt,
      note: note ?? this.note,
    );
  }
}

/// 一家服务商的完整额度信息（前端最终使用的"聚合对象"）
class ProviderQuota {
  final Provider provider;
  final String planName;         // "ChatGPT Plus"、"Kimi Moderato"、"GLM Pro"
  final String? planType;        // 原始 plan_type（可选）
  final DateTime? expiresAt;     // 订阅到期日（Codex 有，Kimi/GLM 可能没有）
  final List<QuotaWindow> windows;
  final QuotaStatus status;
  final String? errorMessage;
  final DateTime? fetchedAt;     // 本次查询时间

  ProviderQuota({
    required this.provider,
    required this.planName,
    required this.windows,
    this.planType,
    this.expiresAt,
    this.status = QuotaStatus.ok,
    this.errorMessage,
    this.fetchedAt,
  });

  // 主窗口（取第一个，通常是 5h 短窗口）
  QuotaWindow? get primaryWindow =>
      windows.isEmpty ? null : windows.first;

  // 派生属性：是否未配置（没填 key）
  bool get isUnknown => status == QuotaStatus.unknown;
}
