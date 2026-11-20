import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'lexicon.dart';
import 'platform.dart';
import 'suggestions.dart';

class CardEditorScreen extends StatefulWidget {
  const CardEditorScreen({
    super.key,
    required this.platform,
    this.entry,
    this.word,
    this.sentence = '',
    this.sources,
  });

  final ThinkCapsPlatform platform;
  final Entry? entry;
  final String? word;
  final String sentence;
  final SuggestionSources? sources;

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  late final _sources = widget.sources ?? SuggestionSources();
  late final _english = TextEditingController(text: _term);
  late final _russian = TextEditingController(text: widget.entry?.russian);
  late final _context = TextEditingController(
    text: widget.entry?.context ?? widget.sentence,
  );
  final _englishFocus = FocusNode();
  final _scroll = ScrollController();
  Timer? _delay;
  int _lookupVersion = 0;
  int _draftVersion = 0;
  late String _term = normalizeTerm(widget.entry?.english ?? widget.word ?? '');
  late bool _automatic = widget.entry?.automatic ?? false;
  late bool _manualTranslation = widget.entry != null && !_automatic;
  DictionarySuggestions? _dictionary;
  DictionarySuggestions? _lemma;
  String? _googleTranslation;
  List<String> _examples = [];
  String? _pickedExample;
  String _previousContext = '';
  String? _saveStatus;
  bool _lookupStarted = false;
  bool _loadingDictionary = false;
  bool _loadingTranslation = false;
  bool _loadingExamples = false;
  bool _translationFailed = false;
  bool _examplesFailed = false;
  bool _saving = false;

  bool get _repeat => widget.entry == null && widget.word == null;
  bool get _valid => isEnglishTerm(_term);
  bool get _canSave => _valid && !_saving && _russian.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.entry == null && _valid) {
      _loadingDictionary = _loadingTranslation = _loadingExamples = true;
      _delay = Timer(Duration.zero, _lookup);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _sources.close();
    _english.dispose();
    _russian.dispose();
    _context.dispose();
    _englishFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _draftChanged() {
    _draftVersion++;
    _saveStatus = null;
  }

  void _termChanged(String input) {
    final term = normalizeTerm(input);
    if (term == _term) return;
    _delay?.cancel();
    _lookupVersion++;
    setState(() {
      _draftChanged();
      if (!_manualTranslation ||
          (_repeat && _term.isNotEmpty) ||
          _russian.text.isEmpty) {
        _russian.clear();
        _manualTranslation = false;
      }
      _term = term;
      if (_pickedExample != null) _context.text = _previousContext;
      _automatic = false;
      _pickedExample = null;
      _dictionary = _lemma = null;
      _googleTranslation = null;
      _examples = [];
      _lookupStarted = false;
      _loadingDictionary = _loadingTranslation = _loadingExamples = _valid;
      _translationFailed = _examplesFailed = false;
    });
    if (_valid) _delay = Timer(const Duration(milliseconds: 320), _lookup);
  }

  void _lookup() {
    _delay?.cancel();
    _lookupStarted = true;
    unawaited(_loadTranslations(_term, _lookupVersion));
    unawaited(_loadExamples(_term, _lookupVersion));
  }

  bool _current(int version) => mounted && version == _lookupVersion;

  Future<void> _loadTranslations(String term, int version) async {
    setState(() {
      _loadingTranslation = _loadingDictionary = true;
      _translationFailed = false;
    });
    DictionarySuggestions? data;
    try {
      data = await _sources.dictionary(term);
    } catch (_) {
      // The existing ML Kit translator can fill the field if the dictionary fails.
    }
    if (!_current(version)) return;
    final first = data?.translations.firstOrNull;
    setState(() {
      _dictionary = data;
      _loadingDictionary = false;
      _appendExamples(data?.examples ?? []);
      if (first != null) {
        _useDefaultTranslation(first, automatic: false);
        _loadingTranslation = false;
      }
    });
    if (data?.lemma case final lemma?) {
      unawaited(_loadMeaning(lemma, version));
    }
    if (first != null) return;
    try {
      final translation = await widget.platform.translate(term);
      if (translation.toLowerCase() == term.toLowerCase()) {
        throw StateError('Translation matches the term');
      }
      if (!_current(version)) return;
      setState(() {
        _googleTranslation = translation;
        _useDefaultTranslation(translation, automatic: true);
        _loadingTranslation = false;
      });
    } catch (_) {
      if (!_current(version)) return;
      setState(() {
        _loadingTranslation = false;
        _translationFailed = true;
      });
    }
  }

  Future<void> _loadMeaning(String lemma, int version) async {
    try {
      final data = await _sources.dictionary(lemma);
      if (!_current(version) || data.meanings.isEmpty) return;
      setState(() => _lemma = data);
    } catch (_) {
      // Keep the definition from the original entry if its base form fails.
    }
  }

  void _useDefaultTranslation(String translation, {required bool automatic}) {
    if (_manualTranslation || _russian.text.isNotEmpty) return;
    _russian.text = translation;
    _automatic = automatic;
  }

  Future<void> _loadExamples(String term, int version) async {
    setState(() {
      _examplesFailed = false;
      _loadingExamples = true;
    });
    try {
      final values = await _sources.examples(term);
      if (!_current(version)) return;
      setState(() {
        _appendExamples(values);
        _loadingExamples = false;
      });
    } catch (_) {
      if (!_current(version)) return;
      setState(() {
        _examplesFailed = true;
        _loadingExamples = false;
      });
    }
  }

  void _appendExamples(List<String> values) {
    _examples = {..._examples, ...values}.take(4).toList();
  }

  void _selectTranslation(String option) {
    setState(() {
      _draftChanged();
      _russian.text = option;
      _manualTranslation = false;
      _automatic = option == _googleTranslation;
    });
  }

  void _selectExample(String option) {
    setState(() {
      _draftChanged();
      if (_pickedExample == option) {
        _context.text = _previousContext;
        _pickedExample = null;
      } else {
        if (_pickedExample == null) _previousContext = _context.text;
        _context.text = option;
        _pickedExample = option;
      }
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final version = _draftVersion;
    setState(() {
      _saving = true;
      _saveStatus = null;
    });
    try {
      await widget.platform.save(
        id: widget.entry?.id,
        english: _term,
        russian: _russian.text,
        context: _context.text,
        automatic: _automatic,
      );
      if (!mounted) return;
      if (!_repeat) {
        Navigator.pop(context, true);
        return;
      }
      if (version == _draftVersion) {
        _english.clear();
        _russian.clear();
        _termChanged('');
        _context.clear();
        _manualTranslation = false;
        if (_scroll.hasClients) _scroll.jumpTo(0);
        _englishFocus.requestFocus();
      }
      setState(() => _saveStatus = 'Карточка сохранена');
    } on PlatformException catch (error) {
      if (!mounted || version != _draftVersion) return;
      setState(() {
        _saveStatus = error.code == 'DUPLICATE'
            ? 'Такая карточка уже в словаре'
            : 'Не удалось сохранить. Попробуйте ещё раз';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final entry = widget.entry!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить карточку?'),
        content: Text(
          '«${entry.english}» и её история повторений будут удалены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.platform.remove(entry.id);
      if (mounted) Navigator.pop(context, true);
    } on PlatformException {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveStatus = 'Не удалось удалить карточку';
        });
      }
    }
  }

  void _submitTerm() {
    if (_canSave) {
      unawaited(_save());
    } else if (_valid && (!_lookupStarted || _delay?.isActive == true)) {
      _lookup();
    }
  }

  void _showSources() {
    final articles = [?_dictionary?.title, ?_lemma?.title];
    final links = articles.isEmpty
        ? 'https://en.wiktionary.org/'
        : articles
              .map(
                (article) => Uri.https(
                  'en.wiktionary.org',
                  '/wiki/${article.replaceAll(' ', '_')}',
                ),
              )
              .join('\n');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Источники подсказок'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Переводы, определения и часть примеров взяты из Английского '
            'Викисловаря (CC BY-SA 4.0), извлечены Wiktextract и отобраны в ThinkCaps.\n'
            '$links\nhttps://kaikki.org/dictionary/English/\n'
            'https://creativecommons.org/licenses/by-sa/4.0/\n\n'
            'Другие примеры загружены из Tatoeba (CC BY 2.0 FR и CC0 1.0).\n'
            'https://tatoeba.org\nhttps://creativecommons.org/licenses/by/2.0/fr/\n\n'
            'Для поиска введённый термин отправляется этим сервисам.',
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

  Future<void> _chooseSuggestion({
    required String title,
    required List<String> options,
    required String? selected,
    required ValueChanged<String> onSelected,
  }) async {
    final version = _lookupVersion;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) =>
          _SuggestionSheet(title: title, options: options, selected: selected),
    );
    if (choice != null && _current(version) && !_saving) onSelected(choice);
  }

  Widget _translationSlot() {
    final options = _googleTranslation == null
        ? _dictionary?.translations ?? <String>[]
        : [_googleTranslation!];
    final selected = _russian.text.trim();
    final alternative = options
        .where((option) => option != selected)
        .firstOrNull;
    final Widget content;
    if (alternative != null) {
      content = LayoutBuilder(
        key: const ValueKey('translations'),
        builder: (context, size) {
          const optionStyle = TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          );
          const allLabel = 'Все варианты';
          final allWidth = options.length > 1
              ? _labelWidth(
                      context,
                      allLabel,
                      Theme.of(context).textTheme.labelLarge!,
                    ) +
                    56
              : 0;
          final showShortcut =
              _labelWidth(context, alternative, optionStyle) + 22 + allWidth <=
              size.maxWidth;
          return Row(
            children: [
              if (showShortcut)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: ink,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    textStyle: optionStyle,
                  ),
                  onPressed: _saving
                      ? null
                      : () => _selectTranslation(alternative),
                  child: Text(alternative),
                ),
              if (options.length > 1 || !showShortcut)
                Flexible(
                  child: TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _chooseSuggestion(
                            title: 'Варианты перевода',
                            options: options,
                            selected: selected,
                            onSelected: _selectTranslation,
                          ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.expand_more_rounded, size: 17),
                    label: Text(
                      options.length > 1 ? allLabel : 'Вариант перевода',
                    ),
                  ),
                ),
            ],
          );
        },
      );
    } else if (_loadingTranslation) {
      content = _LookupStatus('Ищем перевод…', loading: true);
    } else if (_translationFailed) {
      content = _LookupStatus(
        'Перевод не загрузился',
        retry: () => _loadTranslations(_term, _lookupVersion),
      );
    } else if (_valid && !_lookupStarted && widget.entry != null) {
      content = Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _saving ? null : _lookup,
          child: const Text('Найти подсказки'),
        ),
      );
    } else {
      content = const SizedBox.shrink();
    }
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 10 + MediaQuery.textScalerOf(context).scale(38),
            child: _FadeContent(child: content),
          ),
        ),
        if (_automatic || _googleTranslation != null) const TranslationCredit(),
      ],
    );
  }

  Widget _wordPanel() => Panel(
    radius: 22,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Английский', style: _fieldLabel),
        Semantics(
          label: 'Слово или фраза',
          child: TextField(
            controller: _english,
            focusNode: _englishFocus,
            autofocus: _repeat,
            textInputAction: TextInputAction.done,
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            onChanged: _termChanged,
            onEditingComplete: _submitTerm,
            style: const TextStyle(
              fontSize: 26,
              height: 1.25,
              letterSpacing: -.7,
              fontWeight: FontWeight.w800,
            ),
            decoration: _fieldDecoration('Слово или фраза').copyWith(
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _english,
                builder: (_, value, _) => Visibility(
                  visible: value.text.isNotEmpty,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IconButton(
                    tooltip: 'Очистить поле',
                    onPressed: () {
                      _english.clear();
                      _termChanged('');
                      _englishFocus.requestFocus();
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: _englishFocus,
          builder: (_, _) => Divider(
            height: 18,
            thickness: 1,
            color: _englishFocus.hasFocus ? Colors.transparent : line,
          ),
        ),
        const Text('Перевод', style: _fieldLabel),
        Semantics(
          label: 'Перевод',
          child: TextField(
            controller: _russian,
            inputFormatters: [LengthLimitingTextInputFormatter(200)],
            textInputAction: TextInputAction.done,
            onEditingComplete: _save,
            onChanged: (_) => setState(() {
              _draftChanged();
              _manualTranslation = true;
              _automatic = false;
            }),
            style: const TextStyle(
              fontSize: 19,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
            decoration: _fieldDecoration('Введите перевод'),
          ),
        ),
        _translationSlot(),
      ],
    ),
  );

  Widget _exampleAction() {
    if (_examples.isNotEmpty) {
      return Align(
        key: const ValueKey('examples'),
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _saving
              ? null
              : () => _chooseSuggestion(
                  title: 'Примеры употребления',
                  options: _examples,
                  selected: _pickedExample,
                  onSelected: _selectExample,
                ),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.expand_more_rounded, size: 17),
          label: const Text('Примеры'),
        ),
      );
    }
    if (_loadingExamples || _loadingDictionary) {
      return const Align(
        key: ValueKey('examples-loading'),
        alignment: Alignment.centerRight,
        child: SizedBox.square(
          dimension: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            semanticsLabel: 'Ищем примеры',
          ),
        ),
      );
    }
    if (_examplesFailed) {
      return Align(
        key: const ValueKey('examples-retry'),
        alignment: Alignment.centerRight,
        child: Tooltip(
          message: 'Примеры не загрузились',
          child: TextButton.icon(
            onPressed: () => _loadExamples(_term, _lookupVersion),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Повторить'),
          ),
        ),
      );
    }
    if (_lookupStarted) {
      return const Align(
        key: ValueKey('examples-empty'),
        alignment: Alignment.centerRight,
        child: Text('Нет примеров', style: _fieldLabel),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _contextPanel() => Panel(
    color: ink,
    radius: 20,
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 16 + MediaQuery.textScalerOf(context).scale(32),
          child: Row(
            children: [
              const Text('Контекст', style: _fieldLabel),
              const SizedBox(width: 8),
              Expanded(child: _FadeContent(child: _exampleAction())),
            ],
          ),
        ),
        Semantics(
          label: 'Пример или контекст',
          child: TextField(
            controller: _context,
            minLines: 2,
            maxLines: 2,
            keyboardType: TextInputType.multiline,
            inputFormatters: [LengthLimitingTextInputFormatter(1000)],
            onChanged: (_) => setState(() {
              _draftChanged();
              _pickedExample = null;
            }),
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
            decoration: _fieldDecoration('Предложение по желанию'),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final status = _term.isNotEmpty && !_valid
        ? 'Введите термин на английском'
        : _saveStatus;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ink,
        scrolledUnderElevation: 0,
        title: LayoutBuilder(
          builder: (context, size) {
            final title = _repeat
                ? 'Быстрое добавление'
                : widget.entry == null
                ? 'Новая карточка'
                : 'Карточка';
            final compact =
                _repeat &&
                _labelWidth(context, title, subheading) > size.maxWidth;
            return Text(compact ? 'Добавление' : title, style: subheading);
          },
        ),
        actions: [
          if (widget.entry != null)
            IconButton(
              tooltip: 'Удалить карточку',
              onPressed: _saving ? null : _remove,
              icon: const Icon(Icons.delete_outline, color: muted),
            ),
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
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
                    children: [
                      _wordPanel(),
                      const SizedBox(height: 18),
                      _contextPanel(),
                      AnimatedSize(
                        duration: _editorMotion(context),
                        alignment: Alignment.topCenter,
                        child: _MeaningPanel(
                          key: ValueKey(_term),
                          dictionary: _dictionary,
                          lemma: _lemma,
                        ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: ink,
                    border: Border(top: BorderSide(color: line)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSize(
                          duration: _editorMotion(context),
                          alignment: Alignment.bottomCenter,
                          child: status == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      status,
                                      style: body.copyWith(fontSize: 13),
                                    ),
                                  ),
                                ),
                        ),
                        FilledButton(
                          onPressed: _canSave ? _save : null,
                          child: Text(_saving ? 'Сохраняем…' : 'Сохранить'),
                        ),
                      ],
                    ),
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

const _fieldLabel = TextStyle(
  color: muted,
  fontSize: 13,
  fontWeight: FontWeight.w700,
  height: 1.35,
);

InputDecoration _fieldDecoration(String hint) => InputDecoration(
  hintText: hint,
  isDense: true,
  filled: false,
  contentPadding: const EdgeInsets.symmetric(vertical: 7),
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: mint),
  ),
);

Duration _editorMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 180);

double _labelWidth(BuildContext context, String value, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

class _FadeContent extends StatelessWidget {
  const _FadeContent({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: _editorMotion(context),
    layoutBuilder: (current, previous) => Stack(
      fit: StackFit.expand,
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.hardEdge,
      children: [
        for (final old in previous)
          Positioned.fill(
            child: IgnorePointer(child: ExcludeSemantics(child: old)),
          ),
        ?current,
      ],
    ),
    child: child,
  );
}

class _SuggestionSheet extends StatelessWidget {
  const _SuggestionSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  final String title;
  final List<String> options;
  final String? selected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .62,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(title, style: subheading),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: options.length,
              separatorBuilder: (_, _) => const Divider(
                height: 1,
                indent: 12,
                endIndent: 12,
                color: line,
              ),
              itemBuilder: (context, index) {
                final option = options[index];
                final active = option == selected;
                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selected: active,
                  selectedTileColor: mintSurface,
                  title: Text(
                    option,
                    style: body.copyWith(color: active ? mint : text),
                  ),
                  trailing: active
                      ? const Icon(Icons.check_rounded, color: mint)
                      : null,
                  onTap: () => Navigator.pop(context, option),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _LookupStatus extends StatelessWidget {
  _LookupStatus(this.message, {this.loading = false, this.retry})
    : super(key: ValueKey(message));
  final String message;
  final bool loading;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (loading) ...[
        const SizedBox.square(
          dimension: 13,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: Text(
          message,
          style: body.copyWith(fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (retry != null)
        TextButton(onPressed: retry, child: const Text('Повторить')),
    ],
  );
}

class _MeaningPanel extends StatefulWidget {
  const _MeaningPanel({
    super.key,
    required this.dictionary,
    required this.lemma,
  });
  final DictionarySuggestions? dictionary;
  final DictionarySuggestions? lemma;

  @override
  State<_MeaningPanel> createState() => _MeaningPanelState();
}

class _MeaningPanelState extends State<_MeaningPanel> {
  bool _expanded = false;

  String _partOfSpeech(String code) => switch (code) {
    'noun' => 'Существительное',
    'verb' => 'Глагол',
    'adj' => 'Прилагательное',
    'adv' => 'Наречие',
    'prep' => 'Предлог',
    'phrase' => 'Выражение',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final entry = widget.dictionary;
    if (entry == null) return const SizedBox.shrink();
    final lemma = widget.lemma;
    final parts = entry.meanings.map((meaning) => meaning.partOfSpeech).toSet();
    final baseMeanings = lemma?.meanings ?? [];
    final matching = baseMeanings.where(
      (meaning) => parts.contains(meaning.partOfSpeech),
    );
    final meanings = [
      ...entry.meanings,
      ...(matching.isEmpty ? baseMeanings : matching),
    ].take(4).toList();
    if (meanings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Panel(
        color: mintSurface,
        border: mint.withValues(alpha: .16),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Значение · «${entry.title}»',
              style: subheading.copyWith(fontSize: 17, color: mint),
            ),
            if (lemma != null)
              Text(
                'Основная форма «${lemma.title}»',
                style: body.copyWith(fontSize: 13),
              ),
            for (final (index, meaning)
                in (_expanded ? meanings : meanings.take(2)).indexed) ...[
              const SizedBox(height: 10),
              if (_partOfSpeech(meaning.partOfSpeech).isNotEmpty &&
                  (index == 0 ||
                      meanings[index - 1].partOfSpeech != meaning.partOfSpeech))
                Text(
                  _partOfSpeech(meaning.partOfSpeech),
                  style: body.copyWith(fontSize: 12),
                ),
              Text(meaning.definition, style: body.copyWith(color: text)),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Английский Викисловарь',
                  style: body.copyWith(fontSize: 12),
                ),
                if (meanings.length > 2)
                  TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    iconAlignment: IconAlignment.end,
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 17,
                    ),
                    label: Text(_expanded ? 'Свернуть' : 'Все значения'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
