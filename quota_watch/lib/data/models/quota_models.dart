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
// 后端返回的额度 JSON 解析后填进这些类；UI 代码直接消费这些模型。
//
// ============================================================================

// 模型需要 Color 类型来提供服务商品牌色，因此引入 Flutter Material 库。
import 'package:flutter/material.dart';

/// `enum` 是一组有限、固定的选项。
/// 这里用 Provider.codex / Provider.kimi / Provider.glm，避免到处手写字符串并拼错。
enum Provider {
  // 每个枚举值都可以调用下面定义的 const 构造函数，保存自己的显示名称和描述。
  codex('Codex', 'OpenAI ChatGPT 套餐'),
  kimi('Kimi', 'Moonshot Kimi 编程套餐'),
  glm('GLM', '智谱 GLM Coding Plan');

  // `final` 字段只能在对象创建时赋值一次，之后不能被重新指定。
  // `String` 是文字类型；displayName 和 description 是这两个字段的名字。
  final String displayName;
  final String description;

  // 枚举的构造函数使用位置参数：第一个参数填 displayName，第二个填 description。
  // `const` 说明这些枚举对象可以在编译期创建，运行时不会反复生成同一个值。
  const Provider(this.displayName, this.description);

  // factory/解析函数把 JSON 中的字符串转换成 Dart 枚举。
  // 遇到未知服务商时立即报错，避免错误数据悄悄进入 UI。
  static Provider fromJson(String value) {
    for (final provider in Provider.values) {
      if (provider.name == value) return provider;
    }
    throw FormatException('不支持的 provider：$value');
  }

  /// 每家的主题色（在 app_theme 里定义的常量）
  // getter 用 `get` 声明，看起来像读取字段，实际可以根据当前枚举值计算结果。
  Color get brandColor {
    // 这里用 Dart 3 的 switch 表达式：每个箭头右侧就是对应分支的结果。
    return switch (this) {
      Provider.codex => const Color(0xFF10A37F),
      Provider.kimi => const Color(0xFF1D9BF0),
      Provider.glm => const Color(0xFF615CED),
    };
  }

  /// 每家的 logo（先用首字母占位，阶段 5 再换真实 logo）
  // 字符串可以用下标 `[0]` 取第一个字符；这里仅用于占位图标。
  String get initial => displayName[0];

  /// 每家的官方标识图片资源（assets/logos/README.md 记录了来源与授权）。
  /// Image.asset 加载失败时，UI 会回退到上面的 initial 占位字母。
  String get logoAsset {
    return switch (this) {
      Provider.codex => 'assets/logos/codex.png',
      Provider.kimi => 'assets/logos/kimi.png',
      Provider.glm => 'assets/logos/glm.png',
    };
  }
}

/// 查询状态也是枚举：它描述“查询结果处于哪一种状态”，而不是具体数据。
enum QuotaStatus {
  ok, // 正常
  degraded, // 部分窗口数据缺失
  error, // 查询失败
  loading, // 加载中
  unknown, // 未配置（没填 key）

  ;

  static QuotaStatus fromJson(String value) {
    for (final status in QuotaStatus.values) {
      if (status.name == value) return status;
    }
    throw FormatException('不支持的 quota status：$value');
  }
}

/// 单个额度窗口（比如 Codex 的"5 小时窗口"、"7 天窗口"）
class QuotaWindow {
  // `class` 定义一个可以创建对象的类型；这里一个对象代表一个时间窗口。
  // `String` 表示文字，`double` 表示可带小数的数字。
  final String label; // "5 小时窗口"、"周窗口"
  final double used; // 已用
  final double limit; // 上限
  final String unit; // "tokens"、"次"、"%"（用来显示单位）
  // 类型名后的 `?` 表示可空：某些服务商可能没有重置时间或备注。
  final DateTime? resetAt; // 重置时间
  final String? note; // 备注（比如 GLM 的"高峰3倍扣费"）

  // `{}` 表示命名参数；`required` 表示调用构造函数时必须提供该参数。
  // resetAt/note 没有 required，所以调用者可以省略它们，它们的值就是 null。
  QuotaWindow({
    required this.label,
    required this.used,
    required this.limit,
    required this.unit,
    this.resetAt,
    this.note,
  });

  // factory 构造函数负责把一段 JSON 对象转换成 QuotaWindow。
  // JSON 数字会先以 num 读取，再统一转成模型需要的 double。
  factory QuotaWindow.fromJson(Map<String, dynamic> json) {
    return QuotaWindow(
      label: json['label'] as String,
      used: (json['used'] as num).toDouble(),
      limit: (json['limit'] as num).toDouble(),
      unit: json['unit'] as String,
      resetAt: _optionalDateTime(json['resetAt'], 'resetAt'),
      note: json['note'] as String?,
    );
  }

  // 派生属性：剩余。getter 每次读取时根据 used 和 limit 计算，不额外存一份副本。
  // `clamp` 把结果限制在 0 到 limit 之间，避免出现负剩余或超过上限的显示值。
  double get remaining => (limit - used).clamp(0, limit);

  // 派生属性：使用百分比（0-100）。limit 为 0 时先返回 0，避免除以 0。
  double get usedPercent {
    if (limit == 0) return 0;
    return (used / limit * 100).clamp(0, 100);
  }

  // bool 是只有 true/false 两种值的类型；这里把告警规则集中在模型中。
  bool get isWarning => usedPercent >= 80 && usedPercent < 95;

  // 接近耗尽与完全耗尽要分开：95%～不足 100% 显示“紧张”。
  bool get isCritical => usedPercent >= 95 && usedPercent < 100;

  // 达到或超过 100% 时显示“耗尽”。usedPercent 已被钳制到最高 100。
  bool get isExhausted => usedPercent >= 100;

  // `int?` 表示“整数或 null”；没有 resetAt 时就没有倒计时。
  int? get resetsInSeconds {
    if (resetAt == null) return null;
    // `!` 是空断言：因为上一行已经判断不为 null，告诉 Dart 这里可以安全使用实际值。
    return resetAt!.difference(DateTime.now()).inSeconds.clamp(0, 1 << 31);
  }

  // copyWith 是不可变数据常用模式：不修改旧对象，而是复制它并替换指定字段。
  // 可选命名参数仍然是 nullable；调用者不传某字段时用原对象的值。
  QuotaWindow copyWith({
    String? label,
    double? used,
    double? limit,
    String? unit,
    DateTime? resetAt,
    String? note,
  }) {
    return QuotaWindow(
      // `??` 是空合并运算符：左侧不为 null 就使用左侧，否则使用右侧。
      label: label ?? this.label,
      used: used ?? this.used,
      limit: limit ?? this.limit,
      unit: unit ?? this.unit,
      resetAt: resetAt ?? this.resetAt,
      note: note ?? this.note,
    );
  }
}

/// 恢复额度（Codex 官方 app-server credits 对象的归一化形态）
class QuotaCredits {
  final bool hasCredits; // 是否有恢复额度
  final bool unlimited; // 是否无限
  final String? balance; // 官方返回的余量文本（仅展示用）

  const QuotaCredits({
    required this.hasCredits,
    required this.unlimited,
    this.balance,
  });

  // JSON 对象转 QuotaCredits；字段类型不符即视为契约漂移并抛 FormatException。
  factory QuotaCredits.fromJson(Map<String, dynamic> json) {
    final hasCredits = json['hasCredits'];
    final unlimited = json['unlimited'];
    final balance = json['balance'];
    if (hasCredits is! bool || unlimited is! bool) {
      throw const FormatException('credits 缺少 hasCredits/unlimited 布尔字段');
    }
    if (balance != null && balance is! String) {
      throw const FormatException('credits.balance 必须是字符串');
    }
    return QuotaCredits(
      hasCredits: hasCredits,
      unlimited: unlimited,
      balance: balance,
    );
  }

  // 可空字段的入口：键缺失或为 null 时返回 null，类型不对则明确失败。
  static QuotaCredits? fromJsonOrNull(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw const FormatException('credits 必须是对象');
    }
    return QuotaCredits.fromJson(value);
  }
}

enum ResetAllowanceSource {
  provider,
  manual;

  static ResetAllowanceSource fromJson(String value) {
    return switch (value) {
      'provider' => ResetAllowanceSource.provider,
      'manual' => ResetAllowanceSource.manual,
      _ => throw FormatException('不支持的 reset allowance source：$value'),
    };
  }
}

/// 可额外重置额度的次数与有效期。
///
/// `manual` 明确表示本机备注，避免把用户输入伪装成 Provider 官方数据。
class ResetAllowance {
  final int count;
  final DateTime? expiresAt;
  final ResetAllowanceSource source;

  const ResetAllowance({
    required this.count,
    required this.source,
    this.expiresAt,
  });

  factory ResetAllowance.fromJson(Map<String, dynamic> json) {
    final count = json['count'];
    if (count is! int || count < 0) {
      throw const FormatException('resetAllowance.count 必须是非负整数');
    }
    return ResetAllowance(
      count: count,
      expiresAt: _optionalDateTime(
        json['expiresAt'],
        'resetAllowance.expiresAt',
      ),
      source: ResetAllowanceSource.fromJson(json['source'] as String),
    );
  }

  static ResetAllowance? fromJsonOrNull(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw const FormatException('resetAllowance 必须是对象');
    }
    return ResetAllowance.fromJson(value);
  }
}

/// 一家服务商的完整额度信息（前端最终使用的"聚合对象"）
class ProviderQuota {
  // ProviderQuota 把一家服务商的多个 QuotaWindow 聚合成页面可使用的完整对象。
  final Provider provider;
  final String planName; // "ChatGPT Plus"、"Kimi Moderato"、"GLM Pro"
  final String? planType; // 原始 plan_type（可选）
  final DateTime? expiresAt; // 订阅到期日（Codex 有，Kimi/GLM 可能没有）
  // `List<QuotaWindow>` 表示“QuotaWindow 对象组成的列表”，尖括号是泛型类型。
  final List<QuotaWindow> windows;
  final QuotaStatus status;
  final String? errorMessage;
  final DateTime? fetchedAt; // 本次查询时间
  final QuotaCredits? credits; // 恢复额度（可选，目前只有 Codex 返回）
  final ResetAllowance? resetAllowance; // 可重置次数（官方或明确标注的手动备注）

  ProviderQuota({
    required this.provider,
    required this.planName,
    required this.windows,
    this.planType,
    this.expiresAt,
    // `=` 提供默认值：调用者不传 status 时，默认认为查询正常。
    this.status = QuotaStatus.ok,
    this.errorMessage,
    this.fetchedAt,
    this.credits,
    this.resetAllowance,
  });

  // ProviderQuota.fromJson 是 JSON 数据进入前端统一模型的入口。
  factory ProviderQuota.fromJson(Map<String, dynamic> json) {
    final rawWindows = json['windows'];
    if (rawWindows is! List) {
      throw const FormatException('windows 必须是数组');
    }

    final windows = rawWindows.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('windows 中的每一项都必须是对象');
      }
      return QuotaWindow.fromJson(item);
    }).toList();

    return ProviderQuota(
      provider: Provider.fromJson(json['provider'] as String),
      planName: json['planName'] as String,
      planType: json['planType'] as String?,
      expiresAt: _optionalDateTime(json['expiresAt'], 'expiresAt'),
      windows: windows,
      status: QuotaStatus.fromJson((json['status'] as String?) ?? 'ok'),
      errorMessage: json['errorMessage'] as String?,
      fetchedAt: _optionalDateTime(json['fetchedAt'], 'fetchedAt'),
      credits: QuotaCredits.fromJsonOrNull(json['credits']),
      resetAllowance: ResetAllowance.fromJsonOrNull(json['resetAllowance']),
    );
  }

  // `isEmpty` 检查列表是否没有元素；三元运算符 `条件 ? A : B` 在两种结果中选一个。
  QuotaWindow? get primaryWindow => windows.isEmpty ? null : windows.first;

  // 派生属性：是否未配置（没填 key）
  bool get isUnknown => status == QuotaStatus.unknown;

  // 阶段 6 准备：过期判断。fetchedAt 距 now 超过阈值则视为“可能已过期”，
  // 供未来 UI 在失败回退旧值时提示用户。与后端 QuotaAggregator.is_stale 口径一致。
  // `now` 参数仅为可测试性注入；默认取当前时间。无 fetchedAt 时视为过期。
  bool isStale({DateTime? now, Duration threshold = staleThreshold}) {
    if (fetchedAt == null) return true;
    final reference = now ?? DateTime.now();
    return reference.difference(fetchedAt!) > threshold;
  }

  // 默认过期阈值：6 小时（与后端一致）。
  static const Duration staleThreshold = Duration(hours: 6);
}

// JSON 中的时间使用 ISO 8601 字符串，例如 2026-07-22T12:00:00Z。
// 可选字段为 null 时直接返回 null；格式错误时给出包含字段名的错误。
DateTime? _optionalDateTime(Object? value, String fieldName) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('$fieldName 必须是 ISO 8601 字符串');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$fieldName 不是有效时间：$value');
  }
  return parsed;
}
