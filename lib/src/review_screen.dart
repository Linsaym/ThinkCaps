import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import 'design.dart';
import 'lexicon.dart';

final _wordSeparator = RegExp(r'\s+');

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.queue,
    required this.spacing,
    required this.onGrade,
    required this.onSpeak,
    required this.onStopSpeech,
    this.now = DateTime.now,
  });
  final List<ReviewCard> queue;
  final ReviewSpacing spacing;
  final Future<ReviewState> Function(ReviewCard, Grade) onGrade;
  final Future<void> Function(String) onSpeak;
  final Future<void> Function() onStopSpeech;
  final DateTime Function() now;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with TickerProviderStateMixin {
  late final _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 410),
  )..addStatusListener((_) => setState(() {}));
  late final _slide = AnimationController.unbounded(vsync: this);
  late final _pending = [...widget.queue];
  late final AppLifecycleListener _lifecycle;
  ReviewCard? _current;
  DateTime? _nextAttempt;
  Timer? _retryTimer;
  int _remembered = 0;
  bool _submitting = false;
  bool _speaking = false;

  bool get _revealComplete => _flip.isCompleted;

  @override
  void initState() {
    super.initState();
    _advance();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_nextAttempt != null) setState(_advance);
      },
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _lifecycle.dispose();
    _stopSpeech();
    _flip.dispose();
    _slide.dispose();
    super.dispose();
  }

  void _advance() {
    _retryTimer?.cancel();
    _current = null;
    _nextAttempt = null;
    final now = widget.now();
    DateTime? next;
    for (var i = 0; i < _pending.length; i++) {
      final available = widget.spacing.availableAt(_pending[i]);
      if (!available.isAfter(now)) {
        _current = _pending.removeAt(i);
        return;
      }
      if (next == null || available.isBefore(next)) next = available;
    }
    if (next != null) {
      _nextAttempt = next;
      _retryTimer = Timer(next.difference(now), () => setState(_advance));
    }
  }

  void _reveal() {
    final card = _current;
    if (card == null || _submitting || _flip.value > 0 || _flip.isAnimating) {
      return;
    }
    widget.spacing.recordExposure(card, widget.now());
    HapticFeedback.selectionClick();
    if (MediaQuery.disableAnimationsOf(context)) {
      _flip.value = 1;
    } else {
      _flip.forward();
    }
  }

  Future<void> _speak(String word) async {
    if (_speaking || _submitting || _flip.isAnimating) return;
    _speaking = true;
    try {
      await widget.onSpeak(word).timeout(const Duration(seconds: 15));
    } on PlatformException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'TTS_VOICE' => 'Установите английский голос в настройках Android.',
        'TTS_UNAVAILABLE' => 'Включите синтез речи в настройках Android.',
        _ => 'Не удалось озвучить слово. Попробуйте ещё раз.',
      };
      notifyUser(context, message);
    } on TimeoutException {
      _stopSpeech();
      if (mounted) {
        notifyUser(context, 'Озвучка не запустилась. Попробуйте ещё раз.');
      }
    } finally {
      _speaking = false;
    }
  }

  void _stopSpeech() {
    if (_speaking) widget.onStopSpeech().ignore();
  }

  void _settle(double velocity) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.value = 0;
      return;
    }
    _slide.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 340, damping: 24),
        _slide.value,
        0,
        velocity,
      ),
    );
  }

  void _endDrag(DragEndDetails details, double width) {
    final velocity = details.primaryVelocity ?? 0;
    final projected = _slide.value + velocity * .16;
    if (_revealComplete && projected.abs() > width * .28) {
      _rate(
        projected.isNegative ? Grade.again : Grade.remembered,
        width,
        velocity,
      );
    } else {
      _settle(velocity);
    }
  }

  Future<void> _rate(Grade grade, double width, [double velocity = 0]) async {
    final card = _current;
    if (card == null || _submitting || !_revealComplete) return;
    _stopSpeech();
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final target = grade == Grade.again ? -width * 1.4 : width * 1.4;
    final duration =
        (1000 * (target - _slide.value).abs() / math.max(1800, velocity.abs()))
            .round()
            .clamp(140, 270);
    try {
      final animation = reduceMotion
          ? Future<void>.value()
          : _slide
                .animateTo(
                  target,
                  duration: Duration(milliseconds: duration),
                  curve: Curves.easeInCubic,
                )
                .orCancel;
      final (next, _) = await (widget.onGrade(card, grade), animation).wait;
      if (!mounted) return;
      setState(() {
        widget.spacing.recordExposure(card, widget.now());
        if (grade == Grade.again) {
          _pending.insert(
            0,
            ReviewCard(card.entry, card.direction, state: next),
          );
        } else {
          _remembered++;
        }
        _flip.reset();
        _slide.value = 0;
        _submitting = false;
        _advance();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _settle(0);
      notifyUser(context, 'Не удалось сохранить ответ. Попробуйте ещё раз.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _current;
    final nextAttempt = _nextAttempt;
    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: LayoutBuilder(
                builder: (context, space) {
                  final width = space.maxWidth - 48;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 11, 24, 22),
                    children: [
                      Row(
                        children: [
                          IconButton.outlined(
                            tooltip: 'Назад',
                            onPressed: _submitting
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                            style: IconButton.styleFrom(
                              side: const BorderSide(color: line),
                              foregroundColor: text,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Повторение',
                              style: subheading.copyWith(fontSize: 20),
                            ),
                          ),
                          if (card != null)
                            Text(
                              '${_remembered + 1} / ${widget.queue.length}',
                              style: label.copyWith(letterSpacing: .4),
                            ),
                        ],
                      ),
                      const SizedBox(height: 17),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          value: widget.queue.isEmpty
                              ? 1
                              : _remembered / widget.queue.length,
                          backgroundColor: line,
                          valueColor: const AlwaysStoppedAnimation(mint),
                        ),
                      ),
                      const SizedBox(height: 23),
                      if (card != null) ...[
                        _activeCard(
                          card,
                          width,
                          (space.maxHeight - 245).clamp(285.0, 455.0),
                        ),
                        if (!_revealComplete)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Назовите ответ, затем коснитесь карточки.',
                              textAlign: TextAlign.center,
                              style: body,
                            ),
                          ),
                      ] else if (nextAttempt != null)
                        _waiting(context, nextAttempt)
                      else
                        _completed(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _waiting(BuildContext context, DateTime nextAttempt) => EmptyState(
    icon: Icons.schedule_rounded,
    title: 'Пауза перед повторением',
    detail:
        'Следующая попытка в ${TimeOfDay.fromDateTime(nextAttempt).format(context)}. Можно вернуться позже.',
    action: OutlinedButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Вернуться'),
    ),
  );

  Widget _completed() => EmptyState(
    icon: Icons.check_circle_outline_rounded,
    title: 'Повторение завершено',
    detail:
        'Пройдено: ${widget.queue.length} ${plural(widget.queue.length, 'карточка', 'карточки', 'карточек')}. Следующие повторения появятся по расписанию.',
    action: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Готово'),
      ),
    ),
  );

  Widget _activeCard(ReviewCard card, double width, double height) {
    final now = widget.now();
    final extraCard = _pending.any(
      (card) => !widget.spacing.availableAt(card).isAfter(now),
    );
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final canRate = _revealComplete && !_submitting;
    return SizedBox(
      height: height + 7,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (extraCard)
            Positioned.fill(
              left: 10,
              right: 10,
              top: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF14171B),
                  border: Border.all(color: line),
                  borderRadius: BorderRadius.circular(27),
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: height,
            child: Semantics(
              hint: _revealComplete ? null : 'Перевернуть карточку',
              customSemanticsActions: canRate
                  ? {
                      const CustomSemanticsAction(label: 'Не вспомнил'): () =>
                          _rate(Grade.again, width),
                      const CustomSemanticsAction(label: 'Вспомнил'): () =>
                          _rate(Grade.remembered, width),
                    }
                  : null,
              child: GestureDetector(
                onTap: _revealComplete ? null : _reveal,
                onHorizontalDragStart: canRate ? (_) => _slide.stop() : null,
                onHorizontalDragUpdate: canRate
                    ? (details) => _slide.value += details.delta.dx
                    : null,
                onHorizontalDragCancel: canRate ? () => _settle(0) : null,
                onHorizontalDragEnd: canRate
                    ? (details) => _endDrag(details, width)
                    : null,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_flip, _slide]),
                  builder: (context, _) {
                    final angle =
                        Curves.easeInOutCubic.transform(_flip.value) * math.pi;
                    final back = angle >= math.pi / 2;
                    final offset = _slide.value;
                    final transform = Matrix4.identity()
                      ..setEntry(3, 2, .0015)
                      ..rotateZ(
                        reducedMotion
                            ? 0
                            : (offset / width * .28).clamp(-.3, .3),
                      )
                      ..rotateY(back ? angle - math.pi : angle);
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: transform,
                        child: _CardFace(
                          card: card,
                          back: back,
                          onSpeak: () => _speak(card.entry.english),
                          highlight: (offset / width).abs().clamp(0.0, .5),
                          positive: offset > 0,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.card,
    required this.back,
    required this.onSpeak,
    required this.highlight,
    required this.positive,
  });
  final ReviewCard card;
  final bool back;
  final VoidCallback onSpeak;
  final double highlight;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final direction = card.direction;
    final code = back
        ? '${direction.promptCode} · ${direction.answerCode}'
        : direction.promptCode;
    final content = back ? card.answer : card.prompt;
    final promptIsEnglish = direction == Direction.enToRu;
    final contentIsEnglish = back ? !promptIsEnglish : promptIsEnglish;
    final showCredit =
        card.entry.automatic && (back || direction.promptCode == 'RU');
    return Panel(
      padding: const EdgeInsets.all(22),
      radius: 27,
      border: Color.lerp(
        back ? const Color(0xFF385A50) : line,
        positive ? mint : muted,
        highlight,
      )!,
      color: surface,
      child: Column(
        children: [
          Row(
            children: [
              Panel(
                color: mintSurface,
                border: const Color(0xFF2D4C41),
                radius: 9,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  card.direction.label,
                  style: label.copyWith(color: mint, fontSize: 11),
                ),
              ),
              const Spacer(),
              Text(code, style: label),
            ],
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  children: [
                    if (back) ...[
                      _term(
                        context,
                        card.prompt,
                        subheading.copyWith(
                          fontSize: 23,
                          color: muted,
                          fontWeight: FontWeight.w700,
                        ),
                        speak: promptIsEnglish,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _term(
                      context,
                      content,
                      heading.copyWith(fontSize: content.length > 28 ? 31 : 44),
                      speak: contentIsEnglish,
                    ),
                    if (back && card.entry.context.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      Text(
                        card.entry.context,
                        textAlign: TextAlign.center,
                        style: body,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 18,
            child: showCredit ? const Center(child: TranslationCredit()) : null,
          ),
        ],
      ),
    );
  }

  Widget _term(
    BuildContext context,
    String term,
    TextStyle style, {
    required bool speak,
  }) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: MediaQuery.textScalerOf(context).scale(style.fontSize!) * .2,
          children: [
            for (final word in term.split(_wordSeparator))
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(word, softWrap: false, maxLines: 1, style: style),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      label: term,
      hint: speak ? 'Озвучить английское слово' : null,
      button: speak ? true : null,
      onTap: speak ? onSpeak : null,
      excludeSemantics: true,
      child: speak
          ? Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onSpeak,
                borderRadius: BorderRadius.circular(10),
                child: content,
              ),
            )
          : content,
    );
  }
}
