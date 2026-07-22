// ============================================================================
// quota_progress_bar.dart - 额度进度条（带颜色分级）
// ============================================================================
//
// 根据使用百分比自动切色：绿 → 橙 → 红
// 进度条 + 圆角 + 微动画
//
// ============================================================================

import 'package:flutter/material.dart';
import '../../data/models/quota_models.dart';

class QuotaProgressBar extends StatelessWidget {
  final QuotaWindow window;
  final Color brandColor;

  const QuotaProgressBar({
    super.key,
    required this.window,
    required this.brandColor,
  });

  @override
  Widget build(BuildContext context) {
    final percent = window.usedPercent;
    final color = _colorFor(percent);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: percent / 100,
        minHeight: 8,
        backgroundColor: color.withOpacity(0.15),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  Color _colorFor(double percent) {
    if (percent >= 95) return const Color(0xFFEF4444);   // 红
    if (percent >= 80) return const Color(0xFFF59E0B);   // 橙
    return brandColor;                                    // 品牌色
  }
}
