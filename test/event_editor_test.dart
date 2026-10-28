import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/event_editor.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';

void main() {
  testWidgets(
    'new event resets status and does not leak into the next record',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EventEditor(store: store)),
        ),
      );

      final statusField = find.byType(DropdownButtonFormField<EventStatus>);
      await tester.ensureVisible(statusField);
      await tester.tap(statusField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('参加済み').last);
      await tester.pumpAndSettle();

      final titleField = find.byType(TextFormField).first;
      await tester.ensureVisible(titleField);
      await tester.enterText(titleField, '最初の大喜利会');
      final organizerField = find.byType(TextFormField).at(1);
      await tester.enterText(organizerField, '最初の主催者');
      FocusManager.instance.primaryFocus?.unfocus();

      await tester.ensureVisible(find.text('記録を保存'));
      await tester.tap(find.text('記録を保存'));
      await tester.pumpAndSettle();

      expect(store.events, hasLength(1));
      expect(store.events.single.title, '最初の大喜利会');
      expect(store.events.single.status, EventStatus.attended);
      expect(store.events.single.organizer, '最初の主催者');
      expect(
        tester.widget<TextFormField>(titleField).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextFormField>(organizerField).controller!.text,
        isEmpty,
      );
      expect(
        tester.state<FormFieldState<EventStatus>>(statusField).value,
        EventStatus.planned,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      await tester.ensureVisible(titleField);
      await tester.enterText(titleField, '次の大喜利会');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('記録を保存'));
      await tester.tap(find.text('記録を保存'));
      await tester.pumpAndSettle();

      expect(store.events, hasLength(2));
      final second = store.events.singleWhere(
        (event) => event.title == '次の大喜利会',
      );
      expect(second.status, EventStatus.planned);
      expect(second.organizer, isEmpty);
      expect(second.id, isNot(store.events.first.id));

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('a blank title is rejected after scrolling to the save button', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventEditor(store: store)),
      ),
    );

    await tester.ensureVisible(find.text('記録を保存'));
    await tester.tap(find.text('記録を保存'));
    await tester.pumpAndSettle();

    expect(store.events, isEmpty);
    await tester.ensureVisible(find.byType(TextFormField).first);
    expect(find.text('タイトルを入力してください'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
