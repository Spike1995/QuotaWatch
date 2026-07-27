// 首页把 Riverpod 的 AsyncValue 转换成加载、错误、空数据和额度列表 UI。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../app/desktop/desktop_controller.dart';
import '../../app/desktop/window_drag_area.dart';
import '../../app/router/app_router.dart';
import '../../app/state/quota_state.dart';
import '../../app/theme/app_theme.dart';
import '../../data/models/quota_models.dart';
import '../../data/repositories/quota_repository.dart';
import '../widgets/centered_content.dart';
import '../widgets/quota_card.dart';

class HomePage extends ConsumerStatefulWidget {
  final ValueListenable<DisplayMode>? displayModeListenable;

  const HomePage({super.key, this.displayModeListenable});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with RouteAware {
  final Map<Provider, GlobalKey> _cardKeys = {
    for (final provider in Provider.values)
      provider: GlobalKey(debugLabel: 'desktop-${provider.name}-tile'),
  };

  PageRoute<dynamic>? _route;
  bool _routeVisible = true;
  int _regionRequest = 0;
  bool _lastDesktopWidget = false;
  List<ProviderQuota> _lastItems = const [];
  // 阶段 11：悬浮列表的滚动控制器；overflow 状态决定是否需要常驻
  // 滚动条与合并原生区域。
  final ScrollController _scrollController = ScrollController();
  bool _overflowing = false;
  // 上次成功下发给原生通道的区域签名；相同则跳过 clear/set 调用。
  String? _lastRegionSignature;
  static const String _clearedRegionSignature = 'cleared';
  // 阶段 12：闲置淡出。鼠标离开悬浮列表 500ms 后整窗降到 0.45，
  // 重新进入立即恢复 1.0；防抖避免卡片间隙穿越时闪烁。
  static const double _idleOpacity = 0.45;
  static const Duration _idleFadeDelay = Duration(milliseconds: 500);
  Timer? _idleFadeTimer;
  bool _opacityIdle = false;

  void _onSeamlessPointerEnter() {
    _idleFadeTimer?.cancel();
    if (_opacityIdle) {
      _opacityIdle = false;
      unawaited(DesktopController.instance.setOpacity(1.0));
    }
  }

  void _onSeamlessPointerExit() {
    _idleFadeTimer?.cancel();
    _idleFadeTimer = Timer(_idleFadeDelay, () {
      _opacityIdle = true;
      unawaited(DesktopController.instance.setOpacity(_idleOpacity));
    });
  }

  // 切回非 seamless 模式与 dispose 时调用：取消防抖并恢复全不透明。
  // 有 _opacityIdle 脏标记，未淡出时不会重复走原生通道。
  void _restoreFullOpacity() {
    _idleFadeTimer?.cancel();
    _idleFadeTimer = null;
    if (_opacityIdle) {
      _opacityIdle = false;
      unawaited(DesktopController.instance.setOpacity(1.0));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      if (_route != null) AppRouter.observer.unsubscribe(this);
      _route = route;
      AppRouter.observer.subscribe(this, route);
    }
  }

  @override
  void didPush() {
    _routeVisible = true;
  }

  @override
  void didPushNext() {
    _routeVisible = false;
    _scheduleDesktopRegions(enabled: false, items: const []);
  }

  @override
  void didPopNext() {
    _routeVisible = true;
    _scheduleDesktopRegions(
      enabled: _lastDesktopWidget && _lastItems.isNotEmpty,
      items: _lastItems,
    );
  }

  @override
  void didPop() {
    _routeVisible = false;
    _scheduleDesktopRegions(enabled: false, items: const []);
  }

  @override
  void dispose() {
    if (_route != null) AppRouter.observer.unsubscribe(this);
    _regionRequest += 1;
    _scrollController.dispose();
    _restoreFullOpacity();
    unawaited(DesktopController.instance.clearDesktopWidgetRegions());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quotas = ref.watch(quotasProvider);
    final settings = ref.watch(appSettingsProvider);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final modeListenable = widget.displayModeListenable ??
        DesktopController.instance.displayModeListenable;

    return ValueListenableBuilder<DisplayMode>(
      valueListenable: modeListenable,
      builder: (context, displayMode, _) {
        final isDesktopWidget = displayMode == DisplayMode.desktopWidget;
        final hasDesktopWindowControls = !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.linux);
        final items = quotas.valueOrNull ?? const <ProviderQuota>[];
        final usesTransparentCanvas = isDesktopWidget && items.isNotEmpty;
        _lastDesktopWidget = isDesktopWidget;
        _lastItems = items;
        // 阶段 12：切回非 seamless 模式时恢复整窗全不透明（脏标记防抖）。
        if (!isDesktopWidget) _restoreFullOpacity();
        _scheduleDesktopRegions(
          enabled: usesTransparentCanvas,
          items: items,
        );

        return Scaffold(
          // 只有三张原生磁贴区域建立后，Windows 底色才会切成透明。
          // 此处同步移除 Flutter 自己的页面底色，卡片 alpha 才能真正与桌面混合。
          backgroundColor:
              usesTransparentCanvas ? Colors.transparent : scheme.surface,
          // 桌面组件只保留磁贴画布，设置、隐藏和退出继续由托盘菜单承担。
          // 切回置顶小窗时恢复标题栏，避免普通窗口失去基本控制入口。
          appBar: isDesktopWidget
              ? null
              : AppBar(
                  toolbarHeight: 52,
                  // 原生标题栏隐藏后，只把标题文字作为窗口拖动把手。
                  // 不能包整个 AppBar，否则会吞掉 body 的下拉刷新手势。
                  title: hasDesktopWindowControls
                      ? const WindowDragArea(child: Text('Quota Watch'))
                      : const Text('Quota Watch'),
                  actions: [
                    IconButton(
                      tooltip: '数据设置',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/settings'),
                    ),
                    if (hasDesktopWindowControls) ...[
                      IconButton(
                        tooltip: '最小化到托盘',
                        icon: const Icon(Icons.minimize),
                        onPressed: () =>
                            DesktopController.instance.hideToTray(),
                      ),
                      IconButton(
                        tooltip: '退出 Quota Watch',
                        icon: const Icon(Icons.close),
                        onPressed: () => DesktopController.instance.quit(),
                      ),
                    ],
                  ],
                ),
          body: DecoratedBox(
            decoration: usesTransparentCanvas
                ? const BoxDecoration(color: Colors.transparent)
                : BoxDecoration(
                    // 普通置顶小窗保留稳定底色；桌面组件不绘制这层。
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.surface,
                        Color.alphaBlend(
                          scheme.primary.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.18
                                : 0.11,
                          ),
                          scheme.surface,
                        ),
                        Color.alphaBlend(
                          scheme.secondary.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.12
                                : 0.08,
                          ),
                          scheme.surface,
                        ),
                      ],
                    ),
                  ),
            // 阶段 11：基于 valueOrNull 构建 body——刷新失败但还有旧数据时
            // 继续显示卡片列表（顶部加提示条），只有完全没数据时才整页
            // 显示 loading / error。
            child: _buildBody(
              context,
              ref,
              quotas,
              seamless: isDesktopWidget,
              layoutMode: settings.layoutMode,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<ProviderQuota>> quotas, {
    required bool seamless,
    required QuotaLayoutMode layoutMode,
  }) {
    final items = quotas.valueOrNull;
    if (items == null) {
      // 首次加载失败（没有任何旧数据）才整页报错。
      if (quotas.hasError) {
        return _buildLoadError(context, ref, quotas.asError!.error);
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) return _buildEmptyState(context, ref);
    return _buildQuotaList(
      context,
      ref,
      items,
      seamless: seamless,
      layoutMode: layoutMode,
      showRefreshError: quotas.hasError,
    );
  }

  // 刷新失败但仍有上次数据时，在列表顶部显示紧凑提示条代替整页错误。
  Widget _buildRefreshErrorBanner(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '刷新失败，显示上次数据',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(quotasProvider.notifier).reload(),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError(
    BuildContext context,
    WidgetRef ref,
    Object error,
  ) {
    final message =
        error is QuotaRepositoryException ? error.message : '数据加载失败，请重试';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.read(quotasProvider.notifier).reload(),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => ref.read(quotasProvider.notifier).reload(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 120, 24, 24),
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无额度数据',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '当前数据源没有返回任何套餐',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: () => ref.read(quotasProvider.notifier).reload(),
              child: const Text('重新加载'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaList(
    BuildContext context,
    WidgetRef ref,
    List<ProviderQuota> quotas, {
    required bool seamless,
    required QuotaLayoutMode layoutMode,
    required bool showRefreshError,
  }) {
    Widget list = ListView(
      // 只在 seamless 挂滚动控制器（溢出检测与滚动条共用）；普通模式
      // 保持原样——显式 controller 会改变下拉刷新在测试与真机上的手势行为。
      controller: seamless ? _scrollController : null,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      children: [
        if (showRefreshError) _buildRefreshErrorBanner(context, ref),
        // 窄窗形成右侧竖向磁贴条；宽屏仍在 1160px 内排成横向长条。
        CenteredContent(
          maxWidth: 1160,
          child: _QuotaCardGrid(
            quotas: quotas,
            cardKeys: _cardKeys,
            seamless: seamless,
            layoutMode: layoutMode,
          ),
        ),
      ],
    );
    // 阶段 11：内容溢出时悬浮窗需要可见可拖的滚动条；未溢出时不加，
    // 保持卡片间隙的点击穿透。
    if (seamless && _overflowing) {
      list = Scrollbar(
        thumbVisibility: true,
        controller: _scrollController,
        child: list,
      );
    }
    return NotificationListener<SizeChangedLayoutNotification>(
      // 阶段 12：hover 展开/收起经 AnimatedSize 改变卡片高度，外壳内部
      // setState 不会触发首页 build；这里监听尺寸变化通知逐帧重算
      // 原生区域（脏检查会吞掉重复下发）。
      onNotification: (_) {
        if (seamless) {
          _scheduleDesktopRegions(enabled: true, items: quotas);
        }
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          if (seamless) {
            _syncOverflowState();
            _scheduleDesktopRegions(enabled: true, items: quotas);
          }
          return false;
        },
        // 阶段 12：闲置淡出——进入列表区域立即恢复，离开 500ms 后淡出。
        // MouseRegion 只在 seamless 挂载，普通窗口行为不变。
        child: MouseRegion(
          onEnter: seamless ? (_) => _onSeamlessPointerEnter() : null,
          onExit: seamless ? (_) => _onSeamlessPointerExit() : null,
          child: RefreshIndicator(
            onRefresh: () => ref.read(quotasProvider.notifier).reload(),
            child: list,
          ),
        ),
      ),
    );
  }

  // 溢出状态变化时重建一次（挂/摘滚动条、切换区域合并策略）；
  // 与区域下发的脏检查协同：重复调度会被签名比较吞掉，不会循环。
  void _syncOverflowState() {
    if (!_scrollController.hasClients) return;
    final overflowing = _scrollController.position.maxScrollExtent > 0;
    if (overflowing != _overflowing) {
      setState(() => _overflowing = overflowing);
    }
  }

  void _scheduleDesktopRegions({
    required bool enabled,
    required List<ProviderQuota> items,
  }) {
    final request = ++_regionRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || request != _regionRequest) return;
      if (!enabled || !_routeVisible) {
        await _clearDesktopRegionsIfNeeded();
        return;
      }

      // 溢出状态与区域合并策略同源，布局/数据变化后在帧末重新评估。
      _syncOverflowState();

      final viewport = Offset.zero & MediaQuery.sizeOf(context);
      final regions = <Rect>[];
      for (final quota in items) {
        final renderObject =
            _cardKeys[quota.provider]?.currentContext?.findRenderObject();
        if (renderObject is! RenderBox ||
            !renderObject.attached ||
            !renderObject.hasSize) {
          continue;
        }
        final topLeft = renderObject.localToGlobal(Offset.zero);
        final visibleRect = (topLeft & renderObject.size).intersect(viewport);
        if (!visibleRect.isEmpty) regions.add(visibleRect);
      }

      if (!mounted || request != _regionRequest) return;
      if (regions.isEmpty) {
        await _clearDesktopRegionsIfNeeded();
        return;
      }

      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      // 溢出时右缘滚动条必须可命中：把逐卡片区域合并为一条覆盖视口
      // 全宽的区域（牺牲间隙点击穿透）；未溢出时保持逐卡片区域。
      final effectiveRegions = _overflowing
          ? [_mergeRegionsForViewport(regions, viewport)]
          : regions;

      // 脏检查：开关、区域与像素比都没变时跳过原生通道调用，避免每次
      // build 与每帧滚动都走 MethodChannel。
      final signature = _regionSignature(
        regions: effectiveRegions,
        devicePixelRatio: devicePixelRatio,
      );
      if (signature == _lastRegionSignature) return;
      _lastRegionSignature = signature;
      await DesktopController.instance.setDesktopWidgetRegions(
        effectiveRegions,
        devicePixelRatio: devicePixelRatio,
        cornerRadius: AppTheme.cardRadius,
      );
    });
  }

  Future<void> _clearDesktopRegionsIfNeeded() async {
    if (_lastRegionSignature == _clearedRegionSignature) return;
    _lastRegionSignature = _clearedRegionSignature;
    await DesktopController.instance.clearDesktopWidgetRegions();
  }

  // 合并为一条覆盖视口全宽、纵向包住所有卡片的区域。
  Rect _mergeRegionsForViewport(List<Rect> regions, Rect viewport) {
    var top = regions.first.top;
    var bottom = regions.first.bottom;
    for (final region in regions.skip(1)) {
      if (region.top < top) top = region.top;
      if (region.bottom > bottom) bottom = region.bottom;
    }
    return Rect.fromLTRB(viewport.left, top, viewport.right, bottom)
        .intersect(viewport);
  }

  // Rect 比较按整数像素拼接；浮点尾差不触发原生调用。
  String _regionSignature({
    required List<Rect> regions,
    required double devicePixelRatio,
  }) {
    final buffer = StringBuffer()..write(devicePixelRatio);
    for (final region in regions) {
      buffer
        ..write('|')
        ..write(region.left.round())
        ..write(',')
        ..write(region.top.round())
        ..write(',')
        ..write(region.right.round())
        ..write(',')
        ..write(region.bottom.round());
    }
    return buffer.toString();
  }
}

// 按可用宽度把卡片排成 1～3 列的网格；列数变化时卡片宽度平均分配。
class _QuotaCardGrid extends StatelessWidget {
  final List<ProviderQuota> quotas;
  final Map<Provider, GlobalKey> cardKeys;
  final bool seamless;
  final QuotaLayoutMode layoutMode;

  const _QuotaCardGrid({
    required this.quotas,
    required this.cardKeys,
    required this.seamless,
    required this.layoutMode,
  });

  // 卡片之间的水平、垂直间距保持一致。
  static const double _spacing = 10;

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder 读取父级给的实际宽度，据此决定列数。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (layoutMode == QuotaLayoutMode.vertical) {
          final cardWidth = width.clamp(0, 360).toDouble();
          return Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: cardWidth,
              child: Column(
                children: [
                  for (var index = 0; index < quotas.length; index++) ...[
                    if (index > 0) const SizedBox(height: _spacing),
                    _buildCard(quotas[index], width: cardWidth),
                  ],
                ],
              ),
            ),
          );
        }
        if (layoutMode == QuotaLayoutMode.horizontal) {
          final cardWidth = width >= 1040
              ? (width - _spacing * 2) / 3
              : width.clamp(300, 340).toDouble();
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < quotas.length; index++) ...[
                  if (index > 0) const SizedBox(width: _spacing),
                  _buildCard(quotas[index], width: cardWidth),
                ],
              ],
            ),
          );
        }
        final columns = width >= 1100 ? 3 : (width >= 700 ? 2 : 1);
        final cardWidth = (width - _spacing * (columns - 1)) / columns;
        // Wrap 超出当前行宽时自动换行，配合固定卡片宽度即可形成网格。
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final quota in quotas) _buildCard(quota, width: cardWidth),
          ],
        );
      },
    );
  }

  Widget _buildCard(ProviderQuota quota, {required double width}) {
    return SizedBox(
      key: cardKeys[quota.provider],
      width: width,
      // 卡片已展示全部窗口，首页无需再跳转详情页。
      // seamless 卡片套一层悬浮外壳：紧凑行/hover 展开 + 整卡拖动 + 控制按钮。
      child:
          seamless ? _SeamlessCardShell(quota: quota) : QuotaCard(quota: quota),
    );
  }
}

// ============================================================================
// 悬浮卡片自治外壳（阶段 11 建立，阶段 12 加入紧凑/展开双形态）
// ============================================================================
// 未 hover 时卡片是紧凑单行（约 36px）；hover 时经 AnimatedSize 原地展开
// 为完整卡片并浮现三个小按钮（Stack 上层，位于拖动区之外，点击不会触发
// 窗口拖动）；整张卡片同时是窗口拖动把手。
class _SeamlessCardShell extends ConsumerStatefulWidget {
  final ProviderQuota quota;

  const _SeamlessCardShell({required this.quota});

  @override
  ConsumerState<_SeamlessCardShell> createState() => _SeamlessCardShellState();
}

class _SeamlessCardShellState extends ConsumerState<_SeamlessCardShell> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        children: [
          // 整卡拖动区：无标题栏悬浮窗没有系统把手。move 光标提示可拖。
          MouseRegion(
            cursor: SystemMouseCursors.move,
            child: WindowDragArea(
              // SizeChangedLayoutNotifier 把展开/收起的高度变化上报给
              // 首页，驱动原生点击区域逐帧跟随（AnimatedSize 自身只是
              // 视觉动画，不会触发任何重建）。
              child: SizeChangedLayoutNotifier(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: QuotaCard(
                    quota: widget.quota,
                    seamless: true,
                    expanded: _hovering,
                  ),
                ),
              ),
            ),
          ),
          if (_hovering)
            Positioned(
              top: 6,
              right: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HoverControlButton(
                      tooltip: '刷新',
                      icon: Icons.refresh,
                      onPressed: () =>
                          ref.read(quotasProvider.notifier).reload(),
                    ),
                    _HoverControlButton(
                      tooltip: '隐藏到托盘',
                      icon: Icons.minimize,
                      onPressed: () => DesktopController.instance.hideToTray(),
                    ),
                    _HoverControlButton(
                      tooltip: '切换置顶小窗',
                      icon: Icons.push_pin_outlined,
                      onPressed: () => DesktopController.instance
                          .setDisplayMode(DisplayMode.alwaysOnTop),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// hover 浮现的小图标按钮：18px 图标、紧凑尺寸。
class _HoverControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _HoverControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      icon: Icon(icon),
    );
  }
}
