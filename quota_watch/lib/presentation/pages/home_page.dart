// ============================================================================
// home_page.dart - 首页：三家额度卡片列表
// ============================================================================
//
// 【阶段 1 学习要点】
// - Scaffold 是 Material 页面的"骨架"（顶部 AppBar + 中间 body + 底部 FAB）
// - ListView.builder 按需渲染长列表，性能更好
// - 点击卡片 → Navigator.push 跳详情页（页面栈管理）
//
// 【AI 工具练习】
// 问 Codex："解释 ListView.builder 与 ListView.separated 的差别，先不要改代码"
// 或："这里用 Column+Expanded 还是 ListView，哪个对？"
//
// ============================================================================

import 'package:flutter/material.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models/quota_models.dart';
import '../widgets/quota_card.dart';
import '../widgets/summary_header.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late List<ProviderQuota> _quotas;

  @override
  void initState() {
    super.initState();
    _quotas = MockQuotaRepository.all();   // 后续由可注入的 Repository 替换
  }

  Future<void> _refresh() async {
    // 阶段 5 在这里接本地假后端；现在只模拟一个延迟
    await Future.delayed(const Duration(milliseconds: 600));
    setState(() {
      _quotas = MockQuotaRepository.all();
    });
  }

  void _openDetail(ProviderQuota quota) {
    Navigator.of(context).pushNamed('/detail', arguments: quota);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quota Watch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('设置页 - 阶段 5 实现')),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const SummaryHeader(),            // 顶部"总览"小卡片
            const SizedBox(height: 16),
            ..._quotas.map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: QuotaCard(
                  quota: q,
                  onTap: () => _openDetail(q),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 学习版提示：真实 API 要到假数据端到端验收后才接入
            Center(
              child: Text(
                '👆 当前为模拟数据 · 先完成可测试的开发闭环',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
