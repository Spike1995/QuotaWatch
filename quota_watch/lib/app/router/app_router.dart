// ============================================================================
// app_router.dart - 路由配置
// ============================================================================
//
// 【阶段 1 学习要点】
// - 路由 = 不同页面的"地址"。点列表项跳详情页，本质是切地址
// - 当前先用 MaterialApp 的 onGenerateRoute，先理解页面地址和页面栈
// - 页面变复杂时再评估 go_router，不为学习版提前引入额外抽象
//
// ============================================================================

// 路由文件仍然需要 Flutter 的导航类型和页面骨架类型。
import 'package:flutter/material.dart';
import '../../presentation/pages/home_page.dart';
import '../../presentation/pages/detail_page.dart';
import '../../presentation/pages/settings_page.dart';
import '../../data/models/quota_models.dart';

// 这个类只负责“地址对应哪个页面”，不负责保存页面数据。
class AppRouter {
  // `static` 表示成员属于 AppRouter 这个类本身，不需要先 `AppRouter()` 才能使用。
  // `final` 表示引用只在初始化时赋值一次；观察者对象本身不会被换掉。
  // `<PageRoute>` 是泛型：说明 RouteObserver 观察的是页面路由这一类对象。
  static final RouteObserver<PageRoute> observer = RouteObserver<PageRoute>();

  // GlobalKey 让 MaterialApp 和 Navigator 共享同一个导航器身份。
  // `<NavigatorState>` 是泛型类型参数，表示这个 key 对应 Navigator 的状态对象。
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // 返回值 `Route<Object>?` 中的 `?` 表示“可能没有路由”。
  // settings 包含本次导航请求的名字和传入参数。
  static Route<Object>? onGenerateRoute(RouteSettings settings) {
    // `switch` 根据一个值选择多个分支；这里根据路由名称决定页面。
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          // `builder: (_) => ...` 是一个匿名函数：收到上下文后创建 HomePage。
          // `_` 表示这个参数存在，但本函数不需要使用它。
          builder: (_) => const HomePage(),
          settings: settings,
        );
      case '/detail':
        // 详情页接收一个 ProviderQuota 参数
        // `as ProviderQuota` 是类型转换：告诉 Dart 此参数应当是该模型类型。
        // 如果调用方传入了错误类型，这里会在运行时报告错误。
        final quota = settings.arguments as ProviderQuota;
        return MaterialPageRoute(
          builder: (_) => DetailPage(quota: quota),
          settings: settings,
        );
      case '/settings':
        return MaterialPageRoute(
          builder: (_) => const SettingsPage(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('404 - Page not found')),
          ),
        );
    }
  }
}
