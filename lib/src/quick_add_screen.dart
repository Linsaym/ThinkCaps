import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'lexicon.dart';
import 'platform.dart';
import 'suggestions.dart';

class QuickAddScreen extends StatefulWidget {
  const QuickAddScreen({super.key, required this.platform, this.sources});

  final ThinkCapsPlatform platform;
  final SuggestionSources? sources;

  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  late final _sources = widget.sources ?? SuggestionSources();
  final _english = TextEditingController();
  final _russian = TextEditingController();
  final _englishFocus = FocusNode();
  final _russianFocus = FocusNode();
  Timer? _delay;
  int _revision = 0;
  String _term = '';
  DictionarySuggestions? _dictionary;
  List<String> _examples = [];
  String? _translation;
  String? _googleTranslation;
  String? _example;
  String? _saveStatus;
  bool _loadingTranslation = false;
  bool _loadingExamples = false;
  bool _translationFailed = false;
  bool _examplesFailed = false;
  bool _manual = false;
  bool _saving = false;

  @override
  void dispose() {
    _delay?.cancel();
    _sources.close();
    _english.dispose();
    _russian.dispose();
    _englishFocus.dispose();
    _russianFocus.dispose();
    super.dispose();
  }

  void _termChanged(String raw) {
    final term = normalizeTerm(raw);
    if (term == _term) return;
    _delay?.cancel();
    _revision++;
    _russian.clear();
    final valid = isEnglishTerm(term);
    setState(() {
      _term = term;
      _dictionary = null;
      _examples = [];
      _translation = null;
      _googleTranslation = null;
      _example = null;
      _saveStatus = null;
      _manual = false;
      _loadingTranslation = valid;
      _loadingExamples = valid;
      _translationFailed = false;
      _examplesFailed = false;
    });
    if (valid) {
      _delay = Timer(const Duration(milliseconds: 320), _lookup);
    }
  }

  void _lookup() {
    _delay?.cancel();
    _loadTranslations(_term, _revision);
    _loadExamples(_term, _revision);
  }

  Future<void> _loadTranslations(String term, int revision) async {
    setState(() {
      _translationFailed = false;
      _loadingTranslation = true;
    });
    DictionarySuggestions? data;
    try {
      data = await _sources.dictionary(term);
    } catch (_) {
      // ML Kit can still provide a translation when the dictionary is unavailable.
    }
    if (!mounted || revision != _revision) return;
    final first = data?.translations.firstOrNull;
    setState(() {
      _dictionary = data;
      _appendExamples(data?.examples ?? []);
      if (first != null) {
        _translation = first;
        _loadingTranslation = false;
      }
    });
    if (first != null) return;
    try {
      final translation = await widget.platform.translate(term);
      if (translation.toLowerCase() == term.toLowerCase()) {
        throw StateError('Translation matches the term');
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        _googleTranslation = translation;
        _translation = translation;
        _loadingTranslation = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _loadingTranslation = false;
        _translationFailed = true;
      });
    }
  }

  Future<void> _loadExamples(String term, int revision) async {
    setState(() {
      _examplesFailed = false;
      _loadingExamples = true;
    });
    try {
      final values = await _sources.examples(term);
      if (!mounted || revision != _revision) return;
      setState(() {
        _appendExamples(values);
        _loadingExamples = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _examplesFailed = true;
        _loadingExamples = false;
      });
    }
  }

  void _appendExamples(List<String> values) {
    _examples = {..._examples, ...values}.take(4).toList();
  }

  String get _selectedTranslation =>
      _manual ? _russian.text.trim() : _translation ?? '';

  bool get _canSave =>
      !_saving && isEnglishTerm(_term) && _selectedTranslation.isNotEmpty;

  Future<void> _save() async {
    if (!_canSave) return;
    final revision = _revision;
    final translation = _selectedTranslation;
    setState(() {
      _saving = true;
      _saveStatus = null;
    });
    try {
      await widget.platform.save(
        english: _term,
        russian: translation,
        context: _example ?? '',
        automatic: !_manual && translation == _googleTranslation,
      );
      if (!mounted) return;
      if (revision == _revision) {
        _english.clear();
        _termChanged('');
        _englishFocus.requestFocus();
        setState(() => _saveStatus = 'Карточка сохранена');
      }
    } on PlatformException catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _saveStatus = error.code == 'DUPLICATE'
            ? 'Такая карточка уже в словаре'
            : 'Не удалось сохранить. Попробуйте ещё раз';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _submitTerm() {
    if (_canSave) {
      _save();
    } else if (_delay?.isActive == true) {
      _lookup();
    }
  }

  void _toggleManual() {
    if (_manual) {
      setState(() => _manual = false);
      _englishFocus.requestFocus();
    } else {
      _russian.text = _translation ?? '';
      setState(() => _manual = true);
      _russianFocus.requestFocus();
    }
  }

  void _showSources() {
    final article = _dictionary?.title;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Источники подсказок'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Английский Викисловарь и его авторы, CC BY-SA 4.0. '
            'Варианты извлечены Wiktextract, отобраны и упорядочены в ThinkCaps.\n'
            '${Uri.https('en.wiktionary.org', article == null ? '/' : '/wiki/${article.replaceAll(' ', '_')}')}\n'
            'https://kaikki.org/dictionary/English/\n'
            'https://creativecommons.org/licenses/by-sa/4.0/\n\n'
            'Примеры также загружаются из Tatoeba (CC BY 2.0 FR и CC0 1.0).\n'
            'https://tatoeba.org\n'
            'https://creativecommons.org/licenses/by/2.0/fr/\n\n'
            'Для поиска введённое слово или фраза отправляется этим сервисам.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final valid = isEnglishTerm(_term);
    final translations = _googleTranslation == null
        ? _dictionary?.translations ?? <String>[]
        : [_googleTranslation!];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ink,
        scrolledUnderElevation: 0,
        title: const Text('Быстрое добавление', style: subheading),
        actions: [
          IconButton(
            tooltip: 'Источники подсказок',
            onPressed: _showSources,
            icon: const Icon(Icons.info_outline_rounded, color: muted),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                    children: [
                      TextField(
                        controller: _english,
                        focusNode: _englishFocus,
                        autofocus: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [LengthLimitingTextInputFormatter(80)],
                        onChanged: _termChanged,
                        onEditingComplete: _submitTerm,
                        decoration: InputDecoration(
                          labelText: 'Слово или фраза',
                          hintText: 'Например, give up',
                          errorText: _term.isNotEmpty && !valid
                              ? 'Введите слово или фразу на английском'
                              : null,
                          suffixIcon: _english.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Очистить поле',
                                  onPressed: () {
                                    _english.clear();
                                    _termChanged('');
                                    _englishFocus.requestFocus();
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                      if (valid) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Text('Перевод', style: subheading),
                            ),
                            TextButton(
                              onPressed: _saving ? null : _toggleManual,
                              child: Text(_manual ? 'Подсказки' : 'Вручную'),
                            ),
                          ],
                        ),
                        if (_manual)
                          TextField(
                            controller: _russian,
                            focusNode: _russianFocus,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(200),
                            ],
                            textInputAction: TextInputAction.done,
                            onEditingComplete: _save,
                            onChanged: (_) =>
                                setState(() => _saveStatus = null),
                            decoration: const InputDecoration(
                              hintText: 'Введите перевод',
                            ),
                          )
                        else if (translations.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final option in translations)
                                ChoiceChip(
                                  label: Text(option),
                                  selected: option == _translation,
                                  selectedColor: mint,
                                  checkmarkColor: ink,
                                  labelStyle: TextStyle(
                                    color: option == _translation ? ink : text,
                                  ),
                                  onSelected: _saving
                                      ? null
                                      : (_) {
                                          setState(() {
                                            _translation = option;
                                            _saveStatus = null;
                                          });
                                        },
                                ),
                            ],
                          ),
                          if (_googleTranslation != null)
                            const TranslationCredit(),
                        ] else if (_translationFailed)
                          _LookupStatus(
                            'Не удалось загрузить перевод',
                            retry: () => _loadTranslations(_term, _revision),
                          )
                        else if (_loadingTranslation)
                          const _LookupStatus('Ищем перевод…', loading: true),
                        const SizedBox(height: 14),
                        Text(
                          'Пример по желанию',
                          style: subheading.copyWith(fontSize: 16),
                        ),
                        if (_examples.isNotEmpty)
                          RadioGroup<String>(
                            groupValue: _example,
                            onChanged: (value) => setState(() {
                              _example = value;
                              _saveStatus = null;
                            }),
                            child: Column(
                              children: [
                                for (final option in _examples)
                                  RadioListTile<String>(
                                    value: option,
                                    toggleable: true,
                                    enabled: !_saving,
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: Text(option),
                                  ),
                              ],
                            ),
                          )
                        else if (_examplesFailed)
                          _LookupStatus(
                            'Примеры не загрузились',
                            retry: () => _loadExamples(_term, _revision),
                          )
                        else if (_loadingExamples || _loadingTranslation)
                          const _LookupStatus('Ищем примеры…', loading: true)
                        else
                          const _LookupStatus('Примеры не найдены'),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_saveStatus != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_saveStatus!, style: body),
                          ),
                        ),
                      FilledButton(
                        onPressed: _canSave ? _save : null,
                        child: Text(_saving ? 'Сохраняем…' : 'Сохранить'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LookupStatus extends StatelessWidget {
  const _LookupStatus(this.message, {this.loading = false, this.retry});

  final String message;
  final bool loading;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (loading) ...[
        const SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
      ],
      Expanded(child: Text(message, style: body)),
      if (retry != null)
        TextButton(onPressed: retry, child: const Text('Повторить')),
    ],
  );
}
