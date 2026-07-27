import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/app/desktop/desktop_controller.dart';
import 'package:quota_watch/app/state/quota_state.dart';
import 'package:quota_watch/app/theme/app_theme.dart';
import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/quota_repository.dart';
import 'package:quota_watch/presentation/pages/home_page.dart';

/// 视觉基准只使用虚构数据，不读取本地后端或任何真实额度。
class _GlassPreviewRepository implements QuotaRepository {
  @override
  Future<List<ProviderQuota>> all() async {
    final shortReset = DateTime.now().add(const Duration(hours: 2));
    final longReset = DateTime(2099, 8, 21, 9);
    return [
      ProviderQuota(
        provider: Provider.codex,
        planName: 'ChatGPT Pro',
        windows: [
          QuotaWindow(
            label: '5 小时窗口',
            used: 42,
            limit: 100,
            unit: 'percent',
            resetAt: shortReset,
          ),
          QuotaWindow(
            label: '7 天窗口',
            used: 71,
            limit: 100,
            unit: 'percent',
            resetAt: longReset,
          ),
        ],
      ),
      ProviderQuota(
        provider: Provider.kimi,
        planName: 'Kimi Moderato',
        windows: [
          QuotaWindow(
            label: '5h limit',
            used: 63,
            limit: 100,
            unit: 'percent',
            resetAt: shortReset,
          ),
          QuotaWindow(
            label: 'Weekly limit',
            used: 36,
            limit: 100,
            unit: 'percent',
            resetAt: longReset,
          ),
        ],
      ),
      ProviderQuota(
        provider: Provider.glm,
        planName: 'GLM Coding Plan',
        windows: [
          QuotaWindow(
            label: '5 小时窗口',
            used: 87,
            limit: 100,
            unit: 'percent',
            resetAt: shortReset,
          ),
          QuotaWindow(
            label: '月度/MCP 工具窗口',
            used: 24,
            limit: 100,
            unit: 'percent',
            resetAt: longReset,
          ),
        ],
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontLoader = FontLoader('NotoSansSCSubset')
      ..addFont(
        rootBundle.load(
          'assets/fonts/NotoSansSC-QuotaWatchSubset.ttf',
        ),
      );
    final iconFontLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([fontLoader.load(), iconFontLoader.load()]);
  });

  testWidgets('预热三家品牌图资源', (tester) async {
    await _pumpPreview(tester, AppTheme.dark());
    expect(tester.takeException(), isNull);
  });

  testWidgets('360×680 暗色玻璃磁贴视觉基准', (tester) async {
    await _pumpPreview(tester, AppTheme.dark());

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/compact_glass_tile_dark.png'),
    );
  });

  testWidgets('360×680 亮色玻璃磁贴视觉基准', (tester) async {
    await _pumpPreview(tester, AppTheme.light());

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/compact_glass_tile_light.png'),
    );
  });
}

Future<void> _pumpPreview(WidgetTester tester, ThemeData theme) async {
  await tester.binding.setSurfaceSize(const Size(360, 680));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final displayMode = ValueNotifier(DisplayMode.desktopWidget);
  addTearDown(displayMode.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quotaRepositoryProvider.overrideWithValue(_GlassPreviewRepository()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: HomePage(displayModeListenable: displayMode),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
