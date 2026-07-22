// ============================================================================
// mock_data.dart - 模拟数据（阶段 1 起使用，阶段 5 完成假后端联调后仍保留）
// ============================================================================
//
// 【阶段 1 学习要点】
// - 用假数据先把 UI 跑通，是工程界"测试驱动 UI"的常见做法
// - 数据结构按 API_RESEARCH.md 里的归一化模型设计，未来接 API 几乎无改动
// - 看到所有数据，UI 才能调出"满状态/告警状态/耗尽状态"的不同视觉效果
//
// 【重要】后续会依次换成 Fixture Repository、本地假后端 Repository 和真实服务适配器；
// UI 继续依赖统一模型，不直接理解第三方响应。
//
// ============================================================================

import '../models/quota_models.dart';

class MockQuotaRepository {
  /// 返回模拟的三家额度数据
  /// 故意造了"正常/告警/错误"三种状态，方便你调样式
  static List<ProviderQuota> all() {
    final now = DateTime.now();
    return [
      _codex(now),
      _kimi(now),
      _glm(now),
    ];
  }

  static ProviderQuota _codex(DateTime now) {
    return ProviderQuota(
      provider: Provider.codex,
      planName: 'ChatGPT Pro',
      planType: 'pro',
      expiresAt: now.add(const Duration(days: 14)),
      fetchedAt: now.subtract(const Duration(minutes: 3)),
      status: QuotaStatus.ok,
      windows: [
        QuotaWindow(
          label: '5 小时窗口',
          used: 7200,                      // 已用秒数（额度按时间算）
          limit: 18000,                    // 5h = 18000s
          unit: '秒',                       // Codex 主用秒作单位
          resetAt: now.add(const Duration(hours: 2, minutes: 18)),
          note: '主窗口，到期前自动恢复',
        ),
        QuotaWindow(
          label: '7 天窗口',
          used: 182000,
          limit: 604800,
          unit: '秒',
          resetAt: now.add(const Duration(days: 4, hours: 11)),
        ),
      ],
    );
  }

  static ProviderQuota _kimi(DateTime now) {
    return ProviderQuota(
      provider: Provider.kimi,
      planName: 'Kimi Moderato',
      fetchedAt: now.subtract(const Duration(minutes: 1)),
      status: QuotaStatus.ok,
      windows: [
        QuotaWindow(
          label: '5 小时窗口',
          used: 36e6,                      // 36M tokens
          limit: 40e6,                     // 40M tokens
          unit: 'tokens',
          resetAt: now.add(const Duration(hours: 1, minutes: 23)),
        ),
        QuotaWindow(
          label: '周窗口',
          used: 320e6,
          limit: 1000e6,
          unit: 'tokens',
          resetAt: now.add(const Duration(days: 6, hours: 8)),
        ),
      ],
    );
  }

  static ProviderQuota _glm(DateTime now) {
    return ProviderQuota(
      provider: Provider.glm,
      planName: 'GLM Pro',
      fetchedAt: now.subtract(const Duration(minutes: 5)),
      status: QuotaStatus.ok,
      windows: [
        QuotaWindow(
          label: '5 小时窗口',
          used: 38.5e6,                    // 38.5M / 40M → 接近耗尽，触发告警色
          limit: 40e6,
          unit: 'tokens',
          resetAt: now.add(const Duration(minutes: 42)),
          note: '高峰时段扣 3×，非高峰扣 2×',
        ),
        QuotaWindow(
          label: '周窗口',
          used: 89e6,
          limit: 280e6,
          unit: 'tokens',
          resetAt: now.add(const Duration(days: 5, hours: 2)),
        ),
      ],
    );
  }
}
