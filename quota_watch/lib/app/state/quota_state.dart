import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/models/quota_models.dart' show ProviderQuota;
import '../../data/repositories/platform_quota_repository.dart';
import '../../data/repositories/quota_repository.dart';

// 阶段 9（假数据移除）：删除了 DataSourceMode.fixture 离线分支、
// FixtureQuotaRepository 与所有假场景。应用现在只通过真实后端获取额度。
// 保留的"场景"概念仅用于在后端侧选择查询哪些真实 provider。

/// 真实额度查询场景。只保留真实数据来源，删除了 normal/empty/partial/
/// unconfigured/all_error/server_error 等假场景。
enum QuotaScenario {
  codexReal('codex_real', 'Codex 真实额度（本机）'),
  kimiReal('kimi_real', 'Kimi 真实额度（本机）'),
  glmReal('glm_real', 'GLM 真实额度（本机）'),
  allReal('all_real', '综合实际额度（本机）');

  final String apiValue;
  final String label;
  const QuotaScenario(this.apiValue, this.label);

  static QuotaScenario fromApiValue(String value) {
    return QuotaScenario.values.firstWhere(
      (scenario) => scenario.apiValue == value,
      // 默认综合实际额度：一次查三家，各自独立开关。
      orElse: () => QuotaScenario.allReal,
    );
  }
}

/// 磁贴排列偏好：自动响应式、固定竖条、固定横条。
enum QuotaLayoutMode {
  auto('自动适配'),
  vertical('竖向'),
  horizontal('横向');

  final String label;
  const QuotaLayoutMode(this.label);

  static QuotaLayoutMode fromName(String value) {
    return QuotaLayoutMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => QuotaLayoutMode.auto,
    );
  }
}

class AppSettings {
  final QuotaScenario scenario;
  final String backendUrl;
  final QuotaLayoutMode layoutMode;

  const AppSettings({
    required this.scenario,
    required this.backendUrl,
    required this.layoutMode,
  });

  AppSettings copyWith({
    QuotaScenario? scenario,
    String? backendUrl,
    QuotaLayoutMode? layoutMode,
  }) {
    return AppSettings(
      scenario: scenario ?? this.scenario,
      backendUrl: backendUrl ?? this.backendUrl,
      layoutMode: layoutMode ?? this.layoutMode,
    );
  }
}

const _initialScenarioName = String.fromEnvironment(
  'QUOTA_SCENARIO',
  defaultValue: 'all_real',
);
const _initialBackendUrl = String.fromEnvironment(
  'QUOTA_BACKEND_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
const _initialLayoutMode = String.fromEnvironment(
  'QUOTA_LAYOUT_MODE',
  defaultValue: 'auto',
);

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    return AppSettings(
      scenario: QuotaScenario.fromApiValue(_initialScenarioName),
      backendUrl: _initialBackendUrl,
      layoutMode: QuotaLayoutMode.fromName(_initialLayoutMode),
    );
  }

  void update({
    required QuotaScenario scenario,
    required String backendUrl,
    required QuotaLayoutMode layoutMode,
  }) {
    state = AppSettings(
      scenario: scenario,
      backendUrl: backendUrl,
      layoutMode: layoutMode,
    );
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final quotaRepositoryProvider = Provider<QuotaRepository>((ref) {
  final settings = ref.watch(appSettingsProvider);
  // Windows 的全部真实场景直接在 Dart 内查询；Web/Android 保留后端路径。
  return createPlatformQuotaRepository(
    client: ref.watch(httpClientProvider),
    baseUrl: settings.backendUrl,
    scenario: settings.scenario.apiValue,
  );
});

class QuotasController extends AsyncNotifier<List<ProviderQuota>> {
  // 阶段 11：悬浮窗"放着不管也始终可信"。每 5 分钟自动重查一次额度，
  // 无需用户手动下拉。timer 随 build 重建（repository 变化时重置），
  // 并在 provider 销毁时取消，避免泄漏。
  Timer? _autoRefreshTimer;

  @override
  Future<List<ProviderQuota>> build() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => reload(),
    );
    ref.onDispose(() {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    });
    return ref.watch(quotaRepositoryProvider).all();
  }

  Future<void> reload() async {
    // copyWithPrevious：刷新中与失败后都保留上次成功的数据，
    // UI 据此继续显示旧卡片而不是整页转圈或整页报错。
    state = const AsyncLoading<List<ProviderQuota>>().copyWithPrevious(state);
    try {
      final items = await ref.read(quotaRepositoryProvider).all();
      state = AsyncData(items);
    } catch (error, stackTrace) {
      // 不用 AsyncValue.guard：guard 直接替换 state，不保留 previous。
      state = AsyncError<List<ProviderQuota>>(error, stackTrace)
          .copyWithPrevious(state);
    }
  }
}

final quotasProvider =
    AsyncNotifierProvider<QuotasController, List<ProviderQuota>>(
  QuotasController.new,
);

/// 每分钟 tick 一次的时钟：倒计时文案（formatResetText 经 resetsInSeconds
/// 依赖 DateTime.now()）随时间推进每分钟重算，无需等下一次数据刷新。
///
/// 用 Notifier + Timer 而不是 StreamProvider：Stream.periodic 的取消是
/// 异步的，widget 测试在树上缴后仍会看到 pending timer；Timer 存下来
/// 并在 onDispose 同步取消，行为与 QuotasController 的自动刷新一致。
class Ticker extends Notifier<int> {
  @override
  int build() {
    var count = 0;
    final timer = Timer.periodic(const Duration(minutes: 1), (_) {
      count += 1;
      state = count;
    });
    ref.onDispose(timer.cancel);
    return count;
  }
}

final tickerProvider = NotifierProvider<Ticker, int>(Ticker.new);
