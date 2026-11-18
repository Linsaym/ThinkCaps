import 'package:flutter_test/flutter_test.dart';
import 'package:thinkcaps/src/lexicon.dart';

void main() {
  final now = DateTime.utc(2026, 11, 18);

  test('both directions are due independently', () {
    final fresh = ReviewState(due: now);
    final entry = Entry(
      id: 1,
      english: 'curiosity',
      russian: 'любопытство',
      context: 'Curiosity can be a great teacher.',
      automatic: true,
      forward: fresh.after(Grade.remembered, now),
      reverse: fresh,
    );
    final queue = dueCards([entry], now);
    expect(queue.map((card) => card.direction), [Direction.ruToEn]);
    expect(queue.single.prompt, 'любопытство');
    expect(queue.single.answer, 'curiosity');
    expect(dueCards([entry], now.add(const Duration(days: 1))).length, 2);
  });

  test('recalls extend intervals and lapses reset the learning step', () {
    final fresh = ReviewState(due: now);
    final dayOne = fresh.after(Grade.remembered, now);
    expect(dayOne.days, 1);
    expect(dayOne.due, now.add(const Duration(days: 1)));
    final dayThree = dayOne.after(Grade.remembered, dayOne.due);
    expect(dayThree.days, 3);
    final lapse = dayThree.after(Grade.again, dayThree.due);
    expect(lapse.days, 0);
    expect(lapse.streak, 0);
    expect(lapse.due, dayThree.due.add(const Duration(minutes: 5)));
  });

  test('questions for the same term are separated when possible', () {
    final state = ReviewState(due: now);
    final entries = [
      for (final (index, (english, russian)) in [
        ('forest', 'лес'),
        ('sea', 'море'),
      ].indexed)
        Entry(
          id: index,
          english: english,
          russian: russian,
          context: '',
          automatic: false,
          forward: state,
          reverse: state,
        ),
    ];
    final queue = dueCards(entries, now);
    expect(queue, hasLength(4));
    for (var index = 1; index < queue.length; index++) {
      expect(queue[index].entry.id, isNot(queue[index - 1].entry.id));
    }
  });

  test(
    'text import retains punctuation, contractions and wrapped OCR lines',
    () {
      final result = extractSentences(
        'Dr. Green can’t see the\nwell-lit garden. Look again!\n\n'
        'https://example.com/article\n\nТолько русский текст.',
      );
      expect(result, [
        'Dr. Green can’t see the well-lit garden.',
        'Look again!',
      ]);
      expect(
        englishWord.allMatches(result.first).map((match) => match[0]),
        containsAll(['can’t', 'well-lit']),
      );
      expect(isEnglishTerm("can’t"), isTrue);
      expect(isEnglishTerm('вспомнил'), isFalse);
    },
  );
}
