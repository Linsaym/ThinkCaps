import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lexicon.dart';

typedef DictionarySuggestions = ({
  List<String> translations,
  List<String> examples,
  String title,
});

class SuggestionSources {
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  final _dictionary = <String, DictionarySuggestions>{};
  final _examples = <String, List<String>>{};

  void close() => _http.close(force: true);

  Future<DictionarySuggestions> dictionary(String term) async {
    final key = term.toLowerCase();
    final cached = _dictionary[key];
    if (cached != null) return cached;
    final prefix = key.length > 1 ? key.substring(0, 2) : key;
    final uri = Uri(
      scheme: 'https',
      host: 'kaikki.org',
      pathSegments: [
        'dictionary',
        'English',
        'meaning',
        key[0],
        prefix,
        '$key.jsonl',
      ],
    );
    final raw = await _read(uri);
    final result = parseDictionary(raw ?? '', term);
    _remember(_dictionary, key, result);
    return result;
  }

  Future<List<String>> examples(String term) async {
    final key = term.toLowerCase();
    final cached = _examples[key];
    if (cached != null) return cached;
    final raw = await _read(
      Uri.https('api.tatoeba.org', '/v1/sentences', {
        'lang': 'eng',
        'q': '"$key"',
        'sort': 'relevance',
        'limit': '18',
        'word_count': '4-20',
        'is_unapproved': 'no',
      }),
    );
    if (raw == null) throw const FormatException('Missing corpus response');
    final response = jsonDecode(raw) as Map<String, dynamic>;
    final match = RegExp(
      '(^|[^a-z])${RegExp.escape(key)}([^a-z]|\$)',
      caseSensitive: false,
    );
    final result = <String>{};
    for (final item in response['data'] as List<dynamic>) {
      final sentence = item['text'] as String;
      if (const {'CC BY 2.0 FR', 'CC0 1.0'}.contains(item['license']) &&
          match.hasMatch(normalizeTerm(sentence)) &&
          _usableExample(sentence)) {
        result.add(sentence);
      }
      if (result.length == 4) break;
    }
    final values = result.toList();
    _remember(_examples, key, values);
    return values;
  }

  Future<String?> _read(Uri uri) async {
    HttpClientRequest? request;
    var timedOut = false;
    Future<String?> fetch() async {
      final incoming = await _http.getUrl(uri);
      request = incoming;
      if (timedOut) {
        incoming.abort();
        return null;
      }
      incoming.headers.set(
        HttpHeaders.userAgentHeader,
        'ThinkCaps (https://github.com/Linsaym/ThinkCaps)',
      );
      final response = await incoming.close();
      if (response.statusCode == HttpStatus.notFound) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      return utf8.decoder.bind(response).join();
    }

    return fetch().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        timedOut = true;
        request?.abort();
        throw TimeoutException('Suggestions request timed out');
      },
    );
  }
}

void _remember<T>(Map<String, T> cache, String key, T value) {
  if (cache.length >= 32 && !cache.containsKey(key)) {
    cache.remove(cache.keys.first);
  }
  cache[key] = value;
}

final _russian = RegExp(r'[а-яё]', caseSensitive: false);
final _stress = RegExp('[\u0300\u0301]');
const _rare = {
  'archaic',
  'dated',
  'dialectal',
  'historical',
  'obsolete',
  'rare',
};

DictionarySuggestions parseDictionary(String raw, String term) {
  final title = <String>{};
  final primary = <String>{};
  final bySense = <(int, String), Set<String>>{};
  final examples = <String>{};
  var entryIndex = 0;
  for (final row in const LineSplitter().convert(raw)) {
    if (row.trim().isEmpty) continue;
    final entry = jsonDecode(row) as Map<String, dynamic>;
    final word = entry['word'] as String;
    if (entry['lang_code'] != 'en' ||
        word.toLowerCase() != term.toLowerCase()) {
      continue;
    }
    final senses = (entry['senses'] as List<dynamic>? ?? []).where(
      (sense) => !_marked(sense['tags']),
    );
    if (senses.isEmpty) continue;
    title.add(word);
    entryIndex++;
    final translations = entry['translations'] as List<dynamic>? ?? [];
    var first = true;
    for (final option in translations) {
      if (option['code'] != 'ru' || _marked(option['tags'])) continue;
      final value = (option['word'] as String?)?.replaceAll(_stress, '').trim();
      if (value == null ||
          value.length > 100 ||
          !_russian.hasMatch(value) ||
          RegExp(r'[A-Za-z]').hasMatch(value)) {
        continue;
      }
      final sense = option['sense'] as String? ?? '';
      (bySense[(entryIndex, sense)] ??= {}).add(value);
      if (first) {
        primary.add(value);
        first = false;
      }
    }
    for (final sense in senses) {
      final usages = sense['examples'] as List<dynamic>? ?? [];
      for (final usage in usages) {
        final value = usage['text'] as String?;
        if (usage['type'] == 'example' &&
            usage['ref'] == null &&
            value != null &&
            _usableExample(value)) {
          examples.add(value);
        }
      }
    }
  }
  final ranked = {
    ...primary,
    ...bySense.values.map((values) => values.first),
    ...bySense.values.expand((values) => values),
  };
  return (
    translations: ranked.take(5).toList(),
    examples: examples.take(4).toList(),
    title: title.firstOrNull ?? term,
  );
}

bool _marked(Object? tags) => tags is List && tags.any(_rare.contains);

bool _usableExample(String sentence) =>
    sentence.length <= 180 && sentence.trim().split(RegExp(r'\s+')).length >= 4;
