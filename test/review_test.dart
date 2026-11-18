import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkcaps/src/design.dart';
import 'package:thinkcaps/src/lexicon.dart';
import 'package:thinkcaps/src/review_screen.dart';

void main() {
  testWidgets('each revealed card accepts a rating by swipe', (tester) async {
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
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.textContaining('через'), findsNothing);
    expect(find.textContaining('Свайп'), findsNothing);
    await tester.fling(find.text('любопытство'), const Offset(280, 0), 950);
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

  testWidgets('long words fit without splitting at a narrow screen width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const longEnglish = 'uncompromisingly-long-description';
    const longRussian = 'Оглушительными';
    final fresh = ReviewState(due: DateTime.utc(2026, 11, 18));
    final entry = Entry(
      id: 1,
      english: 'an $longEnglish',
      russian: longRussian,
      context: '',
      automatic: true,
      forward: fresh,
      reverse: fresh,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: ReviewScreen(
          queue: [ReviewCard(entry, Direction.enToRu)],
          onGrade: (_, _) async {},
        ),
      ),
    );

    Rect expectFittedWord(String word) {
      final finder = find.text(word);
      final widget = tester.widget<Text>(finder);
      expect(widget.maxLines, 1);
      expect(widget.softWrap, isFalse);
      final bounds = tester.getRect(finder);
      expect(bounds.left, greaterThanOrEqualTo(45.9));
      expect(bounds.right, lessThanOrEqualTo(314.1));
      return bounds;
    }

    final englishBounds = expectFittedWord(longEnglish);
    expect(englishBounds.top, greaterThan(tester.getRect(find.text('an')).top));
    await tester.tap(find.text('Показать перевод'));
    await tester.pumpAndSettle();
    expectFittedWord(longRussian);
    expect(tester.takeException(), isNull);
  });
}
