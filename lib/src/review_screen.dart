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
    required this.onGrade,
    required this.onSpeak,
    required this.onStopSpeech,
  });
  final List<ReviewCard> queue;
  final Future<void> Function(ReviewCard, Grade) onGrade;
  final Future<void> Function(String) onSpeak;
  final Future<void> Function() onStopSpeech;

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
  int _index = 0;
  bool _submitting = false;
  bool _speaking = false;

  bool get _revealComplete => _flip.isCompleted;

  @override
  void dispose() {
    _stopSpeech();
    _flip.dispose();
    _slide.dispose();
    super.dispose();
  }

  void _reveal() {
    if (_submitting || _flip.value > 0) return;
    _stopSpeech();
    HapticFeedback.selectionClick();
    if (MediaQuery.disableAnimationsOf(context)) {
      _flip.value = 1;
    } else {
      _flip.forward();
    }
  }

  Future<void> _speak(String word) async {
    if (_speaking || _submitting || _flip.isAnimating) return;
    setState(() => _speaking = true);
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
      if (mounted) setState(() => _speaking = false);
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
    if (_submitting || !_revealComplete) return;
    _stopSpeech();
    final card = widget.queue[_index];
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final target = grade == Grade.again ? -width * 1.4 : width * 1.4;
    final duration =
        (1000 * (target - _slide.value).abs() / math.max(1800, velocity.abs()))
            .round()
            .clamp(140, 270);
    try {
      await Future.wait([
        if (!reduceMotion)
          _slide
              .animateTo(
                target,
                duration: Duration(milliseconds: duration),
                curve: Curves.easeInCubic,
              )
              .orCancel,
        widget.onGrade(card, grade),
      ]);
      if (!mounted) return;
      setState(() {
        _index++;
        _flip.reset();
        _slide.value = 0;
        _submitting = false;
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
    final finished = _index == widget.queue.length;
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
                          if (!finished)
                            Text(
                              '${_index + 1} / ${widget.queue.length}',
                              style: label.copyWith(letterSpacing: .4),
                            ),
                        ],
                      ),
                      const SizedBox(height: 17),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          value: _index / widget.queue.length,
                          backgroundColor: line,
                          valueColor: const AlwaysStoppedAnimation(mint),
                        ),
                      ),
                      const SizedBox(height: 23),
                      if (finished)
                        _completed()
                      else
                        _activeCard(
                          widget.queue[_index],
                          width,
                          (space.maxHeight - 245).clamp(285.0, 455.0),
                        ),
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
    final extraCard = _index + 1 < widget.queue.length;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final canRate = _revealComplete && !_submitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
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
                  customSemanticsActions: canRate
                      ? {
                          const CustomSemanticsAction(
                            label: 'Не вспомнил',
                          ): () =>
                              _rate(Grade.again, width),
                          const CustomSemanticsAction(label: 'Вспомнил'): () =>
                              _rate(Grade.remembered, width),
                        }
                      : null,
                  child: GestureDetector(
                    onTap: _revealComplete ? null : _reveal,
                    onHorizontalDragStart: canRate
                        ? (_) => _slide.stop()
                        : null,
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
                            Curves.easeInOutCubic.transform(_flip.value) *
                            math.pi;
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
                              speaking: _speaking,
                              onSpeak:
                                  _speaking || _submitting || _flip.isAnimating
                                  ? null
                                  : () => _speak(card.entry.english),
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
        ),
        if (!_revealComplete) ...[
          const SizedBox(height: 23),
          FilledButton(
            onPressed: _flip.isAnimating ? null : _reveal,
            child: const Text('Показать перевод'),
          ),
          const SizedBox(height: 12),
          Text(
            'Вспомните перевод, затем переверните карточку.',
            textAlign: TextAlign.center,
            style: body.copyWith(fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.card,
    required this.back,
    required this.speaking,
    required this.onSpeak,
    required this.highlight,
    required this.positive,
  });
  final ReviewCard card;
  final bool back;
  final bool speaking;
  final VoidCallback? onSpeak;
  final double highlight;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final code = back ? card.direction.answerCode : card.direction.promptCode;
    final content = back ? card.answer : card.prompt;
    final fontSize = content.length > 28 ? 31.0 : 44.0;
    final termStyle = heading.copyWith(fontSize: fontSize);
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
                    Semantics(
                      label: content,
                      excludeSemantics: true,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing:
                            MediaQuery.textScalerOf(context).scale(fontSize) *
                            .2,
                        children: [
                          for (final word in content.split(_wordSeparator))
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                word,
                                softWrap: false,
                                maxLines: 1,
                                style: termStyle,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (code == 'EN')
                      IconButton(
                        tooltip: 'Озвучить английское слово',
                        onPressed: onSpeak,
                        color: mint,
                        disabledColor: muted,
                        icon: Icon(
                          speaking
                              ? Icons.volume_up_rounded
                              : Icons.volume_up_outlined,
                          size: 22,
                        ),
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
            child: code == 'RU' && card.entry.automatic
                ? const Center(child: TranslationCredit())
                : null,
          ),
        ],
      ),
    );
  }
}
