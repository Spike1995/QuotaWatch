// ============================================================================
// app_router.dart - 路由配置
// ============================================================================
//
// 【阶段 1 学习要点】
// - 路由 = 不同页面的"地址"。点列表项跳详情页，本质是切地址
// - Flutter 的 Navigator 2.0 配 Router API 略复杂，这里先用手写的 GoRouter 风格封装
// - 阶段 6 上线时再换正式的 go_router 包
//
// ============================================================================

import 'package:flutter/material.dart';
import '../../presentation/pages/home_page.dart';
import '../../presentation/pages/detail_page.dart';
import '../../data/models/quota_models.dart';

class AppRouter {
  // 静态路由配置（路由名 -> 构造函数）
  static final RouteObserver<PageRoute> observer = RouteObserver<PageRoute>();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Route<Object>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          builder: (_) => const HomePage(),
          settings: settings,
        );
      case '/detail':
        // 详情页接收一个 ProviderQuota 参数
        final quota = settings.arguments as ProviderQuota;
        return MaterialPageRoute(
          builder: (_) => DetailPage(quota: quota),
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

  // 简化版 routerConfig（给 MaterialApp.router 用）
  static RouterConfig<Object> get config => RouterConfig(
        routerDelegate: RouterDelegate(
          builder: (context, state) => Navigator(
            observers: [observer],
            onGenerateRoute: onGenerateRoute,
            pages: const [
              MaterialPage(child: HomePage()),
            ],
          ),
        ),
      );
}
