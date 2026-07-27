import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/app/state/quota_state.dart';
import 'package:quota_watch/data/models/quota_models.dart' as models;
import 'package:quota_watch/data/repositories/all_real_quota_repository.dart';
import 'package:quota_watch/data/repositories/quota_repository.dart';

// 阶段 9（假数据移除）后：DataSourceMode/DemoScenario 已删除，AppSettings
// 保留 QuotaScenario + backendUrl + 布局偏好。Windows 发布版默认直接在
// Dart 内聚合三家 Provider，其他平台仍可通过 backendUrl 访问后端。

class _SequenceRepository implements QuotaRepository {
  var calls = 0;

  @override
  Future<List<models.ProviderQuota>> all() async {
    calls += 1;
    return [
      models.ProviderQuota(
        provider: models.Provider.codex,
        planName: '第 $calls 次加载',
        windows: [],
      ),
    ];
  }
}

// 首次成功、之后全部抛错：验证刷新失败时旧数据保留在 state 里。
class _FailAfterFirstRepository implements QuotaRepository {
  var calls = 0;

  @override
  Future<List<models.ProviderQuota>> all() async {
    calls += 1;
    if (calls > 1) throw StateError('模拟后端不可用');
    return [
      models.ProviderQuota(
        provider: models.Provider.codex,
        planName: '首次加载',
        windows: [],
      ),
    ];
  }
}

void main() {
  test('QuotasController 首次加载并可主动刷新', () async {
    final repository = _SequenceRepository();
    final container = ProviderContainer(
      overrides: [quotaRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final first = await container.read(quotasProvider.future);
    expect(first.single.planName, '第 1 次加载');

    await container.read(quotasProvider.notifier).reload();
    final second = container.read(quotasProvider).requireValue;

    expect(second.single.planName, '第 2 次加载');
    expect(repository.calls, 2);
  });

  // 阶段 11：刷新失败时 state 是 AsyncError，但 copyWithPrevious 保留了
  // 上次成功的数据，UI 可以继续显示旧卡片。
  test('reload 失败后 state 仍保留上次数据', () async {
    final repository = _FailAfterFirstRepository();
    final container = ProviderContainer(
      overrides: [quotaRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final first = await container.read(quotasProvider.future);
    expect(first.single.planName, '首次加载');

    await container.read(quotasProvider.notifier).reload();
    final state = container.read(quotasProvider);

    expect(state.hasError, isTrue);
    expect(state.valueOrNull, isNotNull);
    expect(state.valueOrNull!.single.planName, '首次加载');
    expect(repository.calls, 2);
  });

  test('Windows 默认创建 Dart 内的 AllRealQuotaRepository', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(quotaRepositoryProvider),
      isA<AllRealQuotaRepository>(),
    );
  });

  test('切换真实场景会更新设置并保留后端地址', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(appSettingsProvider.notifier).update(
          scenario: QuotaScenario.allReal,
          backendUrl: 'http://127.0.0.1:9000',
          layoutMode: QuotaLayoutMode.horizontal,
        );

    final settings = container.read(appSettingsProvider);
    expect(settings.scenario, QuotaScenario.allReal);
    expect(settings.backendUrl, 'http://127.0.0.1:9000');
    expect(settings.layoutMode, QuotaLayoutMode.horizontal);
  });

  test('可以选择单家或综合实际额度场景', () {
    for (final realScenario in QuotaScenario.values) {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(appSettingsProvider.notifier).update(
            scenario: realScenario,
            backendUrl: 'http://127.0.0.1:8000',
            layoutMode: QuotaLayoutMode.auto,
          );

      expect(container.read(appSettingsProvider).scenario, realScenario);
    }
  });
}
