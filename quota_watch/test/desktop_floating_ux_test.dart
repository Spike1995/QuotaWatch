// 阶段 11/12：桌面悬浮窗自治、紧凑行与闲置淡出的 widget 测试。
// 覆盖：seamless 无 BackdropFilter、整卡 WindowDragArea、紧凑行默认形态、
// hover 展开/移开收回、muted 与彩色取色、失败保留旧卡片、setOpacity。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/app/desktop/desktop_controller.dart';
import 'package:quota_watch/app/desktop/desktop_controller_web.dart';
import 'package:quota_watch/app/desktop/window_drag_area.dart';
import 'package:quota_watch/app/state/quota_state.dart';
import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/repositories/quota_repository.dart';
import 'package:quota_watch/presentation/pages/home_page.dart';
import 'package:quota_watch/presentation/widgets/quota_card.dart';

import 'helpers/sample_quota_repository.dart';

ProviderQuota _simpleQuota({DateTime? fetchedAt}) => ProviderQuota(
      provider: Provider.codex,
      planName: 'ChatGPT Pro',
      fetchedAt: fetchedAt,
      windows: [
        QuotaWindow(label: '窗口', used: 1, limit: 10, unit: 'tokens'),
      ],
    );

class _SingleCardRepository implements QuotaRepository {
  @override
  Future<List<ProviderQuota>> all() async => [
        _simpleQuota(fetchedAt: DateTime(2026, 7, 26, 9, 5)),
      ];
}

// 首次成功、之后全部抛错：配合 reload 验证失败保留旧卡片 + 提示条。
class _FlakyRepository implements QuotaRepository {
  var calls = 0;

  @override
  Future<List<ProviderQuota>> all() async {
    calls += 1;
    if (calls > 1) throw const FormatException('模拟网络故障');
    return [_simpleQuota(fetchedAt: DateTime(2026, 7, 26, 9, 5))];
  }
}

// 主窗口 42%（充足）与 87%（告警）各一张：验证紧凑行取色规则。
class _CalmAndWarningRepository implements QuotaRepository {
  @override
  Future<List<ProviderQuota>> all() async {
    final now = DateTime.now();
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
            resetAt: now.add(const Duration(hours: 1)),
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
            resetAt: now.add(const Duration(hours: 1)),
          ),
        ],
      ),
    ];
  }
}

// 在桌面悬浮模式下泵入首页并等卡片出现。
Future<ValueNotifier<DisplayMode>> _pumpSeamlessHome(
  WidgetTester tester,
  QuotaRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(360, 680));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final displayMode = ValueNotifier(DisplayMode.desktopWidget);
  addTearDown(displayMode.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [quotaRepositoryProvider.overrideWithValue(repository)],
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
  return displayMode;
}

// 创建鼠标手势并把指针停在第一张卡片中心（hover 展开态）。
Future<TestGesture> _hoverFirstCard(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(gesture.removePointer);
  await gesture.addPointer(location: Offset.zero);
  await gesture.moveTo(tester.getCenter(find.byType(QuotaCard).first));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('seamless 卡片不创建 BackdropFilter，普通模式保留', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                QuotaCard(quota: _simpleQuota(), seamless: true),
                QuotaCard(quota: _simpleQuota()),
              ],
            ),
          ),
        ),
      ),
    );

    final seamlessCard = find.byWidgetPredicate(
      (widget) => widget is QuotaCard && widget.seamless,
    );
    final normalCard = find.byWidgetPredicate(
      (widget) => widget is QuotaCard && !widget.seamless,
    );
    expect(
      find.descendant(of: seamlessCard, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    expect(
      find.descendant(of: normalCard, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
  });

  testWidgets('seamless 卡片由 WindowDragArea 整卡包裹，普通模式没有', (tester) async {
    final displayMode =
        await _pumpSeamlessHome(tester, const SampleQuotaRepository());

    expect(
      find.ancestor(
        of: find.byType(QuotaCard),
        matching: find.byType(WindowDragArea),
      ),
      findsNWidgets(3),
    );

    displayMode.value = DisplayMode.alwaysOnTop;
    await tester.pump();
    expect(
      find.ancestor(
        of: find.byType(QuotaCard),
        matching: find.byType(WindowDragArea),
      ),
      findsNothing,
    );
  });

  testWidgets('seamless 默认渲染紧凑行：有“已用”无“更新于”无窗口明细', (tester) async {
    await _pumpSeamlessHome(tester, _SingleCardRepository());

    expect(find.byType(QuotaCard), findsOneWidget);
    expect(find.textContaining('已用 '), findsOneWidget);
    // 紧凑行不渲染完整卡片才有的内容。
    expect(find.textContaining('更新于'), findsNothing);
    expect(find.text('窗口'), findsNothing);
    expect(find.text('ChatGPT Pro'), findsNothing);
    expect(find.byTooltip('刷新'), findsNothing);
  });

  testWidgets('hover 展开为完整卡片，移开收回紧凑行', (tester) async {
    await _pumpSeamlessHome(tester, _SingleCardRepository());
    expect(find.textContaining('更新于'), findsNothing);

    final gesture = await _hoverFirstCard(tester);
    // AnimatedSize 动画 150ms：pump 结束后完整卡片全部内容可见。
    await tester.pumpAndSettle();

    expect(find.textContaining('更新于'), findsOneWidget);
    expect(find.text('ChatGPT Pro'), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget);
    expect(find.byTooltip('隐藏到托盘'), findsOneWidget);
    expect(find.byTooltip('切换置顶小窗'), findsOneWidget);

    // 移出窗口区域：收回紧凑行，控制按钮消失。
    await gesture.moveTo(const Offset(-1, -1));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('更新于'), findsNothing);
    expect(find.byTooltip('刷新'), findsNothing);
    expect(find.textContaining('已用 '), findsOneWidget);
    // 收尾前把 500ms 闲置淡出定时器走完，避免测试结束时残留 pending timer。
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('充足状态紧凑行用 muted 色，告警状态用彩色', (tester) async {
    await _pumpSeamlessHome(tester, _CalmAndWarningRepository());
    final context = tester.element(find.byType(HomePage));
    final scheme = Theme.of(context).colorScheme;

    // 42%（充足）：百分比与圆点不着彩色。
    final calmText = tester.widget<Text>(find.text('已用 42%'));
    expect(calmText.style?.color, scheme.onSurfaceVariant);

    // 87%（告警）：百分比与状态圆点使用告警色。
    final warningText = tester.widget<Text>(find.text('已用 87%'));
    expect(warningText.style?.color, isNot(scheme.onSurfaceVariant));
    expect(
      warningText.style?.color,
      quotaStatusColor(
        (await _CalmAndWarningRepository().all()).last,
        brightness: Theme.of(context).brightness,
        scheme: scheme,
      ),
    );
  });

  testWidgets('主窗口为空时紧凑行退化为名称加状态文字', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: QuotaCard(
              quota: ProviderQuota(
                provider: Provider.glm,
                planName: 'GLM Pro',
                windows: const [],
                status: QuotaStatus.error,
                errorMessage: '模拟故障',
              ),
              seamless: true,
              expanded: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('GLM'), findsOneWidget);
    expect(find.text('查询失败'), findsOneWidget);
    expect(find.textContaining('已用 '), findsNothing);
  });

  testWidgets('刷新失败后保留旧卡片并在列表顶部显示提示条', (tester) async {
    await _pumpSeamlessHome(tester, _FlakyRepository());
    expect(find.byType(QuotaCard), findsOneWidget);

    // 第二次起仓库抛错：手动触发 reload 模拟 5 分钟定时刷新失败。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    await container.read(quotasProvider.notifier).reload();
    await tester.pump();

    expect(find.byType(QuotaCard), findsOneWidget);
    expect(find.text('刷新失败，显示上次数据'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // hover 展开后“更新于”仍显示首次成功的时间，帮助判断数据可信度。
    await _hoverFirstCard(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('更新于'), findsOneWidget);
  });

  test('DesktopController.setOpacity：web 实现调用不抛异常', () async {
    const controller = WebDesktopController();
    await controller.setOpacity(0.45);
    await controller.setOpacity(1.0);
  });

  testWidgets('闲置淡出：离开 500ms 后 setOpacity(0.45)，进入立即恢复', (tester) async {
    final opacityCalls = <double>[];
    const channel = MethodChannel('window_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setOpacity') {
        final arguments = call.arguments! as Map<Object?, Object?>;
        opacityCalls.add((arguments['opacity']! as num).toDouble());
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await _pumpSeamlessHome(tester, _SingleCardRepository());

    // 鼠标在列表内移动：不触发任何透明度调用。
    final gesture = await _hoverFirstCard(tester);
    expect(opacityCalls, isEmpty);

    // 移出窗口区域：500ms 防抖内不淡出，到点后降到 0.45。
    await gesture.moveTo(const Offset(-1, -1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 499));
    expect(opacityCalls, isEmpty);
    await tester.pump(const Duration(milliseconds: 2));
    expect(opacityCalls, [0.45]);

    // 重新进入：立即恢复 1.0。
    await gesture.moveTo(tester.getCenter(find.byType(QuotaCard).first));
    await tester.pump();
    expect(opacityCalls, [0.45, 1.0]);

    // 收尾：再次移出并走完淡出，避免 pending timer 与窗口透明度泄漏。
    await gesture.moveTo(const Offset(-1, -1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(opacityCalls, [0.45, 1.0, 0.45]);
  });
}
