// ============================================================================
// detail_page.dart - 详情页（历史记录等扩展信息的落点）
// ============================================================================
//
// 首页卡片现已直接展示全部窗口；本页保留给订阅信息、历史趋势等扩展内容，
// 窗口块复用 QuotaWindowBlock，与首页保持完全一致的外观和格式化规则。
//
// ============================================================================

// 详情页使用 Material 的页面骨架、列表、卡片和文字控件。
import 'package:flutter/material.dart';
import '../../data/models/quota_models.dart';
import '../widgets/centered_content.dart';
import '../widgets/provider_logo.dart';
import '../widgets/quota_window_block.dart';

class DetailPage extends StatelessWidget {
  // 详情页必须知道要展示哪一家服务商，因此 quota 是 required 参数。
  final ProviderQuota quota;

  const DetailPage({super.key, required this.quota});

  @override
  Widget build(BuildContext context) {
    // 从祖先主题读取文字样式；BuildContext 代表当前 Widget 在树中的位置。
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(quota.provider.displayName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 宽屏时正文最多 960px 并居中，窄屏仍占满可用宽度。
          CenteredContent(
            maxWidth: 960,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 顶部品牌头
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        quota.provider.brandColor,
                        quota.provider.brandColor.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 官方标识叠在品牌渐变上，白底让三家的图标都清晰。
                      ProviderLogo(provider: quota.provider, size: 56),
                      const SizedBox(height: 12),
                      Text(
                        quota.planName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 可空字段先判断不为 null，才可以显示到期日期。
                      if (quota.expiresAt != null)
                        Text(
                          // `!` 解除可空标记：这里依赖上面的判断，告诉 Dart 值确实存在。
                          '订阅到期：${_formatDate(quota.expiresAt!)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      if (quota.fetchedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '更新于 ${_formatRelative(quota.fetchedAt!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 所有窗口详情：与首页卡片共用同一个信息块组件。
                ...quota.windows.map(
                  (w) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: QuotaWindowBlock(
                        window: w,
                        brandColor: quota.provider.brandColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
