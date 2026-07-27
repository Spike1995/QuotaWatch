// flutter_test 提供 Widget 测试工具：可以在不打开真实浏览器的情况下构造 Widget 树并检查它。
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/main.dart';
import 'package:quota_watch/app/desktop/desktop_controller.dart';
import 'package:quota_watch/app/state/quota_state.dart';
import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/quota_repository.dart';
import 'package:quota_watch/presentation/pages/home_page.dart';
import 'package:quota_watch/presentation/widgets/quota_card.dart';
import 'package:quota_watch/presentation/widgets/quota_window_block.dart';

import 'helpers/sample_quota_repository.dart';

// 测试专用的假实现：它遵守 QuotaRepository 合同，但返回与 Mock 不同的数据。
// 如果 HomePage 仍偷偷调用 MockQuotaRepository，这个测试就不会显示“注入套餐”。
class _FakeQuotaRepository implements QuotaRepository {
  @override
  Future<List<ProviderQuota>> all() async {
    return [
      ProviderQuota(
        provider: Provider.codex,
        planName: '注入套餐',
        windows: [
          QuotaWindow(
            label: '测试窗口',
            used: 10,
            limit: 100,
            unit: 'tokens',
          ),
        ],
      ),
    ];
  }
}

class _FailingQuotaRepository implements QuotaRepository {
  @override
  Future<List<ProviderQuota>> all() {
    throw const FormatException('测试用损坏数据');
  }
}

class _EmptyQuotaRepository implements QuotaRepository {
  @override
  Future<List<ProviderQuota>> all() async => [];
}

class _PartialQuotaRepository implements QuotaRepository {
  @override
  Future<List<ProviderQuota>> all() async {
    final normal = await const SampleQuotaRepository().all();
    return [
      normal[0],
      normal[1],
      ProviderQuota(
        provider: Provider.glm,
        planName: 'GLM Pro',
        windows: [],
        status: QuotaStatus.error,
        errorMessage: '模拟故障：GLM 服务暂时不可用',
      ),
    ];
  }
}

class _UnconfiguredQuotaRepository implements QuotaRepository {
  @override
  Future<List<ProviderQuota>> all() async {
    return Provider.values
        .map(
          (provider) => ProviderQuota(
            provider: provider,
            planName: '尚未配置',
            windows: [],
            status: QuotaStatus.unknown,
          ),
        )
        .toList();
  }
}

class _AllErrorQuotaRepository implements QuotaRepository {
  @override
  Future<List<ProviderQuota>> all() async {
    return Provider.values
        .map(
          (provider) => ProviderQuota(
            provider: provider,
            planName: '${provider.displayName} 套餐',
            windows: [],
            status: QuotaStatus.error,
            errorMessage: '模拟故障：${provider.displayName} 查询失败',
          ),
        )
        .toList();
  }
}

// 首页加载时有一个持续旋转的进度圈，pumpAndSettle 不适合等待这种动画。
// 这里最多推进 1 秒，看到额度卡片后立即继续测试。
// 测试画布放大，便于同时检查窄窗和宽屏磁贴布局。
Future<void> _pumpTestApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quotaRepositoryProvider.overrideWithValue(
          const SampleQuotaRepository(),
        ),
      ],
      child: const QuotaWatchApp(),
    ),
  );
  for (var attempt = 0;
      attempt < 20 && find.byType(QuotaCard).evaluate().isEmpty;
      attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

// setSurfaceSize 是异步 API，必须 await 后才能继续 pump，否则测试框架会报时序冲突。
Future<void> _pumpHomeWithRepository(
  WidgetTester tester,
  QuotaRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [quotaRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: HomePage()),
    ),
  );
}

// 阶段 9 修复验证：标题栏包 WindowDragArea 后，body 的下拉刷新仍可用。
// 若 DragToMoveArea 错误吞掉 pan 手势，onRefresh 不会触发，reloads 仍为 0。
class _CountingRepository implements QuotaRepository {
  int loads = 0;
  @override
  Future<List<ProviderQuota>> all() async {
    loads += 1;
    return [
      ProviderQuota(
        provider: Provider.codex,
        planName: '套餐',
        windows: [
          QuotaWindow(label: '窗口', used: 1, limit: 10, unit: 'tokens'),
        ],
      ),
    ];
  }
}

void main() {
  test('中英文窗口原始标签统一为“时间或用途 + 额度”', () {
    expect(formatQuotaWindowLabel('5 小时窗口'), '5 小时额度');
    expect(formatQuotaWindowLabel('5h limit'), '5 小时额度');
    expect(formatQuotaWindowLabel('Weekly limit'), '7 天额度');
    expect(formatQuotaWindowLabel('周窗口'), '7 天额度');
    expect(formatQuotaWindowLabel('7d limit'), '7 天额度');
    expect(formatQuotaWindowLabel('月度/MCP 工具窗口'), '月度工具额度');
    expect(formatQuotaWindowLabel('tool calls'), '工具调用额度');
    expect(formatQuotaWindowLabel('TOKENS_LIMIT'), 'Token 额度');
  });

  // testWidgets 会创建一个 Flutter 测试环境；tester 是操作和查询 Widget 的工具对象。
  testWidgets('首页显示三家模拟套餐', (WidgetTester tester) async {
    // pumpWidget 把根 Widget 放入测试环境，相当于运行时的 runApp。
    await _pumpTestApp(tester);

    // expect 断言预期结果；find 用文字或类型在 Widget 树中查找目标。
    expect(find.text('Quota Watch'), findsOneWidget);
    final cards = find.byType(QuotaCard);
    expect(cards, findsNWidgets(3));
    expect(
      find.descendant(of: cards.at(0), matching: find.text('Codex')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cards.at(1), matching: find.text('Kimi')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cards.at(2), matching: find.text('GLM')),
      findsOneWidget,
    );
  });

  testWidgets('桌面组件隐藏应用栏，切回置顶小窗后恢复', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.binding.setSurfaceSize(const Size(360, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
            home: HomePage(displayModeListenable: displayMode),
          ),
        ),
      );
      for (var attempt = 0;
          attempt < 20 && find.byType(QuotaCard).evaluate().isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Quota Watch'), findsNothing);
      expect(find.byTooltip('数据设置'), findsNothing);
      expect(find.byTooltip('最小化到托盘'), findsNothing);
      expect(find.byTooltip('退出 Quota Watch'), findsNothing);

      displayMode.value = DisplayMode.alwaysOnTop;
      await tester.pump();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Quota Watch'), findsOneWidget);
      expect(find.byTooltip('数据设置'), findsOneWidget);
      expect(find.byTooltip('最小化到托盘'), findsOneWidget);
      expect(find.byTooltip('退出 Quota Watch'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android 使用普通应用栏且不显示托盘窗口控制', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pumpHomeWithRepository(tester, const SampleQuotaRepository());
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('数据设置'), findsOneWidget);
      expect(find.byTooltip('最小化到托盘'), findsNothing);
      expect(find.byTooltip('退出 Quota Watch'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('首页统一窗口名称并只保留百分比、进度条与重置时间', (WidgetTester tester) async {
    await _pumpTestApp(tester);

    // 三家的短窗口与周窗口统一使用“额度”后缀，不泄漏 Provider 英文标签。
    expect(find.text('5 小时额度'), findsNWidgets(3));
    expect(find.text('7 天额度'), findsNWidgets(3));
    expect(find.text('5 小时窗口'), findsNothing);
    expect(find.text('周窗口'), findsNothing);
    expect(find.text('Weekly limit'), findsNothing);
    // 每个窗口只保留一条“已用 X%”；旧三列指标全部删除。
    expect(find.textContaining('已用 '), findsNWidgets(6));
    expect(find.text('已用'), findsNothing);
    expect(find.text('剩余'), findsNothing);
    expect(find.text('上限'), findsNothing);
    // Mock 里三个超过 24 小时的窗口一律写成“M月d日（周X）重置”，不写小时数。
    expect(find.textContaining('）重置'), findsNWidgets(3));
    // 24 小时内的短窗口仍保留倒计时文案。
    expect(find.textContaining('后重置'), findsNWidgets(3));
  });

  testWidgets('设置按钮进入数据设置页', (WidgetTester tester) async {
    await _pumpTestApp(tester);

    await tester.tap(find.byTooltip('数据设置'));
    await tester.pumpAndSettle();

    expect(find.text('Quota Watch 设置'), findsOneWidget);
    expect(find.text('真实额度场景'), findsOneWidget);
    expect(find.text('后端地址'), findsOneWidget);
    expect(find.text('应用并返回'), findsOneWidget);
  });

  testWidgets('可以选择 Kimi 真实额度并提示安全配置', (WidgetTester tester) async {
    await _pumpTestApp(tester);
    await tester.tap(find.byTooltip('数据设置'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byType(DropdownButtonFormField<QuotaScenario>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kimi 真实额度（本机）').last);
    await tester.pumpAndSettle();

    expect(find.text('Kimi 真实额度（本机）'), findsOneWidget);
    expect(
      find.text('Kimi Key 可在下方安全面板写入 Windows 凭据管理器。'),
      findsOneWidget,
    );
  });

  testWidgets('可以选择综合实际额度并说明独立开关', (WidgetTester tester) async {
    // all_real 是默认场景，进入设置页即应显示其说明文本。
    await _pumpTestApp(tester);
    await tester.tap(find.byTooltip('数据设置'));
    await tester.pumpAndSettle();

    expect(find.text('综合实际额度（本机）'), findsOneWidget);
    expect(
      find.text('同时查询已启用或已有本机安全凭据的服务。'),
      findsOneWidget,
    );
  });

  testWidgets('Codex 卡片按三态显示恢复额度', (WidgetTester tester) async {
    ProviderQuota quotaWith(QuotaCredits? credits) => ProviderQuota(
          provider: Provider.codex,
          planName: 'ChatGPT Pro',
          credits: credits,
          windows: [
            QuotaWindow(label: '窗口', used: 10, limit: 100, unit: 'tokens'),
          ],
        );

    await tester.pumpWidget(
      // QuotaWindowBlock 现在 watch tickerProvider，直接泵入卡片也需要 ProviderScope。
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            // SingleChildScrollView 防止三张卡片超出测试画布高度。
            body: SingleChildScrollView(
              child: Column(
                children: [
                  QuotaCard(
                    quota: quotaWith(const QuotaCredits(
                      hasCredits: true,
                      unlimited: false,
                      balance: '50',
                    )),
                  ),
                  QuotaCard(
                    quota: quotaWith(const QuotaCredits(
                      hasCredits: true,
                      unlimited: true,
                    )),
                  ),
                  QuotaCard(quota: quotaWith(null)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('恢复额度：50'), findsOneWidget);
    expect(find.text('恢复额度：无限'), findsOneWidget);
    // 无 credits 的卡片不渲染该行：含“恢复额度”的文本恰好只有两条。
    expect(find.textContaining('恢复额度'), findsNWidgets(2));
  });

  testWidgets('额度达到 100% 时卡片显示耗尽', (WidgetTester tester) async {
    final exhaustedQuota = ProviderQuota(
      provider: Provider.glm,
      planName: '测试套餐',
      windows: [
        QuotaWindow(
          label: '测试窗口',
          used: 100,
          limit: 100,
          unit: 'tokens',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: QuotaCard(quota: exhaustedQuota)),
        ),
      ),
    );

    expect(find.text('耗尽'), findsOneWidget);
    expect(find.text('紧张'), findsNothing);
  });

  testWidgets('首页可以注入不同的 Repository 实现', (WidgetTester tester) async {
    await _pumpHomeWithRepository(tester, _FakeQuotaRepository());
    await tester.pumpAndSettle();

    expect(find.text('注入套餐'), findsOneWidget);
    expect(find.text('ChatGPT Pro'), findsNothing);
  });

  testWidgets('数据源读取失败时显示错误和重试按钮', (tester) async {
    await _pumpHomeWithRepository(tester, _FailingQuotaRepository());
    await tester.pumpAndSettle();

    expect(find.text('数据加载失败，请重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('数据源返回空列表时显示空状态', (tester) async {
    await _pumpHomeWithRepository(tester, _EmptyQuotaRepository());
    await tester.pumpAndSettle();

    expect(find.text('暂无额度数据'), findsOneWidget);
    expect(find.text('当前数据源没有返回任何套餐'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.byType(QuotaCard), findsNothing);
  });

  testWidgets('单家失败时保留其他套餐并显示失败原因', (tester) async {
    await _pumpHomeWithRepository(tester, _PartialQuotaRepository());
    await tester.pumpAndSettle();

    final cards = find.byType(QuotaCard);
    expect(cards, findsNWidgets(3));
    expect(find.text('查询失败'), findsOneWidget);
    expect(find.text('模拟故障：GLM 服务暂时不可用'), findsOneWidget);
    expect(
      find.descendant(of: cards.at(0), matching: find.text('Codex')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cards.at(1), matching: find.text('Kimi')),
      findsOneWidget,
    );
  });

  testWidgets('三家未配置时分别显示未配置状态', (tester) async {
    await _pumpHomeWithRepository(tester, _UnconfiguredQuotaRepository());
    await tester.pumpAndSettle();

    expect(find.byType(QuotaCard), findsNWidgets(3));
    expect(find.text('未配置'), findsNWidgets(3));
  });

  testWidgets('三家全部失败时分别保留错误卡片', (tester) async {
    await _pumpHomeWithRepository(tester, _AllErrorQuotaRepository());
    await tester.pumpAndSettle();

    expect(find.byType(QuotaCard), findsNWidgets(3));
    expect(find.text('查询失败'), findsNWidgets(3));
    expect(find.text('模拟故障：Codex 查询失败'), findsOneWidget);
    expect(find.text('模拟故障：Kimi 查询失败'), findsOneWidget);
    expect(find.text('模拟故障：GLM 查询失败'), findsOneWidget);
  });

  // 阶段 9 修复：标题文字包 WindowDragArea（窗口拖动把手）后，body 区域的
  // 下拉刷新仍能触发。验证 DragToMoveArea 没有把垂直拖动手势吞掉。
  testWidgets('标题栏可拖动窗口时，列表仍可下拉刷新', (tester) async {
    final repo = _CountingRepository();
    await _pumpHomeWithRepository(tester, repo);
    await tester.pumpAndSettle();
    expect(repo.loads, 1); // 初始加载

    // 在可滚动列表顶部向下拖动（overscroll），触发 RefreshIndicator。
    // 从列表第一个可见磁贴往下 fling，确保手势落在 body 的 ListView 内，
    // 而非 AppBar 的标题拖动区。
    final scrollable = find.byType(Scrollable).first;
    expect(scrollable, findsWidgets);
    await tester.fling(scrollable, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    // 若手势被 DragToMoveArea 吞掉，reload 不会执行，loads 仍为 1。
    expect(repo.loads, greaterThan(1));
  });
}
