import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thinkcaps/main.dart';

void main() {
  testWidgets('screenshot text and saved context are lowercase', (
    tester,
  ) async {
    const channel = MethodChannel('app.thinkcaps/bridge');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Map<Object?, Object?>? saved;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'scanScreenshot' => 'THE OLD COMPASS POINTS NORTH.',
        'translate' => 'компас',
        'saveEntry' => saved = call.arguments as Map<Object?, Object?>,
        _ => [],
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const ThinkCapsApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Импорт').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Скриншот'));
    await tester.pumpAndSettle();

    const sentence = 'the old compass points north.';
    final richText = find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == sentence,
    );
    final paragraph = tester.renderObject<RenderParagraph>(richText);
    final compass = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 8, extentOffset: 15),
        )
        .single;
    await tester.tapAt(paragraph.localToGlobal(compass.toRect().center));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(saved?['english'], 'compass');
    expect(saved?['context'], sentence);
    await tester.pumpWidget(const SizedBox());
  });
}
