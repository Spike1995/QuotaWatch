// ============================================================================
// main.dart - 应用入口
// ============================================================================
//
// 【阶段 1 学习要点】
// - main() 是所有 Dart 程序的入口
// - runApp() 把根 widget 挂载到屏幕上
// - MaterialApp 配置全局主题、路由
//
// 【AI 工具练习】
// 问 Codex："解释一下 MaterialApp 的 theme 和 darkTheme 怎么联动系统主题"
//
// ============================================================================

// `import` 把另一个库公开的类型和函数引入当前文件。
// 这里引入 Flutter 的 Material 库，才能使用 Widget、MaterialApp、ThemeMode 等类型。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/theme/app_theme.dart';
import 'app/router/app_router.dart';
import 'app/desktop/desktop_controller.dart';

// `main()` 是 Dart 程序约定的入口函数：程序启动时先从这里执行。
// 阶段 9 改成 async：桌面控制器（window_manager）需要 await 完成窗口初始化
// 之后，再 runApp，否则插件通道可能还没和原生窗口建立连接。
//
// `Future<void>` 表示这是一个返回"未来完成"的异步函数。
Future<void> main() async {
  // 使用任何 Flutter 服务（如 window_manager）前，必须先确保 Flutter 绑定
  // 已初始化——否则在 main 里直接 await 会抛 "Binding has not been
  // initialized" 异常。runApp 内部会自动调用它，但这里我们在 runApp 之前
  // 就要 await 异步初始化，所以需要手动调一次。
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面控制器：Windows 上设置小窗尺寸/无边框/置顶；Web 上为空操作。
  // 用 conditional import 自动按平台二选一，Web 构建不受影响。
  await DesktopController.instance.init();

  // ProviderScope 保存整个应用共享的数据模式、Repository 和异步查询状态。
  runApp(const ProviderScope(child: QuotaWatchApp()));
}

// `class` 定义一种对象结构；`extends` 表示 QuotaWatchApp 继承 Flutter
// 提供的 StatelessWidget 行为。StatelessWidget 适合自身没有可变页面状态的组件。
class QuotaWatchApp extends StatelessWidget {
  // `{super.key}` 是命名参数写法：把可选的 Widget key 直接交给父类。
  // key 用于在 Widget 树更新时识别“这是同一个组件”；本例不需要自定义 key。
  const QuotaWatchApp({super.key});

  // `@override` 告诉 Dart：下面的方法是在实现父类要求的同名方法。
  // `build` 接收 BuildContext（当前 Widget 在树中的位置），返回要显示的 Widget。
  @override
  Widget build(BuildContext context) {
    // MaterialApp 是应用外壳：集中提供主题、导航器和初始路由。
    return MaterialApp(
      title: 'Quota Watch',
      debugShowCheckedModeBanner: false,

      // 主题（亮色 + 暗色，跟随系统）。这些值会向下传给子 Widget。
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,

      // 路由：页面地址和页面创建规则放在 AppRouter，便于理解页面栈。
      navigatorKey: AppRouter.navigatorKey,
      navigatorObservers: [AppRouter.observer],
      onGenerateRoute: AppRouter.onGenerateRoute,
      initialRoute: '/',
    );
  }
}
