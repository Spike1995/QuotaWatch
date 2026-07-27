import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:quota_watch/app/state/quota_state.dart';
import 'package:quota_watch/app/desktop/window_native_io.dart';
import 'package:quota_watch/presentation/pages/settings_page.dart';

import 'helpers/sample_quota_repository.dart';

const _startupChannel = MethodChannel('quota_watch/window');

MockClient _profileClient() {
  return MockClient(
    (_) async => http.Response.bytes(
      utf8.encode(
        '[{"provider":"codex","label":"本机 Codex 登录",'
        '"configured":true,"source":"codex_local_login"},'
        '{"provider":"kimi","label":"Kimi Code",'
        '"configured":false,"source":"not_configured"},'
        '{"provider":"glm","label":"GLM Coding Plan",'
        '"configured":false,"source":"not_configured"}]',
      ),
      200,
    ),
  );
}

Future<void> _pumpSettings(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(700, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quotaRepositoryProvider.overrideWithValue(
          const SampleQuotaRepository(),
        ),
        httpClientProvider.overrideWithValue(_profileClient()),
      ],
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_startupChannel, null);
  });

  testWidgets('Windows 设置页可以开启当前用户的开机自启动', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_startupChannel, (call) async {
        calls.add(call);
        if (call.method == 'getStartupEnabled') return false;
        if (call.method == 'setStartupEnabled') return true;
        return null;
      });

      await _pumpSettings(tester);

      final switchFinder = find.byKey(const ValueKey('windows-startup-switch'));
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
      expect(find.text('已开启开机自启动。'), findsOneWidget);
      final write = calls.lastWhere(
        (call) => call.method == 'setStartupEnabled',
      );
      expect(write.arguments, {'enable': true});
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('原生写入失败时自启动开关回滚并提示原因', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_startupChannel, (call) async {
        if (call.method == 'getStartupEnabled') return true;
        if (call.method == 'setStartupEnabled') return false;
        return null;
      });

      await _pumpSettings(tester);

      final switchFinder = find.byKey(const ValueKey('windows-startup-switch'));
      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
      expect(
        find.text('开机自启动设置失败，请确认根目录启动器仍然存在。'),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('Windows 凭据通道只请求白名单 Provider 且不回显到参数', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_startupChannel, (call) async {
      calls.add(call);
      if (call.method == 'readProviderApiKey') {
        return 'offline-secret-placeholder';
      }
      return null;
    });

    final value = await WindowNative.readProviderApiKey('kimi');
    final unsupported = await WindowNative.readProviderApiKey('codex');

    expect(value, 'offline-secret-placeholder');
    expect(unsupported, isNull);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'readProviderApiKey');
    expect(calls.single.arguments, {'provider': 'kimi'});
  });

  test('Windows 原生配置写入只使用固定方法和非秘密元数据', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_startupChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'writeProviderApiKey' ||
        'deleteProviderApiKey' ||
        'writeCredentialMetadata' =>
          true,
        'readCredentialMetadata' => '{"version":1,"profiles":{}}',
        _ => null,
      };
    });

    expect(
      await WindowNative.writeProviderApiKey(
        'glm',
        'offline-secret-placeholder',
      ),
      isTrue,
    );
    expect(await WindowNative.deleteProviderApiKey('glm'), isTrue);
    expect(await WindowNative.readCredentialMetadata(), contains('profiles'));
    expect(
      await WindowNative.writeCredentialMetadata(
        '{"version":1,"profiles":{"glm":{"label":"Local"}}}',
      ),
      isTrue,
    );

    expect(calls.map((call) => call.method), [
      'writeProviderApiKey',
      'deleteProviderApiKey',
      'readCredentialMetadata',
      'writeCredentialMetadata',
    ]);
    final metadataCall = calls.last;
    expect(jsonEncode(metadataCall.arguments), isNot(contains('apiKey')));
    expect(jsonEncode(metadataCall.arguments), isNot(contains('secret')));
  });
}
