import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thinkcaps/src/lexicon.dart';
import 'package:thinkcaps/src/platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android preserves card data and independent schedules', (
    _,
  ) async {
    final platform = ThinkCapsPlatform();
    final context = 'ThinkCaps test ${DateTime.now().microsecondsSinceEpoch}';
    const english = 'example';
    const russian = 'пример';

    Future<void> addCard() => platform.save(
      english: english,
      russian: russian,
      context: context,
      automatic: true,
    );

    await addCard();
    final created = (await platform.loadEntries()).singleWhere(
      (entry) => entry.context == context,
    );
    addTearDown(() => platform.remove(created.id));
    expect(created.english, english);
    expect(created.russian, russian);
    expect(created.automatic, isTrue);
    expect(created.forward.due, created.reverse.due);
    expect(created.forward.days, 0);
    expect(created.reverse.days, 0);

    await expectLater(
      addCard(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'DUPLICATE',
        ),
      ),
    );

    await platform.grade(
      ReviewCard(created, Direction.ruToEn),
      Grade.remembered,
    );
    await platform.save(
      id: created.id,
      english: english,
      russian: 'образец',
      context: context,
      automatic: false,
    );

    final updated = (await platform.loadEntries()).singleWhere(
      (entry) => entry.id == created.id,
    );
    expect(updated.context, context);
    expect(updated.russian, 'образец');
    expect(updated.automatic, isFalse);
    expect(updated.forward.due, created.forward.due);
    expect(updated.forward.days, 0);
    expect(updated.forward.streak, 0);
    expect(
      updated.reverse.due.difference(created.reverse.due),
      greaterThanOrEqualTo(const Duration(days: 1)),
    );
    expect(updated.reverse.days, 1);
    expect(updated.reverse.streak, 1);

    await platform.remove(created.id);
    expect(
      (await platform.loadEntries()).map((entry) => entry.id),
      isNot(contains(created.id)),
    );
  });
}
