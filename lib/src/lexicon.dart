import 'dart:collection';

enum Direction {
  enToRu('EN → RU', 'EN', 'RU'),
  ruToEn('RU → EN', 'RU', 'EN');

  const Direction(this.label, this.promptCode, this.answerCode);
  final String label;
  final String promptCode;
  final String answerCode;
}

enum Grade { again, remembered }

class ReviewState {
  const ReviewState({required this.due, this.streak = 0, this.days = 0});
  final DateTime due;
  final int streak;
  final int days;

  ReviewState after(Grade grade, DateTime now) {
    if (grade == Grade.again) {
      return ReviewState(due: now.add(const Duration(minutes: 5)));
    }
    final interval = switch (days) {
      0 => 1,
      1 => 3,
      _ => (days * 2.15).round().clamp(1, 180),
    };
    return ReviewState(
      due: now.add(Duration(days: interval)),
      streak: streak + 1,
      days: interval,
    );
  }
}

class Entry {
  const Entry({
    required this.id,
    required this.english,
    required this.russian,
    required this.context,
    required this.automatic,
    required this.forward,
    required this.reverse,
  });

  final int id;
  final String english;
  final String russian;
  final String context;
  final bool automatic;
  final ReviewState forward;
  final ReviewState reverse;

  ReviewState state(Direction direction) =>
      direction == Direction.enToRu ? forward : reverse;

  bool dueAt(DateTime now) =>
      !forward.due.isAfter(now) || !reverse.due.isAfter(now);
}

class ReviewCard {
  const ReviewCard(this.entry, this.direction);
  final Entry entry;
  final Direction direction;

  String get prompt =>
      direction == Direction.enToRu ? entry.english : entry.russian;
  String get answer =>
      direction == Direction.enToRu ? entry.russian : entry.english;
  ReviewState get state => entry.state(direction);
}

List<ReviewCard> dueCards(Iterable<Entry> entries, DateTime now) {
  final forward = Queue<ReviewCard>();
  final reverse = Queue<ReviewCard>();
  for (final entry in entries.toList().reversed) {
    if (!entry.forward.due.isAfter(now)) {
      forward.add(ReviewCard(entry, Direction.enToRu));
    }
    if (!entry.reverse.due.isAfter(now)) {
      reverse.add(ReviewCard(entry, Direction.ruToEn));
    }
  }
  final queue = <ReviewCard>[];
  while (forward.isNotEmpty || reverse.isNotEmpty) {
    final last = queue.lastOrNull;
    final preferForward = last?.direction != Direction.enToRu;
    final preferred = preferForward ? forward : reverse;
    final alternate = preferForward ? reverse : forward;
    final previousId = last?.entry.id;
    if (preferred.length > 1 && preferred.first.entry.id == previousId) {
      preferred.addLast(preferred.removeFirst());
    }
    if (preferred.isNotEmpty && preferred.first.entry.id != previousId) {
      queue.add(preferred.removeFirst());
    } else if (alternate.isNotEmpty) {
      queue.add(alternate.removeFirst());
    } else {
      queue.add(preferred.removeFirst());
    }
  }
  return queue;
}

String plural(int count, String one, String few, String many) {
  if (count % 100 >= 11 && count % 100 <= 14) return many;
  return switch (count % 10) {
    1 => one,
    2 || 3 || 4 => few,
    _ => many,
  };
}

String normalizeTerm(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ').replaceAll('’', "'");

bool isEnglishTerm(String text) {
  final word = normalizeTerm(text);
  return word.length <= 80 &&
      RegExp(r"^[a-zA-Z]+(?:[ .'-][a-zA-Z]+)*$").hasMatch(word);
}

final englishWord = RegExp(r"[a-zA-Z]+(?:[’'-][a-zA-Z]+)*");
final webLink = RegExp(r'(?:https?://|www\.)[^\s]+', caseSensitive: false);

List<String> extractSentences(String text) {
  const abbreviations = {'mr', 'mrs', 'ms', 'dr', 'st', 'prof', 'vs', 'etc'};
  final paragraphs = text
      .replaceAll('\r\n', '\n')
      .trim()
      .split(RegExp(r'\n\s*\n'));
  final sentences = <String>[];
  for (final paragraph in paragraphs) {
    final clean = paragraph
        .replaceAll(webLink, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    var start = 0;
    for (final boundary in RegExp('([.!?…]+[”"»’)]*)\\s+').allMatches(clean)) {
      final sentence = clean.substring(start, boundary.start);
      final trailing = RegExp(r'\b([A-Za-z]+)$').firstMatch(sentence)?.group(1);
      if (boundary[1]!.startsWith('.') &&
          trailing != null &&
          (trailing.length == 1 ||
              abbreviations.contains(trailing.toLowerCase()))) {
        continue;
      }
      final part = clean
          .substring(start, boundary.start + boundary[1]!.length)
          .trim();
      if (englishWord.hasMatch(part)) sentences.add(part);
      start = boundary.end;
    }
    final remainder = clean.substring(start).trim();
    if (englishWord.hasMatch(remainder)) sentences.add(remainder);
  }
  return sentences;
}
