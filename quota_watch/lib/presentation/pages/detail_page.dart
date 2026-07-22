// ============================================================================
// detail_page.dart - 详情页（点卡片进来）
// ============================================================================
//
// 展示单家服务商的所有窗口详情 + 倒计时
// 阶段 5 会加上"历史趋势图"
//
// ============================================================================

import 'package:flutter/material.dart';
import '../../data/models/quota_models.dart';
import '../widgets/quota_progress_bar.dart';

class DetailPage extends StatelessWidget {
  final ProviderQuota quota;

  const DetailPage({super.key, required this.quota});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(quota.provider.displayName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部品牌头
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  quota.provider.brandColor,
                  quota.provider.brandColor.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quota.planName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (quota.expiresAt != null)
                  Text(
                    '订阅到期：${_formatDate(quota.expiresAt!)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                if (quota.fetchedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '更新于 ${_formatRelative(quota.fetchedAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 所有窗口详情
          ...quota.windows.map((w) => _WindowBlock(
                window: w,
                brandColor: quota.provider.brandColor,
              )),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatRelative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

class _WindowBlock extends StatelessWidget {
  final QuotaWindow window;
  final Color brandColor;

  const _WindowBlock({required this.window, required this.brandColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timelapse, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text(
                  window.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            QuotaProgressBar(window: window, brandColor: brandColor),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Metric(
                  label: '已用',
                  value: _format(window.used, window.unit),
                ),
                _Metric(
                  label: '剩余',
                  value: _format(window.remaining, window.unit),
                  highlight: true,
                ),
                _Metric(
                  label: '上限',
                  value: _format(window.limit, window.unit),
                ),
              ],
            ),
            if (window.resetAt != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 14, color: theme.colorScheme.outline),
                    const SizedBox(width: 6),
                    Text(
                      '${_formatCountdown(window)} 后重置',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
            if (window.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 12, color: theme.colorScheme.outline),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        window.note!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _format(double n, String unit) {
    if (unit == 'tokens') {
      if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(2)}B';
      if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
      if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
      return n.toStringAsFixed(0);
    }
    // 秒为单位（Codex），转成"Xh Ym"
    final h = n ~/ 3600;
    final m = ((n % 3600) ~/ 60).toInt();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatCountdown(QuotaWindow w) {
    final secs = w.resetsInSeconds ?? 0;
    if (secs <= 0) return '即将';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) return '${h}时${m}分';
    if (m > 0) return '${m}分${s}秒';
    return '${s}秒';
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _Metric({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: highlight ? theme.colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}
