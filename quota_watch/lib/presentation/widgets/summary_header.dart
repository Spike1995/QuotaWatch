// ============================================================================
// summary_header.dart - 顶部总览小卡片
// ============================================================================
//
// 给首页加一个"全平台概览"的头部，一眼看到三家的整体状态。
// 阶段 1 用模拟数据写死 3 家。
//
// ============================================================================

import 'package:flutter/material.dart';

class SummaryHeader extends StatelessWidget {
  const SummaryHeader({super.key});

  @override
  Widget build(BuildContext context) {
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
            '已跟踪 3 个套餐',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '当前模式：模拟数据，可下拉刷新',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: const [
              _Dot(color: Color(0xFF10A37F), label: 'Codex'),
              SizedBox(width: 16),
              _Dot(color: Color(0xFF1D9BF0), label: 'Kimi'),
              SizedBox(width: 16),
              _Dot(color: Color(0xFF615CED), label: 'GLM'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
