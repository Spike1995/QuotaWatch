// 测试专用的样本数据 Repository（仅测试用，非生产代码）。
// 删除生产 fixture/mock_data 后，widget 测试仍需要一份离线、确定性的
// 三家样本数据来验证 UI 渲染。这里集中维护这份测试样本。
//
// 数据与原 mock_data 等价：三家各两个窗口（5小时 + 周/7天）。
// 它不进 lib/，不会随 app 发布。

import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/quota_repository.dart';

class SampleQuotaRepository implements QuotaRepository {
  const SampleQuotaRepository();

  @override
  Future<List<ProviderQuota>> all() async {
    final now = DateTime.now();
    return [_codex(now), _kimi(now), _glm(now)];
  }

  static ProviderQuota _codex(DateTime now) => ProviderQuota(
        provider: Provider.codex,
        planName: 'ChatGPT Pro',
        windows: [
          QuotaWindow(
            label: '5 小时窗口',
            used: 7200,
            limit: 18000,
            unit: 'seconds',
            resetAt: now.add(const Duration(hours: 1)),
          ),
          QuotaWindow(
            label: '7 天窗口',
            used: 180000,
            limit: 200000,
            unit: 'seconds',
            resetAt: now.add(const Duration(hours: 60)),
          ),
        ],
      );

  static ProviderQuota _kimi(DateTime now) => ProviderQuota(
        provider: Provider.kimi,
        planName: 'Kimi Moderato',
        windows: [
          QuotaWindow(
            label: '5 小时窗口',
            used: 36000000,
            limit: 40000000,
            unit: 'tokens',
            resetAt: now.add(const Duration(hours: 1)),
          ),
          QuotaWindow(
            label: '周窗口',
            used: 36000000,
            limit: 40000000,
            unit: 'tokens',
            resetAt: now.add(const Duration(hours: 60)),
          ),
        ],
      );

  static ProviderQuota _glm(DateTime now) => ProviderQuota(
        provider: Provider.glm,
        planName: 'GLM Pro',
        windows: [
          QuotaWindow(
            label: '5 小时窗口',
            used: 38500000,
            limit: 40000000,
            unit: 'tokens',
            resetAt: now.add(const Duration(hours: 1)),
          ),
          QuotaWindow(
            label: '周窗口',
            used: 30000000,
            limit: 40000000,
            unit: 'tokens',
            resetAt: now.add(const Duration(hours: 60)),
          ),
        ],
      );
}
