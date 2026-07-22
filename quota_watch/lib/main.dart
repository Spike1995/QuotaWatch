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

import 'package:flutter/material.dart';
import 'app/theme/app_theme.dart';
import 'app/router/app_router.dart';

void main() {
  runApp(const QuotaWatchApp());
}

class QuotaWatchApp extends StatelessWidget {
  const QuotaWatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Quota Watch',
      debugShowCheckedModeBanner: false,

      // 主题（亮色 + 暗色，跟随系统）
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,

      // 路由（用 go_router 风格的静态配置，这里先简化手写）
      routerConfig: AppRouter.config,
    );
  }
}
