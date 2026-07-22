// ============================================================================
// quota_card.dart - 单家额度卡片（首页列表项）
// ============================================================================
//
// 【阶段 1 学习要点】
// - InkWell + Card = Material 风格的可点击卡片（自带涟漪动画）
// - LinearProgressIndicator 是进度条组件
// - 把视觉逻辑抽到单独 widget，UI 才能复用（详情页也用同样的进度条）
//
// ============================================================================

import 'package:flutter/material.dart';
import '../../data/models/quota_models.dart';
import 'quota_progress_bar.dart';

class QuotaCard extends StatelessWidget {
  final ProviderQuota quota;
  final VoidCallback? onTap;

  const QuotaCard({super.key, required this.quota, this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = quota.primaryWindow;
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部：logo + 套餐名 + 状态点
              Row(
                children: [
                  _Logo(provider: quota.provider),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quota.provider.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          quota.planName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (primary != null) _StatusChip(window: primary),
                ],
              ),

              const SizedBox(height: 20),

              // 主窗口进度条
              if (primary != null) ...[
                QuotaProgressBar(window: primary, brandColor: quota.provider.brandColor),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatUsed(primary),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      _formatReset(primary),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // 没数据时
                Text(
                  quota.isUnknown ? '尚未配置' : (quota.errorMessage ?? '暂无数据'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],

              // 多窗口提示
              if (quota.windows.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.more_horiz,
                          size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        '另 ${quota.windows.length - 1} 个窗口',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatUsed(QuotaWindow w) {
    final percent = w.usedPercent.toStringAsFixed(0);
    if (w.unit == 'tokens') {
      return '已用 ${_formatTokens(w.used)} / ${_formatTokens(w.limit)}';
    }
    return '已用 $percent%';
  }

  String _formatReset(QuotaWindow w) {
    if (w.resetAt == null) return '';
    final secs = w.resetsInSeconds ?? 0;
    if (secs <= 0) return '即将重置';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h${m}m 后重置';
    return '${m}m 后重置';
  }

  String _formatTokens(double n) {
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

// 圆形 logo 占位（阶段 5 换成真实 logo）
class _Logo extends StatelessWidget {
  final Provider provider;
  const _Logo({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: provider.brandColor.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        provider.initial,
        style: TextStyle(
          color: provider.brandColor,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}

// 右上角状态标签
class _StatusChip extends StatelessWidget {
  final QuotaWindow window;
  const _StatusChip({required this.window});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String text;
    if (window.isCritical) {
      color = const Color(0xFFEF4444);
      text = '紧张';
    } else if (window.isWarning) {
      color = const Color(0xFFF59E0B);
      text = '告警';
    } else {
      color = const Color(0xFF22C55E);
      text = '充足';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
