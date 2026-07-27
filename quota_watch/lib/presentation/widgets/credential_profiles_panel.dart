import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/models/credential_profile.dart';
import '../../data/models/quota_models.dart';
import '../../data/repositories/backend_endpoint_policy.dart';
import '../../data/repositories/credential_profile_repository.dart';
import '../../data/repositories/platform_credential_profile_repository.dart';

/// 本机安全配置面板。
///
/// TextEditingController 只在当前页面内短暂持有用户输入；每次请求结束都会清空
/// Key。后端响应模型没有 Key 字段，所以这里也不存在回填或持久化路径。
class CredentialProfilesPanel extends StatefulWidget {
  final http.Client client;
  final String backendUrl;

  const CredentialProfilesPanel({
    super.key,
    required this.client,
    required this.backendUrl,
  });

  @override
  State<CredentialProfilesPanel> createState() =>
      _CredentialProfilesPanelState();
}

class _CredentialProfilesPanelState extends State<CredentialProfilesPanel> {
  late final Map<Provider, TextEditingController> _labelControllers;
  late final Map<Provider, TextEditingController> _keyControllers;
  late final TextEditingController _resetCountController;
  List<CredentialProfileSummary> _profiles = const [];
  DateTime? _resetExpiresAt;
  Provider? _busyProvider;
  bool _loading = false;
  String? _loadError;

  CredentialProfileStore get _repository =>
      createPlatformCredentialProfileRepository(
        client: widget.client,
        baseUrl: widget.backendUrl,
      );

  @override
  void initState() {
    super.initState();
    _labelControllers = {
      Provider.codex: TextEditingController(text: '本机 Codex 登录'),
      Provider.kimi: TextEditingController(text: 'Kimi Code'),
      Provider.glm: TextEditingController(text: 'GLM Coding Plan'),
    };
    _keyControllers = {
      Provider.kimi: TextEditingController(),
      Provider.glm: TextEditingController(),
    };
    _resetCountController = TextEditingController();
    if (isLoopbackBackendUrl(widget.backendUrl)) {
      _load();
    }
  }

  @override
  void didUpdateWidget(CredentialProfilesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backendUrl != widget.backendUrl &&
        isLoopbackBackendUrl(widget.backendUrl)) {
      _load();
    }
  }

  @override
  void dispose() {
    for (final controller in _labelControllers.values) {
      controller.dispose();
    }
    for (final controller in _keyControllers.values) {
      controller.dispose();
    }
    _resetCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isLoopbackBackendUrl(widget.backendUrl)) {
      return _RemoteBackendNotice(backendUrl: widget.backendUrl);
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(
                  Icons.security_rounded,
                  size: 20,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本机账户与密钥', style: theme.textTheme.titleMedium),
                  Text(
                    'Key 仅写入 Windows 凭据管理器，不在 Flutter 中保存或回显',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '刷新配置状态',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading && _profiles.isEmpty)
          const LinearProgressIndicator()
        else if (_loadError != null && _profiles.isEmpty)
          _InlineError(message: _loadError!, onRetry: _load)
        else ...[
          _buildCodexCard(context),
          const SizedBox(height: 10),
          _buildApiKeyCard(context, Provider.kimi),
          const SizedBox(height: 10),
          _buildApiKeyCard(context, Provider.glm),
        ],
      ],
    );
  }

  Widget _buildCodexCard(BuildContext context) {
    final profile = _profileFor(Provider.codex);
    final scheme = Theme.of(context).colorScheme;
    final busy = _busyProvider == Provider.codex;
    return _ProfileCard(
      provider: Provider.codex,
      status: profile?.sourceLabel ?? '读取中',
      configured: profile?.configured ?? false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _labelControllers[Provider.codex],
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: '账户标签（非登录名）',
              helperText: 'Codex 仍使用官方本机登录，不读取或粘贴 Token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _resetCountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '可重置次数（手动记录）',
              hintText: '例如 3',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.autorenew_rounded),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : _pickResetExpiry,
            icon: const Icon(Icons.event_outlined),
            label: Text(
              _resetExpiresAt == null
                  ? '选择重置次数到期时间'
                  : '到期 ${_formatLocalDateTime(_resetExpiresAt!)}',
            ),
          ),
          if (_resetExpiresAt != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed:
                    busy ? null : () => setState(() => _resetExpiresAt = null),
                child: const Text('清除到期时间'),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '这两个字段是本机手动备注；当前官方 Codex 本机接口未提供自动读取字段。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: busy ? null : () => _delete(Provider.codex),
                child: const Text('清除备注'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: busy ? null : _saveCodex,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('保存备注'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApiKeyCard(BuildContext context, Provider provider) {
    final profile = _profileFor(provider);
    final busy = _busyProvider == provider;
    final isEnvironment = profile?.source == CredentialSource.environment;
    return _ProfileCard(
      provider: provider,
      status: profile?.sourceLabel ?? '读取中',
      configured: profile?.configured ?? false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _labelControllers[provider],
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: '配置标签',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: ValueKey('${provider.name}-api-key-field'),
            controller: _keyControllers[provider],
            obscureText: true,
            obscuringCharacter: '•',
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: const [],
            decoration: InputDecoration(
              labelText: '新的 API Key',
              hintText: profile?.configured == true
                  ? '已配置；输入新 Key 可替换'
                  : '仅发送到当前本机后端',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key_rounded),
            ),
            onSubmitted: (_) {
              if (!busy && !isEnvironment) _saveApiKey(provider);
            },
          ),
          const SizedBox(height: 12),
          if (isEnvironment)
            Text(
              '当前由后端环境变量管理；要改用安全存储，请先移除该环境变量并重启后端。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: busy || isEnvironment || profile?.configured != true
                    ? null
                    : () => _delete(provider),
                child: const Text('删除本机配置'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: ValueKey('${provider.name}-save-api-key'),
                onPressed:
                    busy || isEnvironment ? null : () => _saveApiKey(provider),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline_rounded),
                label: Text(profile?.configured == true ? '替换 Key' : '安全保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profiles = await _repository.all();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _syncControllers(profiles);
      });
    } on CredentialProfileException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    } on Object {
      if (mounted) setState(() => _loadError = '读取安全配置失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveApiKey(Provider provider) async {
    final label = _labelControllers[provider]!.text.trim();
    final key = _keyControllers[provider]!.text.trim();
    if (label.isEmpty || key.isEmpty) {
      _showMessage('请填写配置标签和新的 API Key');
      return;
    }
    await _runMutation(provider, () async {
      final updated = await _repository.saveApiKey(
        provider: provider,
        label: label,
        apiKey: key,
      );
      if (!mounted) return;
      _replaceProfile(updated);
      _showMessage('${provider.displayName} 已安全保存');
    });
  }

  Future<void> _saveCodex() async {
    final label = _labelControllers[Provider.codex]!.text.trim();
    final rawCount = _resetCountController.text.trim();
    final resetCount = rawCount.isEmpty ? null : int.tryParse(rawCount);
    if (label.isEmpty) {
      _showMessage('请填写 Codex 账户标签');
      return;
    }
    if (rawCount.isNotEmpty && (resetCount == null || resetCount < 0)) {
      _showMessage('可重置次数必须是非负整数');
      return;
    }
    if ((resetCount == null) != (_resetExpiresAt == null)) {
      _showMessage('请同时填写可重置次数和到期时间');
      return;
    }
    await _runMutation(Provider.codex, () async {
      final updated = await _repository.saveCodexNote(
        label: label,
        resetCount: resetCount,
        resetExpiresAt: _resetExpiresAt,
      );
      if (!mounted) return;
      _replaceProfile(updated);
      _showMessage('Codex 本机备注已保存');
    });
  }

  Future<void> _delete(Provider provider) async {
    await _runMutation(provider, () async {
      final updated = await _repository.delete(provider);
      if (!mounted) return;
      _replaceProfile(updated);
      if (provider == Provider.codex) {
        _resetCountController.clear();
        _resetExpiresAt = null;
      }
      _showMessage(
        provider == Provider.codex
            ? 'Codex 手动备注已清除'
            : '${provider.displayName} 本机凭据已删除',
      );
    });
  }

  Future<void> _runMutation(
    Provider provider,
    Future<void> Function() mutation,
  ) async {
    setState(() => _busyProvider = provider);
    try {
      await mutation();
    } on CredentialProfileException catch (error) {
      _showMessage(error.message);
    } on Object {
      _showMessage('安全配置操作失败');
    } finally {
      if (mounted) {
        // 无论成功失败都尽快移除 Flutter 内存里的 Key 文本。若页面已销毁，
        // controller 已随 dispose 释放，不能再访问它。
        _keyControllers[provider]?.clear();
        setState(() => _busyProvider = null);
      }
    }
  }

  Future<void> _pickResetExpiry() async {
    final now = DateTime.now();
    final initial = _resetExpiresAt ?? now.add(const Duration(days: 30));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      helpText: '选择重置次数到期日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '选择到期时间',
    );
    if (time == null || !mounted) return;
    setState(() {
      _resetExpiresAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _replaceProfile(CredentialProfileSummary updated) {
    setState(() {
      _profiles = [
        for (final profile in _profiles)
          if (profile.provider == updated.provider) updated else profile,
        if (!_profiles.any((profile) => profile.provider == updated.provider))
          updated,
      ];
      _syncControllers(_profiles);
    });
  }

  void _syncControllers(List<CredentialProfileSummary> profiles) {
    for (final profile in profiles) {
      _labelControllers[profile.provider]?.text = profile.label;
      if (profile.provider == Provider.codex) {
        _resetCountController.text = profile.resetCount?.toString() ?? '';
        _resetExpiresAt = profile.resetExpiresAt?.toLocal();
      }
    }
  }

  CredentialProfileSummary? _profileFor(Provider provider) {
    for (final profile in _profiles) {
      if (profile.provider == provider) return profile;
    }
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ProfileCard extends StatelessWidget {
  final Provider provider;
  final String status;
  final bool configured;
  final Widget child;

  const _ProfileCard({
    required this.provider,
    required this.status,
    required this.configured,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 32,
                  decoration: BoxDecoration(
                    color: provider.brandColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    provider.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  configured
                      ? Icons.verified_user_outlined
                      : Icons.shield_outlined,
                  size: 16,
                  color: configured ? scheme.tertiary : scheme.outline,
                ),
                const SizedBox(width: 5),
                Text(
                  status,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: configured ? scheme.tertiary : scheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

class _RemoteBackendNotice extends StatelessWidget {
  final String backendUrl;

  const _RemoteBackendNotice({required this.backendUrl});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.phone_android_rounded, color: scheme.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '当前是非本机后端（$backendUrl）。移动端只查看额度；'
                '请在运行后端的 Windows 电脑上配置 Provider Key，'
                '不要把无鉴权的安全配置接口暴露到局域网或公网。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatLocalDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
