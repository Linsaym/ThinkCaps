import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkcaps/src/design.dart';
import 'package:thinkcaps/src/lexicon.dart';
import 'package:thinkcaps/src/review_screen.dart';

void main() {
  testWidgets('both directions reveal before accepting a rating', (
    tester,
  ) async {
    final fresh = ReviewState(due: DateTime.utc(2026, 11, 18));
    final entry = Entry(
      id: 1,
      english: 'curiosity',
      russian: 'любопытство',
      context: 'Curiosity can be a great teacher.',
      automatic: true,
      forward: fresh,
      reverse: fresh,
    );
    final ratings = <(Direction, Grade)>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: ReviewScreen(
          queue: dueCards([entry], fresh.due),
          onGrade: (card, grade) async => ratings.add((card.direction, grade)),
        ),
      ),
    );
    expect(find.text('curiosity'), findsOneWidget);
    expect(find.text('любопытство'), findsNothing);
    await tester.fling(find.text('curiosity'), const Offset(280, 0), 650);
    await tester.pumpAndSettle();
    expect(ratings, isEmpty);
    await tester.tap(find.text('Показать перевод'));
    await tester.pumpAndSettle();
    expect(find.text('любопытство'), findsOneWidget);
    expect(find.text(entry.context), findsOneWidget);
    await tester.tap(find.text('Вспомнил'));
    await tester.pumpAndSettle();
    expect(find.text('RU → EN'), findsOneWidget);
    expect(find.text('любопытство'), findsOneWidget);
    expect(find.text('curiosity'), findsNothing);
    await tester.tap(find.text('Показать перевод'));
    await tester.pumpAndSettle();
    await tester.fling(find.text('curiosity'), const Offset(-280, 0), 950);
    await tester.pumpAndSettle();
    expect(ratings, [
      (Direction.enToRu, Grade.remembered),
      (Direction.ruToEn, Grade.again),
    ]);
    expect(find.text('Повторение завершено'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
