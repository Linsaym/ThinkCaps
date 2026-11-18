import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'design.dart';
import 'lexicon.dart';

class ImportScreen extends StatelessWidget {
  const ImportScreen({
    super.key,
    required this.sentences,
    required this.source,
    required this.scanning,
    required this.onScan,
    required this.onText,
    required this.onWord,
    required this.onClear,
  });
  final List<String> sentences;
  final String source;
  final bool scanning;
  final VoidCallback onScan;
  final VoidCallback onText;
  final void Function(String word, String sentence) onWord;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListView.builder(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(24, 19, 24, 28),
    itemCount: sentences.length + 1,
    itemBuilder: (context, index) {
      if (index == 0) return _header();
      final sentence = sentences[index - 1];
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _SentenceCard(
          sentence: sentence,
          onWord: (word) => onWord(word, sentence),
        ),
      );
    },
  );

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Импорт', style: heading),
      const SizedBox(height: 9),
      const Text(
        'Коснитесь слова в тексте, чтобы узнать перевод и сохранить его с контекстом.',
        style: body,
      ),
      const SizedBox(height: 23),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ImportAction(
              icon: Icons.document_scanner_outlined,
              title: 'Скриншот',
              busy: scanning,
              onTap: scanning ? null : onScan,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ImportAction(
              icon: Icons.content_paste_rounded,
              title: 'Вставить текст',
              onTap: onText,
            ),
          ),
        ],
      ),
      const SizedBox(height: 26),
      if (sentences.isEmpty)
        const Panel(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.ios_share_rounded, color: muted, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Можно также отправить текст через меню Android «Поделиться».',
                  style: body,
                ),
              ),
            ],
          ),
        )
      else ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(source, style: subheading)),
            IconButton(
              tooltip: 'Очистить импорт',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, color: muted),
            ),
          ],
        ),
        const SizedBox(height: 7),
      ],
    ],
  );
}

class _ImportAction extends StatelessWidget {
  const _ImportAction({
    required this.icon,
    required this.title,
    this.onTap,
    this.busy = false,
  });
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: line),
      borderRadius: BorderRadius.circular(20),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: mintSurface,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: mint, size: 20),
            ),
            const SizedBox(height: 13),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SentenceCard extends StatefulWidget {
  const _SentenceCard({required this.sentence, required this.onWord});
  final String sentence;
  final ValueChanged<String> onWord;

  @override
  State<_SentenceCard> createState() => _SentenceCardState();
}

class _SentenceCardState extends State<_SentenceCard> {
  final _links = <TapGestureRecognizer>[];
  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _buildSpans();
  }

  @override
  void didUpdateWidget(_SentenceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sentence != widget.sentence) _buildSpans();
  }

  void _clearLinks() {
    for (final link in _links) {
      link.dispose();
    }
    _links.clear();
  }

  void _buildSpans() {
    _clearLinks();
    _spans = [];
    var offset = 0;
    for (final match in englishWord.allMatches(widget.sentence)) {
      final word = match[0]!;
      if (match.start > offset) {
        _spans.add(
          TextSpan(text: widget.sentence.substring(offset, match.start)),
        );
      }
      final tap = TapGestureRecognizer()..onTap = () => widget.onWord(word);
      _links.add(tap);
      _spans.add(
        TextSpan(
          text: word,
          recognizer: tap,
          style: const TextStyle(
            color: mint,
            decoration: TextDecoration.underline,
            decorationColor: Color(0x556EE7B7),
            decorationThickness: 1.2,
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < widget.sentence.length) {
      _spans.add(TextSpan(text: widget.sentence.substring(offset)));
    }
  }

  @override
  void dispose() {
    _clearLinks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
    radius: 18,
    child: Text.rich(
      TextSpan(children: _spans),
      style: const TextStyle(
        fontSize: 17,
        height: 1.75,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

Future<String?> showTextImport(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: surface,
      constraints: const BoxConstraints(maxWidth: 540),
      builder: (_) => const _TextImportSheet(),
    );

class _TextImportSheet extends StatefulWidget {
  const _TextImportSheet();

  @override
  State<_TextImportSheet> createState() => _TextImportSheetState();
}

class _TextImportSheetState extends State<_TextImportSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Вставить текст', style: subheading),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 7,
              maxLength: 20000,
              decoration: const InputDecoration(
                hintText: 'Английский текст',
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, _controller.text),
              child: const Text('Открыть текст'),
            ),
          ],
        ),
      ),
    ),
  );
}
