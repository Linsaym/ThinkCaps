import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'lexicon.dart';
import 'platform.dart';

Future<bool> showWordEditor(
  BuildContext context,
  ThinkCapsPlatform platform, {
  Entry? entry,
  String word = '',
  String sentence = '',
}) async {
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: surface,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 540),
        builder: (_) => _WordEditor(
          platform: platform,
          entry: entry,
          word: word,
          sentence: sentence,
        ),
      ) ??
      false;
}

class _WordEditor extends StatefulWidget {
  const _WordEditor({
    required this.platform,
    required this.entry,
    required this.word,
    required this.sentence,
  });
  final ThinkCapsPlatform platform;
  final Entry? entry;
  final String word;
  final String sentence;

  @override
  State<_WordEditor> createState() => _WordEditorState();
}

class _WordEditorState extends State<_WordEditor> {
  late final TextEditingController _english;
  late final TextEditingController _russian;
  late final TextEditingController _context;
  Timer? _delay;
  int _request = 0;
  bool _loading = false;
  bool _saving = false;
  bool _manual = false;
  bool _automatic = false;
  String? _translationError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _english = TextEditingController(
      text: widget.entry?.english ?? widget.word,
    );
    _russian = TextEditingController(text: widget.entry?.russian);
    _context = TextEditingController(
      text: widget.entry?.context ?? widget.sentence,
    );
    _automatic = widget.entry?.automatic ?? false;
    _manual = widget.entry != null;
    if (widget.entry == null && isEnglishTerm(widget.word)) {
      _delay = Timer(Duration.zero, _translate);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _english.dispose();
    _russian.dispose();
    _context.dispose();
    super.dispose();
  }

  void _termChanged(String value) {
    _delay?.cancel();
    _request++;
    setState(() {
      _loading = false;
      _saveError = null;
      _translationError = null;
      if (_automatic) {
        _russian.clear();
        _automatic = false;
        _manual = false;
      }
    });
    if (!_manual && isEnglishTerm(value)) {
      _delay = Timer(const Duration(milliseconds: 520), _translate);
    }
  }

  Future<void> _translate() async {
    _delay?.cancel();
    final word = normalizeTerm(_english.text);
    if (!isEnglishTerm(word)) return;
    final token = ++_request;
    setState(() {
      _loading = true;
      _translationError = null;
    });
    try {
      final translation = await widget.platform.translate(word);
      if (!mounted || token != _request) return;
      setState(() {
        _russian.text = translation;
        _automatic = true;
        _manual = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _request) return;
      setState(() {
        _loading = false;
        _translationError =
            'Перевод недоступен. Проверьте интернет или введите перевод вручную.';
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.platform.save(
        id: widget.entry?.id,
        english: _english.text,
        russian: _russian.text,
        context: _context.text,
        automatic: _automatic,
      );
      if (mounted) Navigator.pop(context, true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = error.code == 'DUPLICATE'
            ? 'Такая карточка уже в словаре.'
            : 'Не удалось сохранить карточку. Попробуйте ещё раз.';
      });
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить карточку?'),
        content: Text(
          '«${widget.entry!.english}» и её история повторений будут удалены.',
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
      await widget.platform.remove(widget.entry!.id);
      if (mounted) Navigator.pop(context, true);
    } on PlatformException {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Не удалось удалить карточку. Попробуйте ещё раз.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final validTerm = isEnglishTerm(_english.text);
    final canSave = validTerm && !_saving && _russian.text.trim().isNotEmpty;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.entry == null ? 'Новая карточка' : 'Карточка',
                      style: subheading.copyWith(fontSize: 26),
                    ),
                  ),
                  if (widget.entry != null)
                    IconButton(
                      tooltip: 'Удалить карточку',
                      onPressed: _saving ? null : _remove,
                      icon: const Icon(Icons.delete_outline, color: muted),
                    ),
                ],
              ),
              const SizedBox(height: 19),
              TextField(
                controller: _english,
                autofocus: widget.word.isEmpty && widget.entry == null,
                enabled: !_saving,
                inputFormatters: [LengthLimitingTextInputFormatter(80)],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                onChanged: _termChanged,
                decoration: InputDecoration(
                  labelText: 'Английский',
                  hintText: 'Например, curiosity',
                  errorText: _english.text.trim().isNotEmpty && !validTerm
                      ? 'Введите английское слово или фразу'
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _russian,
                enabled: !_saving,
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  _request++;
                  _delay?.cancel();
                  setState(() {
                    _automatic = false;
                    _manual = _russian.text.trim().isNotEmpty;
                    _loading = false;
                    _translationError = null;
                    _saveError = null;
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Русский',
                  hintText: _loading ? 'Перевожу…' : 'Перевод',
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(15),
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Перевести с Google Translate',
                          onPressed: validTerm && !_saving ? _translate : null,
                          icon: const Icon(Icons.translate_rounded, size: 21),
                        ),
                ),
              ),
              if (_loading || _automatic || _translationError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 2),
                  child: _translationError != null
                      ? Text(
                          _translationError!,
                          style: body.copyWith(fontSize: 12),
                        )
                      : _loading
                      ? Text(
                          'При первом переводе скачивается языковая модель.',
                          style: body.copyWith(fontSize: 12),
                        )
                      : const TranslationCredit(),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _context,
                enabled: !_saving,
                minLines: 1,
                maxLines: 3,
                inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                decoration: const InputDecoration(
                  labelText: 'Пример или контекст',
                ),
              ),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _saveError!,
                    style: body.copyWith(color: text, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: canSave ? _save : null,
                child: Text(_saving ? 'Сохраняю…' : 'Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
