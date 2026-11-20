import 'package:flutter/material.dart';

import 'design.dart';
import 'lexicon.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.entries,
    required this.due,
    required this.now,
    required this.nextReview,
    required this.onAdd,
    required this.onReview,
    required this.onDictionary,
    required this.onImport,
    required this.onEntry,
  });
  final List<Entry> entries;
  final List<ReviewCard> due;
  final DateTime now;
  final DateTime? nextReview;
  final VoidCallback onAdd;
  final VoidCallback onReview;
  final VoidCallback onDictionary;
  final VoidCallback onImport;
  final ValueChanged<Entry> onEntry;

  String get _date {
    const weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}'
        .toUpperCase();
  }

  String _nextReviewLabel(BuildContext context) {
    final next = nextReview;
    if (next == null || !DateUtils.isSameDay(now, next)) {
      return 'На сегодня всё';
    }
    return 'Следующее в ${TimeOfDay.fromDateTime(next).format(context)}';
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 19, 24, 28),
    children: [
      Text(_date, style: label),
      const SizedBox(height: 8),
      const Text('Сегодня', style: heading),
      const SizedBox(height: 21),
      _ReviewPanel(
        count: due.length,
        hasEntries: entries.isNotEmpty,
        emptyLabel: due.isEmpty ? _nextReviewLabel(context) : '',
        onAdd: onAdd,
        onReview: onReview,
      ),
      const SizedBox(height: 23),
      if (entries.isNotEmpty) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(child: Text('Мой словарь', style: subheading)),
            TextButton(
              onPressed: onDictionary,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 9),
              ),
              child: Row(
                children: [
                  Text(
                    'Все · ${entries.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 17),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        EntryList(
          entries: entries.take(3).toList(),
          now: now,
          onEntry: onEntry,
        ),
      ] else
        Material(
          color: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: line),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: onImport,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 7,
            ),
            leading: const Icon(Icons.document_scanner_outlined, color: mint),
            title: const Text(
              'Импортировать слова',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('Из текста или скриншота', style: body),
            trailing: const Icon(Icons.chevron_right_rounded, color: muted),
          ),
        ),
    ],
  );
}

class _ReviewPanel extends StatelessWidget {
  const _ReviewPanel({
    required this.count,
    required this.hasEntries,
    required this.emptyLabel,
    required this.onAdd,
    required this.onReview,
  });
  final int count;
  final bool hasEntries;
  final String emptyLabel;
  final VoidCallback onAdd;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(19),
    color: const Color(0xFF161E1C),
    border: const Color(0xFF2B443A),
    radius: 25,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            if (MediaQuery.textScalerOf(context).scale(16) < 21)
              const Positioned(
                top: 0,
                right: 0,
                width: 137,
                height: 123,
                child: CardIllustration(),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 14),
              child: LayoutBuilder(
                builder: (context, size) {
                  final compact =
                      MediaQuery.textScalerOf(context).scale(16) >= 21;
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: compact ? size.maxWidth : size.maxWidth * .59,
                      minHeight: compact ? 0 : 119,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (hasEntries) ...[
                          Text(
                            'К ПОВТОРЕНИЮ',
                            style: label.copyWith(color: mint),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count',
                            style: heading.copyWith(
                              fontSize: 57,
                              height: 1.05,
                              letterSpacing: -3,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            count == 0
                                ? emptyLabel
                                : plural(
                                    count,
                                    'карточка',
                                    'карточки',
                                    'карточек',
                                  ),
                            style: body.copyWith(fontSize: 14),
                          ),
                        ] else ...[
                          const Text(
                            'Первая\nкарточка',
                            style: TextStyle(
                              fontSize: 26,
                              height: 1.12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.7,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Начните со слова, которое хотите запомнить.',
                            style: body.copyWith(fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (count > 0 || !hasEntries)
          FilledButton(
            onPressed: hasEntries ? onReview : onAdd,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasEntries ? 'Начать повторение' : 'Добавить карточку',
                  ),
                ),
                Icon(
                  hasEntries ? Icons.arrow_forward_rounded : Icons.add_rounded,
                  size: 21,
                ),
              ],
            ),
          ),
        if (count == 0 && hasEntries)
          OutlinedButton(
            onPressed: onAdd,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF3D574E)),
            ),
            child: const Text('Добавить карточку'),
          ),
      ],
    ),
  );
}

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({
    super.key,
    required this.entries,
    required this.now,
    required this.onAdd,
    required this.onEntry,
  });
  final List<Entry> entries;
  final DateTime now;
  final VoidCallback onAdd;
  final ValueChanged<Entry> onEntry;

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.entries
        : widget.entries
              .where(
                (entry) =>
                    entry.english.toLowerCase().contains(_query) ||
                    entry.russian.toLowerCase().contains(_query),
              )
              .toList();
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 19, 24, 14),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Словарь', style: heading),
                const SizedBox(height: 8),
                Text(
                  '${widget.entries.length} ${plural(widget.entries.length, 'карточка', 'карточки', 'карточек')}',
                  style: body,
                ),
                const SizedBox(height: 20),
                if (widget.entries.isNotEmpty)
                  TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Поиск по словарю',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: muted,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              tooltip: 'Очистить поиск',
                              icon: const Icon(
                                Icons.close_rounded,
                                color: muted,
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(
              child: EmptyState(
                icon: _query.isEmpty
                    ? Icons.style_outlined
                    : Icons.search_off_rounded,
                title: _query.isEmpty
                    ? 'Здесь будут ваши слова'
                    : 'Совпадений нет',
                detail: _query.isEmpty
                    ? 'Добавьте английское слово или выражение.'
                    : 'Попробуйте изменить запрос.',
                action: _query.isEmpty
                    ? OutlinedButton(
                        onPressed: widget.onAdd,
                        child: const Text('Добавить карточку'),
                      )
                    : null,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            sliver: SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => EntryList(
                entries: [filtered[index]],
                now: widget.now,
                onEntry: widget.onEntry,
              ),
            ),
          ),
      ],
    );
  }
}

class EntryList extends StatelessWidget {
  const EntryList({
    super.key,
    required this.entries,
    required this.now,
    required this.onEntry,
  });
  final List<Entry> entries;
  final DateTime now;
  final ValueChanged<Entry> onEntry;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: line),
      borderRadius: BorderRadius.circular(19),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, entry) in entries.indexed) ...[
          if (index != 0)
            const Divider(height: 1, indent: 15, endIndent: 15, color: line),
          InkWell(
            onTap: () => onEntry(entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.english,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.russian,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: body.copyWith(fontSize: 13),
                        ),
                        if (entry.automatic) const TranslationCredit(),
                      ],
                    ),
                  ),
                  if (entry.dueAt(now))
                    const Tooltip(
                      message: 'К повторению',
                      child: Icon(Icons.circle, size: 6, color: mint),
                    ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: muted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
