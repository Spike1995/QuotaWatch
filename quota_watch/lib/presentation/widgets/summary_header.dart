// ============================================================================
// summary_header.dart - 顶部总览小卡片
// ============================================================================
//
// 给首页加一个"全平台概览"的头部，一眼看到三家的整体状态。
// 阶段 1 用模拟数据写死 3 家。
//
// ============================================================================

// 顶部总览使用 Material 的布局和文字控件。
import 'package:flutter/material.dart';
import '../../data/models/quota_models.dart';
import 'provider_logo.dart';

class SummaryHeader extends StatelessWidget {
  final int trackedCount;
  final String subtitle;

  // const 构造函数表示这个总览本身没有运行时状态，可以复用同一个常量配置。
  const SummaryHeader({
    super.key,
    required this.trackedCount,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    // Theme.of(context) 从祖先 MaterialApp 读取当前主题，避免在每个 Widget 重复写颜色。
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已跟踪 $trackedCount 个套餐',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          // Wrap 在窄屏自动换行，宽屏仍保持一行；圆点升级为各家官方标识。
          const Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _ProviderMark(provider: Provider.codex),
              _ProviderMark(provider: Provider.kimi),
              _ProviderMark(provider: Provider.glm),
            ],
          ),
        ],
      ),
    );
  }
}

// 总览里的单家标记：官方小图标 + 名称，替代原来的彩色圆点。
class _ProviderMark extends StatelessWidget {
  final Provider provider;
  const _ProviderMark({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProviderLogo(provider: provider, size: 20),
        const SizedBox(width: 6),
        Text(
          provider.displayName,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
