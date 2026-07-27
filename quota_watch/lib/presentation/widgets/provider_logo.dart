// ============================================================================
// provider_logo.dart - 服务商官方标识
// ============================================================================
//
// 显示 assets/logos/ 下的官方 PNG（ChatGPT / Kimi / Z.ai）。
// 三张图片本身已带圆角外形和透明角，直接铺放即可；
// 加载失败（例如资源缺失）时回退到品牌色圆形 + 首字母占位。
//
// ============================================================================

import 'package:flutter/material.dart';
import '../../data/models/quota_models.dart';

class ProviderLogo extends StatelessWidget {
  final Provider provider;
  final double size;

  const ProviderLogo({super.key, required this.provider, this.size = 44});

  @override
  Widget build(BuildContext context) {
    // 约 24% 的圆角与三张图标自身的外形一致，阴影容器也按它裁剪。
    final radius = BorderRadius.circular(size * 0.24);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: provider.brandColor.withValues(alpha: 0.25),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          provider.logoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // errorBuilder 是 Image 的兜底回调：资源读不到时改画占位字母，
          // 页面不至于因为一张图缺失而整块报错。
          errorBuilder: (context, error, stackTrace) => Container(
            width: size,
            height: size,
            color: provider.brandColor.withValues(alpha: 0.15),
            alignment: Alignment.center,
            child: Text(
              provider.initial,
              style: TextStyle(
                color: provider.brandColor,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.42,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
