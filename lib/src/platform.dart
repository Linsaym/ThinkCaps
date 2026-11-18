import 'package:flutter/services.dart';

import 'lexicon.dart';

class ThinkCapsPlatform {
  static const _channel = MethodChannel('app.thinkcaps/bridge');

  void onSharedText(Future<void> Function()? callback) {
    _channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'shareAvailable') await callback();
            },
    );
  }

  Future<List<String>> drainShares() async =>
      await _channel.invokeListMethod<String>('drainShares') ?? [];

  Future<String?> scanScreenshot() =>
      _channel.invokeMethod<String>('scanScreenshot');

  Future<String> translate(String word) async {
    final result = await _channel
        .invokeMethod<String>('translate', word)
        .timeout(const Duration(seconds: 95));
    final translation = result
        ?.trim()
        .replaceFirst(RegExp(r'[,;:]+$'), '')
        .trim();
    if (translation == null || translation.isEmpty) {
      throw StateError('Empty translation');
    }
    return translation;
  }

  Future<List<Entry>> loadEntries() async {
    final rows =
        await _channel.invokeListMethod<Map<Object?, Object?>>('loadEntries') ??
        [];
    return rows.map((row) {
      ReviewState state(String prefix) => ReviewState(
        due: DateTime.fromMillisecondsSinceEpoch(row['${prefix}Due'] as int),
        streak: row['${prefix}Streak'] as int,
        days: row['${prefix}Days'] as int,
      );
      return Entry(
        id: row['id'] as int,
        english: row['english'] as String,
        russian: row['russian'] as String,
        context: row['context'] as String,
        automatic: row['automatic'] as bool,
        forward: state('en'),
        reverse: state('ru'),
      );
    }).toList();
  }

  Future<void> save({
    int? id,
    required String english,
    required String russian,
    required String context,
    required bool automatic,
  }) => _channel.invokeMethod('saveEntry', {
    'id': id,
    'english': normalizeTerm(english),
    'russian': russian.trim(),
    'context': context.trim(),
    'automatic': automatic,
    'now': DateTime.now().millisecondsSinceEpoch,
  });

  Future<void> remove(int id) => _channel.invokeMethod('removeEntry', id);

  Future<void> grade(ReviewCard card, Grade grade) {
    final next = card.state.after(grade, DateTime.now());
    return _channel.invokeMethod('grade', {
      'id': card.entry.id,
      'direction': card.direction.name,
      'due': next.due.millisecondsSinceEpoch,
      'streak': next.streak,
      'days': next.days,
    });
  }
}
