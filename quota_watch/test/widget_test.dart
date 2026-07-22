import 'package:flutter_test/flutter_test.dart';

import 'package:quota_watch/main.dart';
import 'package:quota_watch/presentation/widgets/quota_card.dart';

void main() {
  testWidgets('首页显示三家模拟套餐', (WidgetTester tester) async {
    await tester.pumpWidget(const QuotaWatchApp());

    expect(find.text('Quota Watch'), findsOneWidget);
    final cards = find.byType(QuotaCard);
    expect(cards, findsNWidgets(3));
    expect(
      find.descendant(of: cards.at(0), matching: find.text('Codex')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cards.at(1), matching: find.text('Kimi')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cards.at(2), matching: find.text('GLM')),
      findsOneWidget,
    );
  });

  testWidgets('点击 Codex 卡片进入详情页', (WidgetTester tester) async {
    await tester.pumpWidget(const QuotaWatchApp());

    await tester.tap(find.byType(QuotaCard).at(0));
    await tester.pumpAndSettle();

    expect(find.text('ChatGPT Pro'), findsOneWidget);
  });
}
