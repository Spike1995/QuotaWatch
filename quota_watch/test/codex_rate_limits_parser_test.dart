import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/providers/codex/codex_rate_limits_parser.dart';

void main() {
  const parser = CodexRateLimitsParser();
  final fixedNow = DateTime.utc(2026, 7, 27);

  test('matches the Python golden for the sanitized app-server fixture', () {
    final fixtureDirectory = _fixtureDirectory();
    final payload = jsonDecode(
      File(
        '${fixtureDirectory.path}${Platform.pathSeparator}'
        'rate_limits_typical.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>
      ..remove('_comment');
    final expected = jsonDecode(
      File(
        '${fixtureDirectory.path}${Platform.pathSeparator}parity'
        '${Platform.pathSeparator}parser_expected.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>
      ..remove('_comment');

    expect(_normalize(parser.parse(payload, fetchedAt: fixedNow)), expected);
  });

  test('prefers the codex bucket and maps known plans', () {
    final result = parser.parse({
      'rateLimits': {
        'primary': {'usedPercent': 99},
      },
      'rateLimitsByLimitId': {
        'other': {
          'limitId': 'other',
          'primary': {'usedPercent': 90},
        },
        'selected': {
          'limitId': 'codex',
          'planType': 'pro',
          'primary': {'usedPercent': 12, 'windowDurationMins': 300},
        },
      },
    }, fetchedAt: fixedNow);

    expect(result.planName, 'ChatGPT Pro');
    expect(result.windows.single.used, 12);
  });

  test('clamps percentages and derives fallback labels', () {
    final result = parser.parse({
      'rateLimits': {
        'primary': {'usedPercent': -2},
        'secondary': {'usedPercent': 120},
      },
    }, fetchedAt: fixedNow);

    expect(result.windows.map((window) => (window.label, window.used)), [
      ('主额度窗口', 0),
      ('次额度窗口', 100),
    ]);
  });

  test('marks a reached limit without exposing the provider payload', () {
    final result = parser.parse({
      'rateLimits': {
        'rateLimitReachedType': 'primary',
        'primary': {'usedPercent': 100},
      },
    }, fetchedAt: fixedNow);
    expect(result.windows.single.note, contains('已触发额度限制'));
  });

  test('rejects malformed windows, times, and missing snapshots', () {
    for (final payload in [
      <String, Object?>{},
      {
        'rateLimits': <String, Object?>{},
      },
      {
        'rateLimits': {
          'primary': {'usedPercent': '25'},
        },
      },
      {
        'rateLimits': {
          'primary': {'usedPercent': 25, 'resetsAt': 'soon'},
        },
      },
      {
        'rateLimits': {
          'primary': {'usedPercent': 25, 'windowDurationMins': 0},
        },
      },
    ]) {
      expect(
        () => parser.parse(payload, fetchedAt: fixedNow),
        throwsFormatException,
      );
    }
  });

  test('validates optional credits exactly', () {
    final valid = parser.parse({
      'rateLimits': {
        'primary': {'usedPercent': 1},
        'credits': {
          'hasCredits': true,
          'unlimited': false,
          'balance': ' 50 ',
        },
      },
    }, fetchedAt: fixedNow);
    expect(valid.credits?.balance, '50');

    for (final credits in [
      'invalid',
      {'hasCredits': 'yes', 'unlimited': false},
      {'hasCredits': true, 'unlimited': 0},
      {'hasCredits': true, 'unlimited': false, 'balance': 50},
      {'hasCredits': true, 'unlimited': false, 'balance': '   '},
      {'hasCredits': true, 'unlimited': false, 'balance': 'x' * 33},
    ]) {
      expect(
        () => parser.parse({
          'rateLimits': {
            'primary': {'usedPercent': 1},
            'credits': credits,
          },
        }, fetchedAt: fixedNow),
        throwsFormatException,
      );
    }
  });
}

Directory _fixtureDirectory() {
  for (final path in [
    '../backend/fixtures/codex',
    'backend/fixtures/codex',
  ]) {
    final directory = Directory(path);
    if (directory.existsSync()) return directory;
  }
  throw StateError('找不到 backend/fixtures/codex');
}

Map<String, Object?> _normalize(ProviderQuota quota) {
  return {
    'provider': quota.provider.name,
    'planName': quota.planName,
    'planType': quota.planType,
    'windows': [
      for (final window in quota.windows)
        {
          'label': window.label,
          'used': window.used,
          'limit': window.limit,
          'unit': window.unit,
          'resetAt': window.resetAt
              ?.toUtc()
              .toIso8601String()
              .replaceFirst('.000Z', 'Z'),
          'note': window.note,
        },
    ],
    'credits': quota.credits == null
        ? null
        : {
            'hasCredits': quota.credits!.hasCredits,
            'unlimited': quota.credits!.unlimited,
            'balance': quota.credits!.balance,
          },
  };
}
