import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/collection.dart';
import 'src/design.dart';
import 'src/editor.dart';
import 'src/import_screen.dart';
import 'src/lexicon.dart';
import 'src/platform.dart';
import 'src/review_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ink,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const ThinkCapsApp());
}

class ThinkCapsApp extends StatelessWidget {
  const ThinkCapsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ThinkCaps',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const _Home(),
  );
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with WidgetsBindingObserver {
  final _platform = ThinkCapsPlatform();
  List<Entry>? _entries;
  List<String> _sentences = [];
  String _source = '';
  int _tab = 0;
  bool _scanning = false;
  bool _loadFailed = false;
  int _importRevision = 0;
  Timer? _dueTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platform.onSharedText(_receiveSharedText);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _receiveSharedText());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dueTimer?.cancel();
    _platform.onSharedText(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() {});
      _scheduleRefresh();
      _receiveSharedText();
    }
  }

  void _scheduleRefresh() {
    _dueTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    var next = tomorrow;
    for (final entry in _entries ?? <Entry>[]) {
      for (final direction in Direction.values) {
        final due = entry.state(direction).due;
        if (due.isAfter(now) && due.isBefore(next)) next = due;
      }
    }
    _dueTimer = Timer(next.difference(now), () {
      if (mounted) setState(() {});
      _scheduleRefresh();
    });
  }

  Future<void> _load() async {
    try {
      final entries = await _platform.loadEntries();
      if (!mounted) return;
      setState(() {
        _loadFailed = false;
        _entries = entries;
      });
      _scheduleRefresh();
    } on PlatformException {
      if (!mounted) return;
      setState(() => _loadFailed = true);
      if (_entries != null) {
        notifyUser(context, 'Не удалось обновить словарь.');
      }
    }
  }

  void _selectTab(int value) {
    FocusScope.of(context).unfocus();
    setState(() => _tab = value);
  }

  Future<void> _openEditor({
    Entry? entry,
    String word = '',
    String sentence = '',
  }) async {
    if (_entries == null) return;
    final changed = await showWordEditor(
      context,
      _platform,
      entry: entry,
      word: word,
      sentence: sentence,
    );
    if (!mounted) return;
    await _load();
    if (changed && mounted && !_loadFailed && entry == null) {
      notifyUser(context, 'Карточка добавлена в словарь');
    }
  }

  Future<void> _startReview() async {
    final queue = dueCards(_entries ?? [], DateTime.now());
    if (queue.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(queue: queue, onGrade: _platform.grade),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _receiveSharedText() async {
    if (!mounted) return;
    try {
      final shares = await _platform.drainShares();
      if (shares.isEmpty || !mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _setImport(shares.join('\n\n'), 'Текст из другого приложения');
    } on PlatformException {
      if (mounted) {
        notifyUser(context, 'Не удалось открыть отправленный текст.');
      }
    }
  }

  void _setImport(String raw, String source) {
    final sentences = extractSentences(raw);
    if (sentences.isEmpty) {
      _selectTab(2);
      notifyUser(context, 'Английский текст не найден.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _importRevision++;
      _sentences = sentences;
      _source = source;
      _tab = 2;
    });
  }

  Future<void> _scan() async {
    if (_scanning) return;
    final revision = _importRevision;
    setState(() => _scanning = true);
    try {
      final result = await _platform.scanScreenshot();
      if (mounted && result != null && revision == _importRevision) {
        _setImport(result, 'Текст со скриншота');
      }
    } on PlatformException {
      if (mounted) {
        notifyUser(
          context,
          'Не удалось распознать изображение. Попробуйте другой скриншот.',
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _paste() async {
    final value = await showTextImport(context);
    if (mounted && value != null) _setImport(value, 'Вставленный текст');
  }

  void _clearImport() {
    setState(() {
      _importRevision++;
      _sentences = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final now = DateTime.now();
    final due = dueCards(entries ?? [], now);
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _tab != 0) _selectTab(0);
      },
      child: Scaffold(
        bottomNavigationBar: entries == null
            ? null
            : _BottomBar(selected: _tab, onSelected: _selectTab),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 22, 8),
                    child: SizedBox(
                      height: 43,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Wordmark(),
                          if (entries != null &&
                              (_tab == 1 || (_tab == 0 && due.isNotEmpty)))
                            IconButton(
                              onPressed: _openEditor,
                              tooltip: 'Добавить слово',
                              icon: const Icon(Icons.add_rounded, size: 23),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: line),
                                ),
                                foregroundColor: mint,
                                backgroundColor: surface,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: entries == null
                        ? Center(
                            child: _loadFailed
                                ? Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: EmptyState(
                                      icon: Icons.sync_problem_rounded,
                                      title: 'Словарь не открылся',
                                      detail:
                                          'Попробуйте загрузить его ещё раз.',
                                      action: OutlinedButton(
                                        onPressed: _load,
                                        child: const Text('Загрузить'),
                                      ),
                                    ),
                                  )
                                : const CircularProgressIndicator(),
                          )
                        : IndexedStack(
                            index: _tab,
                            children: [
                              TodayScreen(
                                entries: entries,
                                due: due,
                                now: now,
                                onAdd: _openEditor,
                                onReview: _startReview,
                                onDictionary: () => _selectTab(1),
                                onImport: () => _selectTab(2),
                                onEntry: (entry) => _openEditor(entry: entry),
                              ),
                              DictionaryScreen(
                                entries: entries,
                                now: now,
                                onAdd: _openEditor,
                                onEntry: (entry) => _openEditor(entry: entry),
                              ),
                              ImportScreen(
                                key: ValueKey(_importRevision),
                                sentences: _sentences,
                                source: _source,
                                scanning: _scanning,
                                onScan: _scan,
                                onText: _paste,
                                onClear: _clearImport,
                                onWord: (word, sentence) =>
                                    _openEditor(word: word, sentence: sentence),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  static const _destinations = [
    (Icons.today_outlined, 'Сегодня'),
    (Icons.style_outlined, 'Словарь'),
    (Icons.document_scanner_outlined, 'Импорт'),
  ];

  @override
  Widget build(BuildContext context) => Material(
    color: ink,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: line)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 5, 12, 3),
              child: Row(
                children: [
                  for (final (index, (icon, title)) in _destinations.indexed)
                    Expanded(
                      child: Semantics(
                        selected: index == selected,
                        button: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: () => onSelected(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 170),
                                  width: 46,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: index == selected
                                        ? mintSurface
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(
                                    icon,
                                    color: index == selected ? mint : muted,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: index == selected ? mint : muted,
                                    fontSize: 11,
                                    fontWeight: index == selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
