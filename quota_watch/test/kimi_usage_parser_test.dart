import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_watch/data/providers/kimi/kimi_usage_parser.dart';
import 'package:quota_watch/data/models/quota_models.dart';

void main() {
  const parser = KimiUsageParser();

  group('KimiUsageParser shared fixture parity', () {
    final fixtureDirectory = _fixtureDirectory();
    final expected = jsonDecode(
      File(
        '${fixtureDirectory.path}${Platform.pathSeparator}parity'
        '${Platform.pathSeparator}parser_expected.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    expected.remove('_comment');

    for (final entry in expected.entries) {
      test('${entry.key} matches the Python golden', () {
        final payload = jsonDecode(
          File(
            '${fixtureDirectory.path}${Platform.pathSeparator}'
            '${entry.key}',
          ).readAsStringSync(),
        ) as Map<String, dynamic>;
        payload.remove('_comment');

        final actual = parser.parse(payload).map(_normalize).toList();
        expect(actual, entry.value);
      });
    }
  });

  group('KimiUsageParser boundaries', () {
    test('rejects a non-object provider contract', () {
      expect(() => parser.parse(<Object?>[]), throwsFormatException);
      expect(() => parser.parse('not an object'), throwsFormatException);
    });

    test('drops rows missing both used and limit', () {
      final windows = parser.parse({
        'limits': [
          {
            'detail': {'name': 'unused'},
          },
        ],
      });
      expect(windows, isEmpty);
    });

    test('accepts numeric strings, remaining fallback, and clamps used', () {
      final windows = parser.parse({
        'usage': {'remaining': '20', 'limit': '100'},
        'limits': [
          {
            'detail': {'used': '150.9', 'limit': '100'},
          },
        ],
      });
      expect(windows[0].used, 80);
      expect(windows[0].limit, 100);
      expect(windows[1].used, 100);
    });

    test('derives labels using the Python parser priority', () {
      final windows = parser.parse({
        'limits': [
          {
            'detail': {'used': 1, 'limit': 10},
            'window': {'duration': 300, 'timeUnit': 'MINUTE'},
          },
          {
            'detail': {'used': 1, 'limit': 10},
            'window': {'duration': 90, 'timeUnit': 'MINUTE'},
          },
          {
            'scope': 'Daily cap',
            'detail': {'used': 1, 'limit': 10},
          },
        ],
      });
      expect(windows.map((window) => window.label), [
        '5h limit',
        '90m limit',
        'Daily cap',
      ]);
    });

    test('uses an injected UTC clock for reset_in whole-second fallback', () {
      final fixedParser = KimiUsageParser(
        clock: () => DateTime.utc(2026, 7, 27, 8, 30, 15, 999, 999),
      );
      final window = fixedParser.parse({
        'usage': {'used': 1, 'limit': 10, 'reset_in': 90},
      }).single;
      expect(window.resetAt, DateTime.utc(2026, 7, 27, 8, 31, 45));
    });

    test('accepts reset aliases and treats a naive date as UTC', () {
      final window = parser.parse({
        'usage': {'used': 1, 'limit': 10, 'reset_time': '2026-07-28'},
      }).single;
      expect(window.resetAt, DateTime.utc(2026, 7, 28));
    });

    test('ignores percentage, totalQuota, and boosterWallet', () {
      final windows = parser.parse({
        'usage': {
          'used': 40,
          'limit': 1000,
          'percentage': 999,
          'totalQuota': 2,
        },
        'boosterWallet': {
          'balance': {'amount': '999'},
        },
      });
      expect(windows, hasLength(1));
      expect(windows.single.used, 40);
      expect(windows.single.limit, 1000);
    });
  });
}

Directory _fixtureDirectory() {
  for (final path in [
    '../backend/fixtures/kimi',
    'backend/fixtures/kimi',
  ]) {
    final directory = Directory(path);
    if (directory.existsSync()) return directory;
  }
  throw StateError('找不到 backend/fixtures/kimi');
}

Map<String, Object?> _normalize(QuotaWindow window) {
  final resetAt = window.resetAt?.toUtc();
  return {
    'label': window.label,
    'used': window.used,
    'limit': window.limit,
    'unit': window.unit,
    'resetAt': resetAt?.toIso8601String().replaceFirst('.000Z', 'Z'),
  };
}
