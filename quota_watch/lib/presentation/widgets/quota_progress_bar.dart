// ============================================================================
// quota_progress_bar.dart - 额度进度条（带颜色分级 + 微动画）
// ============================================================================
//
// 根据使用百分比自动切色：品牌色 → 橙 → 红。
// 自定义轨道 + 填充两层结构，配合 TweenAnimationBuilder 做加载时的填充动画。
//
// ============================================================================

// 进度条和动画颜色来自 Flutter Material 库。
import 'package:flutter/material.dart';
import '../../data/models/quota_models.dart';

/// 额度严重度配色的唯一来源：进度条、百分比徽标共用，保证全 App 同色同义。
/// 未达 80% 时用服务商品牌色，80% 起橙色告警，95% 起红色危险。
Color quotaSeverityColor(
  QuotaWindow window,
  Color brandColor, {
  required Brightness brightness,
}) {
  final percent = window.usedPercent;
  if (percent >= 95) {
    return brightness == Brightness.dark
        ? const Color(0xFFF87171)
        : const Color(0xFFB91C1C);
  }
  if (percent >= 80) {
    return brightness == Brightness.dark
        ? const Color(0xFFFBBF24)
        : const Color(0xFFB45309);
  }
  return brandColor;
}

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
    // usedPercent 已经由模型统一计算，这个 Widget 只负责把百分比画出来。
    final percent = window.usedPercent;
    final color = quotaSeverityColor(
      window,
      brandColor,
      brightness: Theme.of(context).brightness,
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // LayoutBuilder 拿到实际可用宽度，按百分比换算填充像素宽。
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              // 底层轨道：整条浅色，表示 100%。
              Container(
                height: 6,
                width: constraints.maxWidth,
                color: color.withValues(alpha: 0.16),
              ),
              // 上层填充：TweenAnimationBuilder 让宽度从 0 过渡到目标值，
              // tween 的 end 变化时会自动补间，无需手写 AnimationController。
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: percent / 100),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Container(
                  height: 6,
                  width: constraints.maxWidth * value.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.24),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
