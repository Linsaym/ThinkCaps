import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkcaps/src/card_editor_screen.dart';
import 'package:thinkcaps/src/design.dart';
import 'package:thinkcaps/src/lexicon.dart';
import 'package:thinkcaps/src/platform.dart';
import 'package:thinkcaps/src/suggestions.dart';

void main() {
  testWidgets('English field requests standard system keyboard behavior', (
    tester,
  ) async {
    mockPlatform();
    await tester.pumpWidget(_screen(_Suggestions()));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    final client = tester.testTextInput.log.lastWhere(
      (call) => call.method == 'TextInput.setClient',
    );
    final configuration = (client.arguments as List<Object?>)[1] as Map;
    expect(configuration['enableSuggestions'], isTrue);
    expect(configuration['autocorrect'], isTrue);
    expect(field.selectionEnabled, isTrue);
  });

  test(
    'dictionary prioritizes distinct senses and removes duplicate spellings',
    () {
      final raw = jsonEncode({
        'word': 'give up',
        'lang_code': 'en',
        'translations': [
          {'code': 'ru', 'sense': 'surrender', 'word': 'сдава́ться'},
          {'code': 'ru', 'sense': 'surrender', 'word': 'сда́ться'},
          {'code': 'ru', 'sense': 'stop doing', 'word': 'броса́ть'},
          {'code': 'ru', 'sense': 'stop trying', 'word': 'сдаваться'},
          {
            'code': 'ru',
            'sense': 'surrender',
            'tags': ['rare'],
            'word': 'редкость',
          },
          {'code': 'de', 'sense': 'surrender', 'word': 'aufgeben'},
        ],
        'senses': [
          {
            'examples': [
              {'type': 'example', 'text': 'Never give up on your dreams.'},
              {'type': 'quotation', 'text': 'They never seem to give up.'},
            ],
          },
        ],
      });
      final parsed = parseDictionary(raw, 'give up');
      expect(parsed.translations, ['сдаваться', 'бросать', 'сдаться']);
      expect(parsed.examples, ['Never give up on your dreams.']);
    },
  );

  testWidgets('suggestions and definitions do not move the form controls', (
    tester,
  ) async {
    mockPlatform();
    final sources = _Suggestions();
    await tester.pumpWidget(_screen(sources));
    await tester.pump();
    final fields = find.byType(TextField);
    final save = find.text('Сохранить');
    List<Rect> layout() => [
      for (var index = 0; index < 3; index++) tester.getRect(fields.at(index)),
      tester.getRect(save),
    ];
    final initial = layout();
    await tester.enterText(fields.first, 'edibles');
    await tester.pump(const Duration(milliseconds: 320));
    expect(layout(), initial);

    sources.translations['edibles']!.complete(
      parseDictionary('''
{"word":"edibles","pos":"noun","lang_code":"en","senses":[{"glosses":["plural of edible"],"form_of":[{"word":"edible"}]}]}
''', 'edibles'),
    );
    sources.usages['edibles']!.complete(['They brought edibles to the party.']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(layout(), initial);

    sources.translations['edible']!.complete(
      const DictionarySuggestions(
        title: 'edible',
        meanings: [
          (partOfSpeech: 'adj', definition: 'Suitable for consumption.'),
          (partOfSpeech: 'noun', definition: 'Anything that is edible.'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(layout(), initial);
    expect(find.text('Основная форма «edible»'), findsOneWidget);
    expect(find.text('Anything that is edible.'), findsOneWidget);
    expect(find.text('Suitable for consumption.'), findsNothing);
  });

  testWidgets('saves a word, a phrasal verb and an idiom without leaving', (
    tester,
  ) async {
    final sources = _Suggestions();
    final saved = mockPlatform();
    await tester.pumpWidget(_screen(sources));
    await tester.pump();
    final field = find.byType(TextField).first;
    final save = find.text('Сохранить');
    final focus = tester.widget<TextField>(field).focusNode!;
    expect(focus.hasFocus, isTrue);

    for (final term in ['curiosity', 'give up', 'break the ice']) {
      await tester.enterText(field, term);
      await tester.pump(const Duration(milliseconds: 320));
      sources.translations[term]!.complete(
        DictionarySuggestions(
          title: term,
          translations: ['основной', 'другой'],
        ),
      );
      await tester.pump();
      expect(selectedTranslations(tester), ['основной']);
      const example = 'They wanted to give up early.';
      if (term == 'give up') {
        sources.usages[term]!.complete([example, 'Never give up on a dream.']);
        await tester.pump();
        await tester.tap(find.text('другой'));
        await tester.pump();
        expect(selectedTranslations(tester), ['другой']);
        await tester.tap(find.text(example));
        await tester.pump();
      } else if (term == 'break the ice') {
        const sentence = 'Someone has to break the ice.';
        sources.usages[term]!.complete([sentence]);
        await tester.pump();
        await tester.tap(find.widgetWithText(ChoiceChip, sentence));
        await tester.pump();
        await tester.tap(find.widgetWithText(ChoiceChip, sentence));
        await tester.pump();
      }
      await tester.tap(save);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(saved.last['english'], term);
      expect(saved.last['russian'], term == 'give up' ? 'другой' : 'основной');
      expect(saved.last['context'], term == 'give up' ? example : '');
    }
    sources.usages['curiosity']!.complete(['Curiosity brought him back here.']);
    await tester.pump();
    expect(find.text('Curiosity brought him back here.'), findsNothing);
    expect(saved, hasLength(3));
  });

  testWidgets('ignores stale lookup and preserves input on a duplicate', (
    tester,
  ) async {
    final sources = _Suggestions();
    final saved = mockPlatform(duplicate: true);
    await tester.pumpWidget(_screen(sources));
    await tester.pump();
    final field = find.byType(TextField);
    await tester.enterText(field.first, 'curiosity');
    await tester.pump(const Duration(milliseconds: 320));
    await tester.enterText(field.first, 'give up');
    await tester.pump(const Duration(milliseconds: 320));
    sources.translations['curiosity']!.complete(
      const DictionarySuggestions(
        title: 'curiosity',
        translations: ['любопытство'],
      ),
    );
    sources.translations['give up']!.completeError(StateError('Unavailable'));
    sources.usages['give up']!.completeError(StateError('Unavailable'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('любопытство'), findsNothing);
    expect(find.text('Перевод не загрузился'), findsOneWidget);
    expect(find.text('Примеры не загрузились'), findsOneWidget);
    await tester.enterText(field.at(1), 'сдаваться');
    await tester.pump();
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    expect(find.text('Такая карточка уже в словаре'), findsOneWidget);
    expect(tester.widget<TextField>(field.first).controller!.text, 'give up');
    expect(tester.widget<TextField>(field.at(1)).controller!.text, 'сдаваться');
    expect(saved.single['automatic'], isFalse);
  });

  testWidgets('editing retains the entry ID, translation credit and context', (
    tester,
  ) async {
    final saved = mockPlatform();
    final state = ReviewState(due: DateTime(2026));
    final entry = Entry(
      id: 42,
      english: 'compass',
      russian: 'компас',
      context: 'This compass still works.',
      automatic: true,
      forward: state,
      reverse: state,
    );
    await tester.pumpWidget(_screen(_Suggestions(), entry: entry));
    await tester.pump();
    expect(find.byType(TranslationCredit), findsOneWidget);
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(saved.single, containsPair('id', 42));
    expect(saved.single, containsPair('automatic', true));
    expect(saved.single, containsPair('context', 'This compass still works.'));
  });
}

List<String> selectedTranslations(WidgetTester tester) => tester
    .widgetList<ChoiceChip>(find.byType(ChoiceChip))
    .where((chip) => chip.selected)
    .map((chip) => (chip.label as Text).data!)
    .toList();

Widget _screen(_Suggestions sources, {Entry? entry}) => MaterialApp(
  theme: appTheme(),
  home: CardEditorScreen(
    platform: ThinkCapsPlatform(),
    sources: sources,
    entry: entry,
  ),
);

List<Map<Object?, Object?>> mockPlatform({bool duplicate = false}) {
  const channel = MethodChannel('app.thinkcaps/bridge');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final saved = <Map<Object?, Object?>>[];
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'translate') {
      throw PlatformException(code: 'TRANSLATION');
    }
    expect(call.method, 'saveEntry');
    saved.add(call.arguments as Map<Object?, Object?>);
    if (duplicate) throw PlatformException(code: 'DUPLICATE');
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return saved;
}

class _Suggestions extends SuggestionSources {
  final translations = <String, Completer<DictionarySuggestions>>{};
  final usages = <String, Completer<List<String>>>{};

  @override
  Future<DictionarySuggestions> dictionary(String term) =>
      translations.putIfAbsent(term, Completer.new).future;

  @override
  Future<List<String>> examples(String term) =>
      usages.putIfAbsent(term, Completer.new).future;
}
