import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/desktop/desktop_controller.dart';
import '../../app/desktop/window_native_io.dart';
import '../../app/state/quota_state.dart';
import '../../data/repositories/backend_endpoint_policy.dart';
import '../widgets/centered_content.dart';
import '../widgets/credential_profiles_panel.dart';

// 阶段 9（假数据移除）：设置页只保留"真实额度场景"选择与后端地址。
// 删除了数据来源（fixture/backend）切换，因为离线假数据已移除，
// 应用固定走真实后端。

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late QuotaScenario _scenario;
  late QuotaLayoutMode _layoutMode;
  late TextEditingController _backendUrlController;
  bool? _startupEnabled;
  bool _startupBusy = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider);
    _scenario = settings.scenario;
    _layoutMode = settings.layoutMode;
    _backendUrlController = TextEditingController(text: settings.backendUrl);
    if (_showsWindowsStartupSetting) {
      unawaited(_loadStartupSetting());
    }
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appliedSettings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Quota Watch 设置')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 宽屏时表单最多 700px 并居中，保持自然从上到下的焦点顺序。
          CenteredContent(
            maxWidth: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_showsWindowsStartupSetting) ...[
                  Text('Windows 启动', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('windows-startup-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('开机时自动启动'),
                    subtitle: Text(
                      _startupEnabled == null
                          ? '正在读取当前用户的启动设置…'
                          : '登录 Windows 后自动启动，并默认显示为桌面悬浮插件。',
                    ),
                    value: _startupEnabled ?? false,
                    onChanged: _startupEnabled == null || _startupBusy
                        ? null
                        : _setStartupEnabled,
                  ),
                  const SizedBox(height: 24),
                ],
                Text('磁贴布局', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<QuotaLayoutMode>(
                  segments: [
                    for (final mode in QuotaLayoutMode.values)
                      ButtonSegment(
                        value: mode,
                        label: Text(mode.label),
                        icon: Icon(
                          switch (mode) {
                            QuotaLayoutMode.auto =>
                              Icons.auto_awesome_mosaic_outlined,
                            QuotaLayoutMode.vertical =>
                              Icons.view_agenda_outlined,
                            QuotaLayoutMode.horizontal =>
                              Icons.view_week_outlined,
                          },
                        ),
                      ),
                  ],
                  selected: {_layoutMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setState(() => _layoutMode = selection.single);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _layoutHint(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Text('真实额度场景', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<QuotaScenario>(
                  key: ValueKey(_scenario.name),
                  initialValue: _scenario,
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                  items: QuotaScenario.values
                      .map(
                        (scenario) => DropdownMenuItem(
                          value: scenario,
                          child: Text(scenario.label),
                        ),
                      )
                      .toList(),
                  onChanged: (scenario) {
                    if (scenario != null) setState(() => _scenario = scenario);
                  },
                ),
                const SizedBox(height: 20),
                Text('后端地址', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _backendUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'http://127.0.0.1:8000',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _scenarioHint(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _apply,
                  child: const Text('应用并返回'),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 24),
                CredentialProfilesPanel(
                  client: ref.read(httpClientProvider),
                  // 安全配置始终连接“已经应用”的地址，避免用户只改了文本框
                  // 但尚未确认时，把 Key 意外发给另一个主机。
                  backendUrl: appliedSettings.backendUrl,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _showsWindowsStartupSetting =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _loadStartupSetting() async {
    final enabled = await WindowNative.getStartupEnabled();
    if (!mounted) return;
    setState(() => _startupEnabled = enabled);
    if (enabled == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取 Windows 开机自启动设置。')),
      );
    }
  }

  Future<void> _setStartupEnabled(bool enabled) async {
    final previous = _startupEnabled;
    setState(() {
      _startupEnabled = enabled;
      _startupBusy = true;
    });
    final success = await WindowNative.setStartupEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _startupBusy = false;
      if (!success) _startupEnabled = previous;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? enabled
                  ? '已开启开机自启动。'
                  : '已关闭开机自启动。'
              : '开机自启动设置失败，请确认根目录启动器仍然存在。',
        ),
      ),
    );
  }

  void _apply() {
    final backendUrl = _backendUrlController.text.trim();
    if (!_isValidBackendUrl(backendUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '远程后端必须使用 HTTPS；仅本机 127.0.0.1/localhost 可使用 HTTP',
          ),
        ),
      );
      return;
    }

    ref.read(appSettingsProvider.notifier).update(
          scenario: _scenario,
          backendUrl: backendUrl,
          layoutMode: _layoutMode,
        );
    unawaited(
      DesktopController.instance.setLayoutPreference(
        switch (_layoutMode) {
          QuotaLayoutMode.auto => DesktopLayoutPreference.automatic,
          QuotaLayoutMode.vertical => DesktopLayoutPreference.vertical,
          QuotaLayoutMode.horizontal => DesktopLayoutPreference.horizontal,
        },
      ),
    );
    ref.invalidate(quotasProvider);
    Navigator.of(context).pop();
  }

  String _layoutHint() {
    return switch (_layoutMode) {
      QuotaLayoutMode.auto => '根据窗口宽度自动使用 1～3 列。',
      QuotaLayoutMode.vertical => '三张磁贴固定从上到下排列，适合桌面右侧竖条。',
      QuotaLayoutMode.horizontal => '三张磁贴固定从左到右排列，窄屏可横向滑动。',
    };
  }

  String _scenarioHint() {
    switch (_scenario) {
      case QuotaScenario.codexReal:
        return '仅从官方本机 Codex 登录读取额度；不接收登录 Token。';
      case QuotaScenario.kimiReal:
        return 'Kimi Key 可在下方安全面板写入 Windows 凭据管理器。';
      case QuotaScenario.glmReal:
        return 'GLM Key 可在下方安全面板配置；不读取 ZCode 私有数据。';
      case QuotaScenario.allReal:
        return '同时查询已启用或已有本机安全凭据的服务。';
    }
  }

  bool _isValidBackendUrl(String value) {
    return isAllowedBackendUrl(value);
  }
}
