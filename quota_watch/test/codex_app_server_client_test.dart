import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/data/providers/codex/codex_app_server_client.dart';

void main() {
  test('completes the documented JSONL handshake and ignores notifications',
      () async {
    final result = await _client('success').readRateLimits();

    expect(result['rateLimits'], isA<Map<String, dynamic>>());
    final rateLimits = result['rateLimits'] as Map<String, dynamic>;
    final primary = rateLimits['primary'] as Map<String, dynamic>;
    expect(primary['usedPercent'], 25);
  });

  for (final testCase in const [
    ('auth_error', CodexClientFailure.authentication),
    ('invalid_json', CodexClientFailure.contract),
    ('oversized_line', CodexClientFailure.contract),
  ]) {
    test('maps ${testCase.$1} without surfacing raw app-server output',
        () async {
      await expectLater(
        _client(testCase.$1).readRateLimits(),
        throwsA(
          isA<CodexClientException>().having(
            (error) => error.failure,
            'failure',
            testCase.$2,
          ),
        ),
      );
    });
  }

  test('times out and terminates the temporary app-server', () async {
    final stopwatch = Stopwatch()..start();

    await expectLater(
      _client(
        'timeout',
        timeout: const Duration(milliseconds: 50),
      ).readRateLimits(),
      throwsA(
        isA<CodexClientException>().having(
          (error) => error.failure,
          'failure',
          CodexClientFailure.timeout,
        ),
      ),
    );

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('command override must be an existing absolute executable', () {
    const absolute = r'C:\QuotaWatchTests\codex.exe';
    expect(
      resolveCodexCommand(
        environment: const {'QUOTA_WATCH_CODEX_COMMAND': absolute},
        fileExists: (path) => path == absolute,
      ),
      [absolute],
    );
    expect(
      () => resolveCodexCommand(
        environment: const {
          'QUOTA_WATCH_CODEX_COMMAND': 'codex && echo unsafe',
        },
        fileExists: (_) => true,
      ),
      throwsA(isA<CodexClientException>()),
    );
  });

  test('discovers the bundled Codex executable before PATH', () {
    final separator = Platform.pathSeparator;
    final bundled = 'C:${separator}Local${separator}OpenAI${separator}Codex'
        '${separator}bin${separator}codex.exe';
    expect(
      resolveCodexCommand(
        environment: {
          'LOCALAPPDATA': 'C:${separator}Local',
          'PATH': 'C:${separator}Other',
        },
        fileExists: (path) => path == bundled,
      ),
      [bundled],
    );
  });
}

CodexAppServerClient _client(
  String mode, {
  Duration timeout = const Duration(seconds: 2),
}) {
  return CodexAppServerClient(
    command: [_pythonPath(), _fakeServerPath(), mode],
    timeout: timeout,
  );
}

String _pythonPath() {
  for (final path in [
    '../backend/.venv/Scripts/python.exe',
    'backend/.venv/Scripts/python.exe',
  ]) {
    if (File(path).existsSync()) return File(path).absolute.path;
  }
  throw StateError('找不到 backend/.venv Python（仅离线测试需要）');
}

String _fakeServerPath() {
  for (final path in [
    '../backend/tests/fake_codex_app_server.py',
    'backend/tests/fake_codex_app_server.py',
  ]) {
    if (File(path).existsSync()) return File(path).absolute.path;
  }
  throw StateError('找不到离线 Codex app-server 测试替身');
}
