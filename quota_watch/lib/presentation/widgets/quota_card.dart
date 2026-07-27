// ============================================================================
// quota_card.dart - 单家额度卡片（首页列表项）
// ============================================================================
//
// 一张卡片直接展示该服务商的【全部额度窗口】，无需再点进详情页：
// 头部是官方标识 + 套餐 + 状态，下面每个窗口一个 QuotaWindowBlock
// （统一名称 + 已用百分比 + 进度条 + 重置日期），窗口之间用分隔线隔开。
// onTap 仍保留为可选参数，供需要跳转的场景（和卡片语义测试）使用。
//
// 阶段 11：seamless（桌面悬浮）模式下不再创建 BackdropFilter——Flutter
// 的模糊只能作用在自身 surface 上，模糊不到桌面壁纸，纯属 GPU 浪费。
//
// 阶段 12：悬浮窗"无感"化。seamless 未 hover（expanded == false）时渲染
// 紧凑单行（logo + 名称 + 主窗口百分比 + 细进度条 + 状态圆点）；hover
// 展开为完整卡片。面板更透明（alpha 0.65）、边框更淡、无投影；状态
// "充足"时百分比/圆点/进度条用 muted 色，只有异常才着彩色。
//
// ============================================================================

import 'dart:ui';

// 组件使用 Material 的 InkWell、Text 等控件。
import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import '../../data/models/quota_models.dart';
import 'provider_logo.dart';
import 'quota_window_block.dart';

class QuotaCard extends StatelessWidget {
  // 这个卡片只负责把传入的 quota 显示出来，不自己读取数据。
  final ProviderQuota quota;
  // VoidCallback 表示“没有参数、没有返回值的函数”。`?` 表示点击处理可以省略。
  final VoidCallback? onTap;
  // 桌面组件去掉整块面板后使用更安静的边框、状态和阴影。
  final bool seamless;
  // 阶段 12：seamless 时 false 渲染紧凑单行，true 渲染完整卡片；
  // 普通模式忽略此参数，始终完整卡片。
  final bool expanded;

  const QuotaCard({
    super.key,
    required this.quota,
    this.onTap,
    this.seamless = false,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppTheme.cardRadius);
    final baseTileColor =
        theme.cardTheme.color ?? scheme.surfaceContainerHighest;
    // 阶段 12：seamless 面板再降不透明度，日常三条紧凑行更"无感"。
    final tileColor =
        seamless ? baseTileColor.withValues(alpha: 0.65) : baseTileColor;
    final dividerColor = scheme.outlineVariant.withValues(alpha: 0.55);
    // seamless 卡片直接叠在壁纸上：阶段 12 进一步压低边框存在感。
    final glassBorder = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: seamless ? 0.12 : 0.14)
        : scheme.outlineVariant.withValues(alpha: seamless ? 0.25 : 0.60);
    final topSheen = Color.alphaBlend(
      Colors.white.withValues(
        alpha: theme.brightness == Brightness.dark
            ? (seamless ? 0.05 : 0.06)
            : (seamless ? 0.12 : 0.20),
      ),
      tileColor,
    );

    // 整卡语义包含服务商、套餐、状态与每个窗口的简要信息；
    // excludeSemantics 避免子文字被重复朗读。
    // 只有可点击卡片才标记为按钮并提供语义点击动作，不可点击卡片不谎报。
    return Semantics(
      label: _semanticLabel(),
      // container 让每张卡片形成独立语义节点，不和兄弟卡片的文字合并。
      container: true,
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          // 阶段 12：seamless 回到无投影——低透明度面板叠加投影在壁纸上
          // 反而显脏；分离感交给边框与内容本身。
          boxShadow: seamless
              ? const []
              : [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.07,
                    ),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: _maybeBackdropFilter(
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: glassBorder, width: 0.8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    topSheen,
                    tileColor,
                    Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.035),
                      tileColor,
                    ),
                  ],
                ),
              ),
              // InkWell 提供稳定的点击反馈，不改变磁贴尺寸。
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: radius,
                  splashColor: scheme.primary.withValues(alpha: 0.10),
                  highlightColor: scheme.primary.withValues(alpha: 0.055),
                  child: Padding(
                    // 阶段 12：紧凑行用更小的内边距，整行约 36px 高。
                    padding: (seamless && !expanded)
                        ? const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          )
                        : const EdgeInsets.all(12),
                    child: (seamless && !expanded)
                        ? _CompactRow(quota: quota)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 顶部：官方 logo + 套餐名 + 状态标签
                              Row(
                                children: [
                                  ProviderLogo(
                                      provider: quota.provider, size: 32),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          quota.provider.displayName,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            height: 1.15,
                                          ),
                                        ),
                                        Text(
                                          quota.planName,
                                          // 长套餐名单行省略，避免把状态标签挤出屏幕。
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontSize: 10.5,
                                            height: 1.2,
                                          ),
                                        ),
                                        // 可空字段先判断不为 null，才可以显示订阅到期日。
                                        if (quota.expiresAt != null)
                                          Text(
                                            '订阅到期 ${_formatDate(quota.expiresAt!)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: scheme.outline,
                                              fontSize: 9.5,
                                              height: 1.2,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 状态标签同时处理额度充足度和服务商查询状态。
                                  _StatusChip(quota: quota, quiet: seamless),
                                ],
                              ),

                              if (quota.windows.isEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  quota.isUnknown
                                      ? '尚未配置'
                                      : (quota.errorMessage ?? '暂无数据'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ] else ...[
                                // 所有窗口依次完整展示，窗口之间用轻量分隔线区分。
                                const SizedBox(height: 10),
                                for (var i = 0;
                                    i < quota.windows.length;
                                    i++) ...[
                                  if (i > 0) ...[
                                    const SizedBox(height: 8),
                                    Divider(height: 1, color: dividerColor),
                                    const SizedBox(height: 8),
                                  ],
                                  QuotaWindowBlock(
                                    window: quota.windows[i],
                                    // 三家正常进度统一使用安全绿；Provider 品牌色只留在
                                    // Logo 等小面积识别元素，避免整张卡片各自为政。
                                    brandColor: scheme.tertiary,
                                    quiet: seamless,
                                  ),
                                ],
                                // 恢复额度（Codex credits）放在窗口列表之后。
                                if (quota.credits != null) ...[
                                  const SizedBox(height: 8),
                                  Divider(height: 1, color: dividerColor),
                                  const SizedBox(height: 7),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.autorenew_rounded,
                                        size: 14,
                                        color: scheme.outline,
                                      ),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          formatCreditsText(quota.credits!),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                              if (quota.resetAllowance != null) ...[
                                const SizedBox(height: 8),
                                Divider(height: 1, color: dividerColor),
                                const SizedBox(height: 7),
                                _ResetAllowanceRow(
                                  allowance: quota.resetAllowance!,
                                ),
                              ],
                              // 阶段 11：悬浮窗无人盯着刷新按钮，卡片自己交代
                              // 数据是什么时间查到的，配合"刷新失败保留旧卡"判断可信度。
                              if (seamless && quota.fetchedAt != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '更新于 ${_formatFetchedAt(quota.fetchedAt!)}',
                                  maxLines: 1,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.outline,
                                    fontSize: 10,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // seamless 模式跳过 BackdropFilter：Flutter 的模糊只能作用在自身
  // surface 上，悬浮窗背后是桌面壁纸（另一个进程的画面），模糊不到，
  // 纯属 GPU 浪费；普通模式保持原有玻璃模糊。
  Widget _maybeBackdropFilter(Widget child) {
    if (seamless) return child;
    return BackdropFilter(
      // 更透明的表面配合稍强的背景模糊，保留玻璃感与文字可读性。
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: child,
    );
  }

  // “更新于 HH:mm”：本地时间，两位补零。
  String _formatFetchedAt(DateTime fetchedAt) {
    final local = fetchedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _semanticLabel() {
    final parts = <String>[
      '${quota.provider.displayName} ${quota.planName}',
      '状态：${quotaStatusText(quota)}',
      for (final window in quota.windows)
        '${formatQuotaWindowLabel(window.label)}，'
            '${formatUsedPercent(window)}，${formatResetText(window)}',
    ];
    if (quota.credits != null) {
      parts.add(formatCreditsText(quota.credits!));
    }
    if (quota.resetAllowance != null) {
      parts.add(formatResetAllowanceText(quota.resetAllowance!));
    }
    if (quota.windows.isEmpty) {
      parts.add(
        quota.isUnknown ? '尚未配置' : (quota.errorMessage ?? '暂无数据'),
      );
    }
    return parts.join('；');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

// 恢复额度三态文案：无限 > 有余量 > 有但无数值 > 已用完。
String formatCreditsText(QuotaCredits credits) {
  if (credits.unlimited) return '恢复额度：无限';
  if (credits.hasCredits) {
    return credits.balance != null ? '恢复额度：${credits.balance}' : '恢复额度：有';
  }
  return '恢复额度：已用完';
}

String formatResetAllowanceText(ResetAllowance allowance) {
  final expires = allowance.expiresAt == null
      ? '到期时间未记录'
      : '有效至 ${_formatResetDateTime(allowance.expiresAt!)}';
  final source =
      allowance.source == ResetAllowanceSource.manual ? '（手动记录）' : '';
  return '可重置 ${allowance.count} 次 · $expires$source';
}

String _formatResetDateTime(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _ResetAllowanceRow extends StatelessWidget {
  final ResetAllowance allowance;

  const _ResetAllowanceRow({required this.allowance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.restart_alt_rounded, size: 14, color: scheme.tertiary),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            formatResetAllowanceText(allowance),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 10.5,
            ),
          ),
        ),
      ],
    );
  }
}

// 卡片状态颜色的唯一来源：状态标签（_StatusChip）与紧凑行圆点/百分比共用。
// 规则与文案（quotaStatusText）一一对应：错误/耗尽/紧张用 danger，
// 部分可用/告警用 warning，加载中用 info，未配置/无数据用 muted，充足用 tertiary。
Color quotaStatusColor(
  ProviderQuota quota, {
  required Brightness brightness,
  required ColorScheme scheme,
}) {
  final window = quota.primaryWindow;
  final dark = brightness == Brightness.dark;
  final danger = dark ? const Color(0xFFF87171) : const Color(0xFFB91C1C);
  final warning = dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  final info = dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
  final muted = scheme.outline;
  if (quota.status == QuotaStatus.error) return danger;
  if (quota.status == QuotaStatus.degraded) return warning;
  if (quota.status == QuotaStatus.loading) return info;
  if (quota.status == QuotaStatus.unknown) return muted;
  if (window == null) return muted;
  if (window.isExhausted) return danger;
  if (window.isCritical) return danger;
  if (window.isWarning) return warning;
  return scheme.tertiary;
}

// 卡片状态文字的唯一来源：状态标签和卡片语义标签共用，保证两处一致。
// 状态始终用文字表达，不能只靠颜色。
String quotaStatusText(ProviderQuota quota) {
  final window = quota.primaryWindow;
  if (quota.status == QuotaStatus.error) return '查询失败';
  if (quota.status == QuotaStatus.degraded) return '部分可用';
  if (quota.status == QuotaStatus.loading) return '加载中';
  if (quota.status == QuotaStatus.unknown) return '未配置';
  if (window == null) return '无数据';
  if (window.isExhausted) return '耗尽';
  if (window.isCritical) return '紧张';
  if (window.isWarning) return '告警';
  return '充足';
}

// 右上角状态标签
class _StatusChip extends StatelessWidget {
  final ProviderQuota quota;
  final bool quiet;
  const _StatusChip({required this.quota, required this.quiet});

  @override
  Widget build(BuildContext context) {
    final text = quotaStatusText(quota);
    final color = quotaStatusColor(
      quota,
      brightness: Theme.of(context).brightness,
      scheme: Theme.of(context).colorScheme,
    );
    if (quiet) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: 0.24),
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

// ============================================================================
// 阶段 12：紧凑单行（seamless 未 hover 时的日常形态）
// ============================================================================
// 单行只留决策必需字段：谁（logo + 名称）、用多少（主窗口"已用 X%" +
// 细进度条）、要不要管（状态圆点）。主窗口为空（错误/未配置）时退化为
// logo + 名称 + 状态文字。状态"充足"时全部用 muted 色，不打扰；
// 只有告警/紧张/耗尽/错误等异常才着彩色。
class _CompactRow extends StatelessWidget {
  final ProviderQuota quota;

  const _CompactRow({required this.quota});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final window = quota.primaryWindow;
    // “充足”是唯一安静状态；其余都按状态色突出。
    final calm = quotaStatusText(quota) == '充足';
    final accent = calm
        ? scheme.outline
        : quotaStatusColor(
            quota,
            brightness: theme.brightness,
            scheme: scheme,
          );

    return Row(
      children: [
        ProviderLogo(provider: quota.provider, size: 18),
        const SizedBox(width: 7),
        Text(
          quota.provider.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
            height: 1.2,
          ),
        ),
        if (window != null) ...[
          const SizedBox(width: 8),
          Text(
            formatUsedPercent(window),
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              color: calm ? scheme.onSurfaceVariant : accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          // 细进度条：3.5px 高，正常状态 muted、异常才着状态色。
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (window.usedPercent / 100).clamp(0.0, 1.0),
                minHeight: 3.5,
                backgroundColor: scheme.outlineVariant.withValues(alpha: 0.55),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              quotaStatusText(quota),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: calm ? scheme.onSurfaceVariant : accent,
                fontSize: 10.5,
                height: 1.2,
              ),
            ),
          ),
        ],
        const SizedBox(width: 7),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
      ],
    );
  }
}
