// 这个文件测试“数据模型的计算规则”，不创建页面，也不打开浏览器。
// 因此它属于单元测试：输入一个 QuotaWindow，直接检查它计算出的结果。
import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/data/models/quota_models.dart';

void main() {
  // group 把同一类型的测试组织在一起，测试输出会更容易阅读。
  group('QuotaWindow 额度计算', () {
    test('正常使用量会计算剩余量和百分比', () {
      // Arrange（准备）：创建输入数据。
      final window = QuotaWindow(
        label: '测试窗口',
        used: 40,
        limit: 100,
        unit: 'tokens',
      );

      // Assert（断言）：实际结果必须与写测试前预测的产品规则一致。
      expect(window.remaining, 60);
      expect(window.usedPercent, 40);
      expect(window.isWarning, isFalse);
      expect(window.isCritical, isFalse);
      expect(window.isExhausted, isFalse);
    });

    test('零上限不会除以零', () {
      final window = QuotaWindow(
        label: '零上限窗口',
        used: 0,
        limit: 0,
        unit: 'tokens',
      );

      expect(window.remaining, 0);
      expect(window.usedPercent, 0);
      expect(window.isWarning, isFalse);
      expect(window.isCritical, isFalse);
      expect(window.isExhausted, isFalse);
    });

    test('95% 到不足 100% 属于紧张但尚未耗尽', () {
      final window = QuotaWindow(
        label: '紧张窗口',
        used: 96,
        limit: 100,
        unit: 'tokens',
      );

      expect(window.isCritical, isTrue);
      expect(window.isExhausted, isFalse);
    });

    test('超额使用会钳制数值并判定为耗尽', () {
      final window = QuotaWindow(
        label: '超额窗口',
        used: 120,
        limit: 100,
        unit: 'tokens',
      );

      expect(window.remaining, 0);
      expect(window.usedPercent, 100);
      expect(window.isWarning, isFalse);
      expect(window.isCritical, isFalse);
      expect(window.isExhausted, isTrue);
    });

    test('已经过去的重置时间不会产生负倒计时', () {
      final window = QuotaWindow(
        label: '已过期窗口',
        used: 10,
        limit: 100,
        unit: 'tokens',
        resetAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      expect(window.resetsInSeconds, 0);
    });
  });

  group('ProviderQuota 过期判断', () {
    ProviderQuota quota({DateTime? fetchedAt}) => ProviderQuota(
          provider: Provider.codex,
          planName: '测试',
          windows: const [],
          fetchedAt: fetchedAt,
        );

    test('fetchedAt 为 null 时视为已过期', () {
      expect(quota().isStale(now: DateTime(2026, 7, 23)), isTrue);
    });

    test('最近的数据不超过阈值时不过期', () {
      final now = DateTime(2026, 7, 23, 12);
      expect(
        quota(fetchedAt: now.subtract(const Duration(hours: 1)))
            .isStale(now: now),
        isFalse,
      );
    });

    test('超过默认阈值（6 小时）时视为过期', () {
      final now = DateTime(2026, 7, 23, 12);
      expect(
        quota(fetchedAt: now.subtract(const Duration(hours: 7)))
            .isStale(now: now),
        isTrue,
      );
    });

    test('可注入更短的阈值', () {
      final now = DateTime(2026, 7, 23, 12);
      expect(
        quota(fetchedAt: now.subtract(const Duration(minutes: 30))).isStale(
          now: now,
          threshold: const Duration(minutes: 10),
        ),
        isTrue,
      );
    });
  });

  group('QuotaCredits 契约解析', () {
    Map<String, dynamic> quotaJson(Object? credits) => {
          'provider': 'codex',
          'planName': 'ChatGPT Pro',
          'windows': <dynamic>[],
          'credits': credits,
        };

    test('credits 对象完整时映射三个字段', () {
      final quota = ProviderQuota.fromJson(quotaJson({
        'hasCredits': true,
        'unlimited': false,
        'balance': '50',
      }));

      expect(quota.credits, isNotNull);
      expect(quota.credits!.hasCredits, isTrue);
      expect(quota.credits!.unlimited, isFalse);
      expect(quota.credits!.balance, '50');
    });

    test('credits 缺失或为 null 时结果是 null', () {
      expect(ProviderQuota.fromJson(quotaJson(null)).credits, isNull);
      final absent = quotaJson(null)..remove('credits');
      expect(ProviderQuota.fromJson(absent).credits, isNull);
    });

    test('credits 类型不符时明确失败而不是静默吞掉', () {
      expect(
        () => ProviderQuota.fromJson(quotaJson('not-an-object')),
        throwsFormatException,
      );
      expect(
        () => ProviderQuota.fromJson(quotaJson({
          'hasCredits': 'yes',
          'unlimited': false,
        })),
        throwsFormatException,
      );
      expect(
        () => ProviderQuota.fromJson(quotaJson({
          'hasCredits': true,
          'unlimited': false,
          'balance': 50,
        })),
        throwsFormatException,
      );
    });
  });

  group('ResetAllowance 契约解析', () {
    Map<String, dynamic> quotaJson(Object? allowance) => {
          'provider': 'codex',
          'planName': 'ChatGPT Plus',
          'windows': <dynamic>[],
          'resetAllowance': allowance,
        };

    test('手动重置次数保留来源与到期时间', () {
      final quota = ProviderQuota.fromJson(quotaJson({
        'count': 3,
        'expiresAt': '2026-12-31T16:00:00Z',
        'source': 'manual',
      }));

      expect(quota.resetAllowance, isNotNull);
      expect(quota.resetAllowance!.count, 3);
      expect(quota.resetAllowance!.source, ResetAllowanceSource.manual);
      expect(quota.resetAllowance!.expiresAt, DateTime.utc(2026, 12, 31, 16));
    });

    test('负数次数与未知来源会明确失败', () {
      expect(
        () => ProviderQuota.fromJson(quotaJson({
          'count': -1,
          'source': 'manual',
        })),
        throwsFormatException,
      );
      expect(
        () => ProviderQuota.fromJson(quotaJson({
          'count': 1,
          'source': 'guessed',
        })),
        throwsFormatException,
      );
    });
  });
}
