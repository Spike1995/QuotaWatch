// ============================================================================
// quota_window_block.dart - 单个额度窗口的紧凑信息块（首页卡片与详情页共用）
// ============================================================================
//
// 每个窗口只保留统一名称 + 已用百分比 + 进度条 + 重置时间。
// 格式化规则集中在本文件顶部，全 App 只此一份，避免 Provider 原始标签
// （例如“周窗口”和“Weekly limit”）直接泄漏到界面造成中英文混用。
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/state/quota_state.dart';
import '../../data/models/quota_models.dart';
import 'quota_progress_bar.dart';

String _formatPlainNumber(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

/// 把不同 Provider 的原始标签统一成“时间/用途 + 额度”。
///
/// 原始 label 仍保留在数据模型中，便于解析器测试和诊断；只有表现层做本地化。
String formatQuotaWindowLabel(String rawLabel) {
  final label = rawLabel.trim();
  if (label.isEmpty) return '额度';

  final normalized =
      label.toLowerCase().replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');

  if (normalized.contains('mcp') ||
      normalized.contains('tool') ||
      normalized.contains('工具')) {
    if (normalized.contains('month') || normalized.contains('月')) {
      return '月度工具额度';
    }
    return '工具调用额度';
  }

  if (normalized.contains('weekly') ||
      normalized.contains('week') ||
      normalized.contains('7d') ||
      normalized.contains('7 d') ||
      normalized.contains('7 day') ||
      normalized.contains('7 天') ||
      normalized.contains('周')) {
    return '7 天额度';
  }

  if (normalized.contains('daily') ||
      normalized.contains('day cap') ||
      normalized.contains('每日')) {
    return '每日额度';
  }

  String? durationLabel(RegExp pattern, String unit) {
    final match = pattern.firstMatch(normalized);
    final value = match?.group(1);
    return value == null ? null : '$value $unit额度';
  }

  return durationLabel(
          RegExp(r'(\d+(?:\.\d+)?)\s*(?:hours?|hrs?|h)\b'), '小时') ??
      durationLabel(RegExp(r'(\d+(?:\.\d+)?)\s*小时'), '小时') ??
      durationLabel(RegExp(r'(\d+(?:\.\d+)?)\s*(?:days?|d)\b'), '天') ??
      durationLabel(RegExp(r'(\d+(?:\.\d+)?)\s*天'), '天') ??
      durationLabel(
        RegExp(r'(\d+(?:\.\d+)?)\s*(?:minutes?|mins?|m)\b'),
        '分钟',
      ) ??
      durationLabel(RegExp(r'(\d+(?:\.\d+)?)\s*分钟'), '分钟') ??
      durationLabel(
        RegExp(r'(\d+(?:\.\d+)?)\s*(?:seconds?|secs?|s)\b'),
        '秒',
      ) ??
      durationLabel(RegExp(r'(\d+(?:\.\d+)?)\s*秒'), '秒') ??
      _fallbackQuotaLabel(label, normalized);
}

String _fallbackQuotaLabel(String label, String normalized) {
  if (normalized.contains('token')) return 'Token 额度';

  final cleaned = label
      .replaceAll('_', ' ')
      .replaceAll(
        RegExp(r'\b(limit|window|cap)\b', caseSensitive: false),
        '',
      )
      .replaceAll('窗口', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return '额度';
  if (cleaned.endsWith('额度')) return cleaned;
  final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(cleaned);
  return hasChinese ? '$cleaned额度' : '$cleaned 额度';
}

String formatUsedPercent(QuotaWindow window) =>
    '已用 ${_formatPlainNumber(window.usedPercent)}%';

/// 重置时间文案：超过 24 小时的（周/7 天窗口）直接写到具体某一天，
/// 不再换算成"一百多个小时"；24 小时内仍用倒计时，临期更直观。
String formatResetText(QuotaWindow window) {
  if (window.resetAt == null) return '重置时间未知';
  final seconds = window.resetsInSeconds ?? 0;
  if (seconds <= 0) return '即将重置';
  if (seconds > 24 * 3600) {
    // `!` 是空断言：resetsInSeconds 依赖 resetAt，到这里一定不为 null。
    final date = window.resetAt!;
    return '${date.month}月${date.day}日（${weekdayLabel(date)}）重置';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '$hours小时$minutes分后重置';
  return '$minutes分钟后重置';
}

/// DateTime.weekday 从 1（周一）数到 7（周日），按下标换成中文标签。
String weekdayLabel(DateTime date) {
  const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return labels[date.weekday - 1];
}

class QuotaWindowBlock extends ConsumerWidget {
  final QuotaWindow window;
  final Color brandColor;
  final bool quiet;

  const QuotaWindowBlock({
    super.key,
    required this.window,
    required this.brandColor,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 阶段 11：倒计时文案依赖 DateTime.now()，每分钟 tick 触发重算，
    // 悬浮窗不放任何手动入口时文案也会随时间推进。
    ref.watch(tickerProvider);
    final theme = Theme.of(context);
    final severity = quotaSeverityColor(
      window,
      brandColor,
      brightness: theme.brightness,
    );
    final displayLabel = formatQuotaWindowLabel(window.label);
    final usedText = formatUsedPercent(window);
    final resetText = formatResetText(window);

    return Semantics(
      container: true,
      label: '$displayLabel，$usedText，$resetText',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：统一窗口名 + “已用 X%”徽标（颜色与进度条同源）。
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (quiet)
                Text(
                  usedText,
                  style: TextStyle(
                    color: severity,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: severity.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: severity.withValues(alpha: 0.24),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    usedText,
                    style: TextStyle(
                      color: severity,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          QuotaProgressBar(window: window, brandColor: brandColor),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 13,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  resetText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
