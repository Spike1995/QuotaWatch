// 响应式布局与卡片语义测试：用几何关系断言各断点行为，不使用整页 golden。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quota_watch/app/desktop/desktop_controller.dart';
import 'package:quota_watch/app/router/app_router.dart';
import 'package:quota_watch/app/state/quota_state.dart';
import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/presentation/pages/detail_page.dart';
import 'package:quota_watch/presentation/pages/home_page.dart';
import 'package:quota_watch/presentation/pages/settings_page.dart';
import 'package:quota_watch/presentation/widgets/quota_card.dart';
import 'package:quota_watch/presentation/widgets/summary_header.dart';

import 'helpers/sample_quota_repository.dart';

// 设置表面尺寸并在用例结束后恢复，避免污染其他测试。
Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

// 用样本数据源启动首页，看到三张卡片后立即继续。
Future<void> _pumpHome(
  WidgetTester tester,
  Size size, {
  QuotaLayoutMode layoutMode = QuotaLayoutMode.auto,
}) async {
  await _setSurface(tester, size);
  final displayMode = ValueNotifier(DisplayMode.desktopWidget);
  addTearDown(displayMode.dispose);

  // 用 ProviderScope（树上缴时自动销毁容器）而不是自带容器：
  // 阶段 11 的自动刷新/每分钟 tick 定时器随容器销毁同步取消，
  // 自带容器在 addTearDown 里才销毁会残留 pending timer。
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quotaRepositoryProvider.overrideWithValue(
          const SampleQuotaRepository(),
        ),
      ],
      child: MaterialApp(
        home: HomePage(displayModeListenable: displayMode),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HomePage)),
  );
  final currentSettings = container.read(appSettingsProvider);
  container.read(appSettingsProvider.notifier).update(
        scenario: currentSettings.scenario,
        backendUrl: currentSettings.backendUrl,
        layoutMode: layoutMode,
      );
  await tester.pump();
  for (var attempt = 0;
      attempt < 20 && find.byType(QuotaCard).evaluate().isEmpty;
      attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // 任何布局异常（例如 RenderFlex overflow）都会记录为异常。
  expect(tester.takeException(), isNull);
}

Rect _cardRect(WidgetTester tester, int index) =>
    tester.getRect(find.byType(QuotaCard).at(index));

void main() {
  test('手动重置次数文案明确标注来源', () {
    final text = formatResetAllowanceText(
      ResetAllowance(
        count: 3,
        expiresAt: DateTime(2026, 12, 31, 16),
        source: ResetAllowanceSource.manual,
      ),
    );

    expect(text, contains('可重置 3 次'));
    expect(text, contains('有效至'));
    expect(text, contains('手动记录'));
  });

  testWidgets('360×680 桌面竖条：无应用栏且三张磁贴进入首屏', (tester) async {
    await _pumpHome(tester, const Size(360, 680));

    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Quota Watch'), findsNothing);
    expect(find.byTooltip('数据设置'), findsNothing);
    expect(find.byTooltip('最小化到托盘'), findsNothing);
    expect(find.byTooltip('退出 Quota Watch'), findsNothing);
    expect(find.byType(QuotaCard), findsNWidgets(3));
    final first = _cardRect(tester, 0);
    final second = _cardRect(tester, 1);
    final third = _cardRect(tester, 2);
    // 单列：左边缘对齐，纵向依次排列。
    expect(first.left, second.left);
    expect(second.left, third.left);
    expect(second.top, greaterThan(first.top));
    expect(third.top, greaterThan(second.top));
    // 去掉 52px 应用栏后，第一张磁贴从画布顶部 8px 内边距开始。
    expect(first.top, closeTo(8, 0.01));
    // 默认三家、每家两个窗口时，第三张磁贴底部仍位于窗口首屏内。
    expect(third.bottom, lessThanOrEqualTo(680));
  });

  testWidgets('桌面磁贴上报三个圆角区域，设置页临时恢复完整窗口', (tester) async {
    await _setSurface(tester, const Size(360, 680));
    final calls = <MethodCall>[];
    final backgroundCalls = <MethodCall>[];
    const channel = MethodChannel('quota_watch/window');
    const windowManagerChannel = MethodChannel('window_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (call) async {
      if (call.method == 'setBackgroundColor') backgroundCalls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(windowManagerChannel, null);
    });
    final displayMode = ValueNotifier(DisplayMode.desktopWidget);
    addTearDown(displayMode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quotaRepositoryProvider.overrideWithValue(
            const SampleQuotaRepository(),
          ),
        ],
        child: MaterialApp(
          navigatorObservers: [AppRouter.observer],
          home: HomePage(displayModeListenable: displayMode),
        ),
      ),
    );

    // 数据尚未返回、原生区域尚未建立时，启动画布必须保持不透明。
    final loadingScaffold =
        tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(loadingScaffold.backgroundColor, isNot(Colors.transparent));
    await tester.pumpAndSettle();

    final desktopScaffold =
        tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(desktopScaffold.backgroundColor, Colors.transparent);

    List<Object?> regionsOf(MethodCall call) {
      final arguments = call.arguments! as Map<Object?, Object?>;
      return arguments['regions']! as List<Object?>;
    }

    final shapedCall = calls.lastWhere(
      (call) => call.method == 'setWindowRegions' && regionsOf(call).isNotEmpty,
    );
    Map<Object?, Object?> backgroundOf(MethodCall call) =>
        call.arguments! as Map<Object?, Object?>;

    final regions = regionsOf(shapedCall);
    expect(regions, hasLength(3));
    expect(backgroundCalls, isNotEmpty);
    expect(backgroundOf(backgroundCalls.last)['backgroundColorA'], 0);
    final first = regions.first! as Map<Object?, Object?>;
    expect(first['left'], closeTo(10, 0.01));
    expect(first['top'], closeTo(8, 0.01));
    expect(first['right'], closeTo(350, 0.01));
    expect(
      (shapedCall.arguments! as Map<Object?, Object?>)['cornerRadius'],
      18,
    );

    final settingsRoute = Navigator.of(
      tester.element(find.byType(HomePage)),
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
    await tester.pumpAndSettle();
    expect(regionsOf(calls.last), isEmpty);
    expect(backgroundOf(backgroundCalls.last)['backgroundColorA'], 255);

    Navigator.of(tester.element(find.byType(SettingsPage))).pop();
    await tester.pumpAndSettle();
    await settingsRoute;
    expect(regionsOf(calls.last), hasLength(3));
    expect(backgroundOf(backgroundCalls.last)['backgroundColorA'], 0);

    // 切回普通置顶小窗时，Flutter 画布和原生底色都恢复不透明。
    displayMode.value = DisplayMode.alwaysOnTop;
    await tester.pumpAndSettle();
    final alwaysOnTopScaffold =
        tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(alwaysOnTopScaffold.backgroundColor, isNot(Colors.transparent));
    expect(regionsOf(calls.last), isEmpty);
    expect(backgroundOf(backgroundCalls.last)['backgroundColorA'], 255);
  });

  testWidgets('768 宽：首页两列，第三张卡片换到下一行', (tester) async {
    await _pumpHome(tester, const Size(768, 1500));

    expect(find.byType(QuotaCard), findsNWidgets(3));
    final first = _cardRect(tester, 0);
    final second = _cardRect(tester, 1);
    final third = _cardRect(tester, 2);
    // 前两张同一行、左右并排；第三张换行回到最左。
    expect(first.top, second.top);
    expect(second.left, greaterThan(first.left));
    expect(third.top, greaterThan(first.top));
    expect(third.left, first.left);
  });

  testWidgets('1440x1000：首页三列且内容宽度不超过 1160', (tester) async {
    await _pumpHome(tester, const Size(1440, 1000));

    expect(find.byType(QuotaCard), findsNWidgets(3));
    final first = _cardRect(tester, 0);
    final second = _cardRect(tester, 1);
    final third = _cardRect(tester, 2);
    // 三张同一行、从左到右排列。
    expect(first.top, second.top);
    expect(second.top, third.top);
    expect(second.left, greaterThan(first.left));
    expect(third.left, greaterThan(second.left));
    // 整个网格宽度不超过约定的最大内容宽度（允许浮点尾差）。
    expect(third.right - first.left, lessThanOrEqualTo(1160.01));
  });

  testWidgets('1920x1080：正文宽度不再增长，两侧留白对称', (tester) async {
    await _pumpHome(tester, const Size(1920, 1080));

    expect(find.byType(QuotaCard), findsNWidgets(3));
    final first = _cardRect(tester, 0);
    final third = _cardRect(tester, 2);
    expect(third.right - first.left, lessThanOrEqualTo(1160.01));
    // 扣除 ListView 内边距后，左右留白基本相等，说明正文居中。
    final leftMargin = first.left - 16;
    final rightMargin = 1920 - 16 - third.right;
    expect((leftMargin - rightMargin).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('竖向偏好：宽屏仍保持右侧单列窄条', (tester) async {
    await _pumpHome(
      tester,
      const Size(1440, 1100),
      layoutMode: QuotaLayoutMode.vertical,
    );

    final first = _cardRect(tester, 0);
    final second = _cardRect(tester, 1);
    final third = _cardRect(tester, 2);
    expect(first.width, closeTo(360, 0.01));
    expect(first.left, second.left);
    expect(second.left, third.left);
    expect(second.top, greaterThan(first.top));
    expect(third.top, greaterThan(second.top));
  });

  testWidgets('横向偏好：窄屏保持三张横条并允许水平滚动', (tester) async {
    await _pumpHome(
      tester,
      const Size(390, 844),
      layoutMode: QuotaLayoutMode.horizontal,
    );

    final first = _cardRect(tester, 0);
    final second = _cardRect(tester, 1);
    final third = _cardRect(tester, 2);
    expect(first.top, second.top);
    expect(second.top, third.top);
    expect(first.width, greaterThanOrEqualTo(300));
    expect(second.left, greaterThan(first.left));
    expect(third.left, greaterThan(second.left));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('390px 详情页：紧凑窗口信息无 overflow', (tester) async {
    await _setSurface(tester, const Size(390, 844));
    final now = DateTime.now();
    final quota = ProviderQuota(
      provider: Provider.codex,
      planName: 'ChatGPT Pro',
      fetchedAt: now,
      windows: [
        QuotaWindow(
          label: '7 天窗口',
          used: 182000,
          limit: 604800,
          unit: '秒',
          resetAt: now.add(const Duration(days: 4, hours: 11)),
        ),
        QuotaWindow(
          label: 'tokens 窗口',
          used: 1.23e9,
          limit: 2.5e9,
          unit: 'tokens',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: DetailPage(quota: quota))),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('7 天额度'), findsOneWidget);
    expect(find.text('Token 额度'), findsOneWidget);
    expect(find.textContaining('已用 '), findsNWidgets(2));
    expect(find.text('已用'), findsNothing);
    expect(find.text('剩余'), findsNothing);
    expect(find.text('上限'), findsNothing);
    expect(find.text('重置时间未知'), findsOneWidget);
  });

  testWidgets('详情页：不同原始单位统一只显示使用百分比', (tester) async {
    final quota = ProviderQuota(
      provider: Provider.glm,
      planName: 'GLM Coding Plan',
      windows: [
        QuotaWindow(
          label: '5 小时窗口',
          used: 26.5,
          limit: 100,
          unit: 'percent',
        ),
        QuotaWindow(
          label: '工具调用窗口',
          used: 25,
          limit: 100,
          unit: 'calls',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: DetailPage(quota: quota))),
    );
    await tester.pumpAndSettle();

    expect(find.text('已用 26.5%'), findsOneWidget);
    expect(find.text('已用 25%'), findsOneWidget);
    expect(find.text('73.5%'), findsNothing);
    expect(find.text('100%'), findsNothing);
    expect(find.textContaining(' 次'), findsNothing);
    expect(find.textContaining('m'), findsNothing);
  });

  testWidgets('390px 摘要：三家标记无 overflow', (tester) async {
    await _setSurface(tester, const Size(390, 844));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SummaryHeader(trackedCount: 3, subtitle: '内置演示数据 · 正常'),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Kimi'), findsOneWidget);
    expect(find.text('GLM'), findsOneWidget);
  });

  testWidgets('卡片语义：可点击卡片是按钮，不可点击卡片不是按钮', (tester) async {
    final semantics = tester.ensureSemantics();
    final tappableQuota = ProviderQuota(
      provider: Provider.codex,
      planName: 'ChatGPT Pro',
      windows: [
        QuotaWindow(label: '窗口', used: 10, limit: 100, unit: 'tokens'),
      ],
    );
    final errorQuota = ProviderQuota(
      provider: Provider.glm,
      planName: 'GLM Pro',
      windows: const [],
      status: QuotaStatus.error,
      errorMessage: '模拟故障',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                QuotaCard(quota: tappableQuota, onTap: () {}),
                QuotaCard(quota: errorQuota),
              ],
            ),
          ),
        ),
      ),
    );

    // 语义标签包含服务商名、套餐名和状态文字。
    final tappable = tester
        .getSemantics(
          find.bySemanticsLabel(
            RegExp(r'^Codex ChatGPT Pro；状态：充足'),
          ),
        )
        .getSemanticsData();
    expect(tappable.flagsCollection.isButton, isTrue);
    expect(tappable.hasAction(SemanticsAction.tap), isTrue);

    final nonTappable = tester
        .getSemantics(
          find.bySemanticsLabel(
            RegExp(r'^GLM GLM Pro；状态：查询失败'),
          ),
        )
        .getSemanticsData();
    expect(nonTappable.flagsCollection.isButton, isFalse);
    expect(nonTappable.hasAction(SemanticsAction.tap), isFalse);

    semantics.dispose();
  });

  testWidgets('后端地址默认可编辑', (tester) async {
    // 假数据移除后固定走真实后端，地址输入框应存在。
    // SettingsPage 作为 Consumer 需在 ProviderScope 下渲染。
    await _setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quotaRepositoryProvider
              .overrideWithValue(const SampleQuotaRepository()),
          httpClientProvider.overrideWithValue(
            MockClient(
              (_) async => http.Response.bytes(
                utf8.encode(
                  '[{"provider":"codex","label":"本机 Codex 登录",'
                  '"configured":true,"source":"codex_local_login"},'
                  '{"provider":"kimi","label":"Kimi Code",'
                  '"configured":false,"source":"not_configured"},'
                  '{"provider":"glm","label":"GLM Coding Plan",'
                  '"configured":false,"source":"not_configured"}]',
                ),
                200,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.where(
        (field) =>
            field.controller?.text == 'http://127.0.0.1:8000' &&
            field.keyboardType == TextInputType.url,
      ),
      hasLength(1),
    );
  });

  testWidgets('安全保存结束后立即清空 Key 输入框', (tester) async {
    await _setSurface(tester, const Size(700, 1200));
    const shortLivedKey = 'widget-test-key';
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response.bytes(
          utf8.encode(
            '[{"provider":"codex","label":"本机 Codex 登录",'
            '"configured":true,"source":"codex_local_login"},'
            '{"provider":"kimi","label":"Kimi Code",'
            '"configured":false,"source":"not_configured"},'
            '{"provider":"glm","label":"GLM Coding Plan",'
            '"configured":false,"source":"not_configured"}]',
          ),
          200,
        );
      }
      expect(request.method, 'PUT');
      expect(request.body, contains(shortLivedKey));
      return http.Response.bytes(
        utf8.encode(
          '{"provider":"kimi","label":"Kimi Code","configured":true,'
          '"source":"windows_credential_manager"}',
        ),
        200,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quotaRepositoryProvider
              .overrideWithValue(const SampleQuotaRepository()),
          httpClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final keyField = find.byKey(const ValueKey('kimi-api-key-field'));
    await tester.ensureVisible(keyField);
    await tester.enterText(keyField, shortLivedKey);
    final saveButton = find.byKey(const ValueKey('kimi-save-api-key'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final widget = tester.widget<TextField>(keyField);
    expect(widget.controller!.text, isEmpty);
    expect(find.text(shortLivedKey), findsNothing);
    expect(find.text('Windows 凭据管理器'), findsOneWidget);
  });

  testWidgets('安全保存进行中离开设置页不会访问已销毁输入框', (tester) async {
    await _setSurface(tester, const Size(700, 1200));
    final saveStarted = Completer<void>();
    final saveResponse = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response.bytes(
          utf8.encode(
            '[{"provider":"codex","label":"本机 Codex 登录",'
            '"configured":true,"source":"codex_local_login"},'
            '{"provider":"kimi","label":"Kimi Code",'
            '"configured":false,"source":"not_configured"},'
            '{"provider":"glm","label":"GLM Coding Plan",'
            '"configured":false,"source":"not_configured"}]',
          ),
          200,
        );
      }
      saveStarted.complete();
      return saveResponse.future;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quotaRepositoryProvider
              .overrideWithValue(const SampleQuotaRepository()),
          httpClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final keyField = find.byKey(const ValueKey('kimi-api-key-field'));
    await tester.ensureVisible(keyField);
    await tester.enterText(keyField, 'short-lived-dispose-test-key');
    final saveButton = find.byKey(const ValueKey('kimi-save-api-key'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    await saveStarted.future;

    // 模拟用户在网络请求返回前关闭设置页。
    await tester.pumpWidget(const SizedBox.shrink());
    saveResponse.complete(
      http.Response.bytes(
        utf8.encode(
          '{"provider":"kimi","label":"Kimi Code","configured":true,'
          '"source":"windows_credential_manager"}',
        ),
        200,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
