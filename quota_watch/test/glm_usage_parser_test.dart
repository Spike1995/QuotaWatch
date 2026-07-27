import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/data/models/quota_models.dart';
import 'package:quota_watch/data/providers/glm/glm_usage_parser.dart';

void main() {
  const parser = GlmUsageParser();

  group('GlmUsageParser shared fixture parity', () {
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
        expect(parser.parse(payload).map(_normalize).toList(), entry.value);
      });
    }
  });

  group('GlmUsageParser boundaries', () {
    test('rejects non-object contracts', () {
      expect(() => parser.parse(<Object?>[]), throwsFormatException);
      expect(() => parser.parse(null), throwsFormatException);
    });

    test('accepts top-level limits and skips malformed items', () {
      final windows = parser.parse({
        'limits': [
          null,
          {'unit': 3, 'usage': 100, 'currentValue': 10},
          {
            'type': 'TOKENS_LIMIT',
            'unit': 3,
            'usage': 100,
            'currentValue': 10,
          },
        ],
      });
      expect(windows, hasLength(1));
      expect(windows.single.used, 10);
    });

    test('uses the historical 40M limit only for a 5h absolute row', () {
      final windows = parser.parse({
        'limits': [
          {
            'type': 'TOKENS_LIMIT',
            'unit': 3,
            'currentValue': 12,
          },
          {
            'type': 'TOKENS_LIMIT',
            'unit': 6,
            'currentValue': 12,
          },
        ],
      });
      expect(windows, hasLength(1));
      expect(windows.single.limit, 40000000);
    });

    test('rejects invalid current percentages instead of clamping', () {
      for (final percentage in [-1, 101]) {
        expect(
          () => parser.parse({
            'limits': [
              {
                'type': 'TOKENS_LIMIT',
                'number': 1,
                'percentage': percentage,
              },
            ],
          }),
          throwsFormatException,
        );
      }
      expect(
        parser.parse({
          'limits': [
            {
              'type': 'TOKENS_LIMIT',
              'number': 1,
              'percentage': 'not-a-number',
            },
          ],
        }),
        isEmpty,
      );
    });

    test('keeps historical overage and adds a normalized note', () {
      final window = parser.parse({
        'limits': [
          {
            'type': 'TOKENS_LIMIT',
            'unit': 6,
            'usage': 100,
            'currentValue': 125,
            'percentage': 125,
          },
        ],
      }).single;
      expect(window.used, 125);
      expect(window.limit, 100);
      expect(window.note, '已超额（125%）');
    });

    test('parses epoch seconds, epoch milliseconds, and ISO reset times', () {
      final windows = parser.parse({
        'limits': [
          {
            'type': 'TOKENS_LIMIT',
            'unit': 3,
            'usage': 100,
            'currentValue': 10,
            'nextResetTime': 1760000000,
          },
          {
            'type': 'TOKENS_LIMIT',
            'unit': 6,
            'usage': 100,
            'currentValue': 10,
            'nextResetTime': 1760500000000,
          },
          {
            'type': 'TIME_LIMIT',
            'unit': 0,
            'usage': 10,
            'currentValue': 1,
            'nextResetTime': '2026-07-28T00:00:00Z',
          },
        ],
      });
      expect(windows[0].resetAt,
          DateTime.fromMillisecondsSinceEpoch(1760000000000, isUtc: true));
      expect(windows[1].resetAt,
          DateTime.fromMillisecondsSinceEpoch(1760500000000, isUtc: true));
      expect(windows[2].resetAt, DateTime.utc(2026, 7, 28));
    });
  });
}

Directory _fixtureDirectory() {
  for (final path in [
    '../backend/fixtures/glm',
    'backend/fixtures/glm',
  ]) {
    final directory = Directory(path);
    if (directory.existsSync()) return directory;
  }
  throw StateError('找不到 backend/fixtures/glm');
}

Map<String, Object?> _normalize(QuotaWindow window) {
  final resetAt = window.resetAt?.toUtc();
  return {
    'label': window.label,
    'used': window.used,
    'limit': window.limit,
    'unit': window.unit,
    'resetAt': resetAt?.toIso8601String().replaceFirst('.000Z', 'Z'),
    'note': window.note,
  };
}
