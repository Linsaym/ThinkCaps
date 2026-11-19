import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkcaps/src/design.dart';
import 'package:thinkcaps/src/lexicon.dart';
import 'package:thinkcaps/src/review_screen.dart';

void main() {
  testWidgets('only English terms speak and card taps reveal both terms', (
    tester,
  ) async {
    final now = tester.binding.clock.now;
    final fresh = ReviewState(due: now());
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
    final spoken = <String>[];
    final englishTerm = find.text('curiosity');
    final russianTerm = find.text('любопытство');
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: ReviewScreen(
          queue: dueCards([entry], fresh.due),
          spacing: ReviewSpacing(),
          now: now,
          onGrade: (card, grade) async {
            ratings.add((card.direction, grade));
            return card.state.after(grade, now());
          },
          onSpeak: (word) async => spoken.add(word),
          onStopSpeech: () async {},
        ),
      ),
    );
    expect(find.text('curiosity'), findsOneWidget);
    expect(find.text('любопытство'), findsNothing);
    expect(find.text('Показать перевод'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    await tester.tap(englishTerm);
    await tester.pumpAndSettle();
    expect(spoken, ['curiosity']);
    expect(find.text('любопытство'), findsNothing);
    await tester.fling(find.text('curiosity'), const Offset(280, 0), 650);
    await tester.pumpAndSettle();
    expect(ratings, isEmpty);
    await tester.tapAt(tester.getCenter(englishTerm) + const Offset(0, -105));
    await tester.pumpAndSettle();
    expect(find.text('любопытство'), findsOneWidget);
    expect(find.text('curiosity'), findsOneWidget);
    expect(find.text(entry.context), findsOneWidget);
    await tester.tap(russianTerm);
    await tester.pumpAndSettle();
    expect(spoken, ['curiosity']);
    await tester.tap(englishTerm);
    await tester.pumpAndSettle();
    expect(spoken, List.filled(2, 'curiosity'));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.textContaining('через'), findsNothing);
    expect(find.textContaining('Свайп'), findsNothing);
    await tester.fling(find.text('любопытство'), const Offset(280, 0), 950);
    await tester.pumpAndSettle();
    expect(find.text('Пауза перед повторением'), findsOneWidget);
    expect(find.text('RU → EN'), findsNothing);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('RU → EN'), findsOneWidget);
    expect(find.text('любопытство'), findsOneWidget);
    expect(find.text('curiosity'), findsNothing);
    expect(find.text('Показать перевод'), findsNothing);
    await tester.tap(russianTerm);
    await tester.pumpAndSettle();
    expect(spoken, List.filled(2, 'curiosity'));
    expect(find.text('любопытство'), findsOneWidget);
    expect(find.text('curiosity'), findsOneWidget);
    await tester.tap(englishTerm);
    await tester.pumpAndSettle();
    expect(spoken, List.filled(3, 'curiosity'));
    await tester.tap(russianTerm);
    await tester.pumpAndSettle();
    expect(spoken, List.filled(3, 'curiosity'));
    await tester.fling(find.text('curiosity'), const Offset(-280, 0), 950);
    await tester.pumpAndSettle();
    expect(ratings, [
      (Direction.enToRu, Grade.remembered),
      (Direction.ruToEn, Grade.again),
    ]);
    expect(find.text('Пауза перед повторением'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed card returns in the open session when due', (
    tester,
  ) async {
    final now = tester.binding.clock.now;
    final mature = ReviewState(due: now(), days: 28, streak: 5);
    final entry = Entry(
      id: 1,
      english: 'forest',
      russian: 'лес',
      context: '',
      automatic: false,
      forward: mature,
      reverse: mature,
    );
    final other = Entry(
      id: 2,
      english: 'sea',
      russian: 'море',
      context: '',
      automatic: false,
      forward: mature,
      reverse: mature,
    );
    final ratings = <(int, Grade)>[];
    late DateTime retryAt;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(),
        home: ReviewScreen(
          queue: [
            ReviewCard(entry, Direction.enToRu),
            ReviewCard(other, Direction.enToRu),
          ],
          spacing: ReviewSpacing(),
          now: now,
          onGrade: (card, grade) async {
            ratings.add((card.state.days, grade));
            final next = card.state.after(grade, now());
            if (grade == Grade.again) retryAt = next.due;
            return next;
          },
          onSpeak: (_) async {},
          onStopSpeech: () async {},
        ),
      ),
    );

    await tester.tap(find.text('EN → RU'));
    await tester.pumpAndSettle();
    await tester.fling(find.text('лес'), const Offset(-280, 0), 950);
    await tester.pumpAndSettle();
    expect(find.text('sea'), findsOneWidget);
    expect(find.text('forest'), findsNothing);
    await tester.tap(find.text('EN → RU'));
    await tester.pumpAndSettle();
    await tester.fling(find.text('море'), const Offset(280, 0), 950);
    await tester.pumpAndSettle();

    expect(find.text('Пауза перед повторением'), findsOneWidget);
    expect(find.text('forest'), findsNothing);

    const tick = Duration(milliseconds: 1);
    await tester.pump(retryAt.difference(now()) - tick);
    expect(find.text('forest'), findsNothing);
    await tester.pump(tick);
    expect(find.text('forest'), findsOneWidget);
    expect(find.text('лес'), findsNothing);

    await tester.tap(find.text('EN → RU'));
    await tester.pumpAndSettle();
    await tester.fling(find.text('лес'), const Offset(280, 0), 950);
    await tester.pumpAndSettle();
    expect(ratings, [
      (28, Grade.again),
      (28, Grade.remembered),
      (0, Grade.remembered),
    ]);
    expect(find.text('Повторение завершено'), findsOneWidget);
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
    final now = tester.binding.clock.now;
    final fresh = ReviewState(due: now());
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
          spacing: ReviewSpacing(),
          now: now,
          onGrade: (card, grade) async => card.state.after(grade, now()),
          onSpeak: (_) async {},
          onStopSpeech: () async {},
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
    await tester.tapAt(englishBounds.center + const Offset(0, -105));
    await tester.pumpAndSettle();
    expectFittedWord(longRussian);
    expectFittedWord(longEnglish);
    expect(tester.takeException(), isNull);
  });
}
