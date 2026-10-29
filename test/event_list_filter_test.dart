import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/event_list.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_controls.dart';
import 'package:giristair/ui/stair_theme.dart';

Future<void> showList(WidgetTester tester, GiriStore store) async {
  tester.view.physicalSize = const Size(430, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: StairTypography.locale,
      supportedLocales: const [StairTypography.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: stairTheme(Brightness.light),
      home: Scaffold(body: EventListScreen(store: store)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String key, String option) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('online card previews the nearest round and detail keeps all', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    final now = DateTime.now();
    await store.saveEvent(
      GiriEvent(
        id: 'long-tournament',
        title: '長い大会',
        kind: EventKind.online,
        meetingType: MeetingType.tournament,
        createdAt: now,
        rounds: [
          EventRound(
            id: 'past',
            name: '終了した予選',
            submissionEnd: now.subtract(const Duration(days: 7)),
          ),
          EventRound(
            id: 'current',
            name: '本戦1回戦',
            submissionEnd: now.add(const Duration(days: 1)),
          ),
          EventRound(
            id: 'future',
            name: '決勝',
            submissionEnd: now.add(const Duration(days: 14)),
          ),
        ],
      ),
    );
    await showList(tester, store);
    expect(find.text('3日程'), findsOneWidget);
    expect(find.textContaining('本戦1回戦'), findsOneWidget);
    expect(find.textContaining('決勝'), findsNothing);
    expect(find.textContaining('終了した予選'), findsNothing);
    await tester.tap(find.text('長い大会'));
    await tester.pumpAndSettle();
    expect(find.textContaining('終了した予選'), findsOneWidget);
    expect(find.textContaining('本戦1回戦'), findsOneWidget);
    expect(find.textContaining('決勝'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'dropdown filters and search respect the planned and attended tabs',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      final now = DateTime.now();
      final future = now.add(const Duration(days: 3));
      final past = now.subtract(const Duration(days: 3));
      GiriEvent event(
        String id,
        String title, {
        EventKind kind = EventKind.live,
        EventStatus status = EventStatus.planned,
        DateTime? date,
        String venue = '北会場',
      }) => GiriEvent(
        id: id,
        title: title,
        kind: kind,
        meetingType: MeetingType.casual,
        status: status,
        createdAt: now,
        eventDate: kind == EventKind.live ? date ?? future : null,
        submissionEnd: kind == EventKind.online ? future : null,
        venue: venue,
        organizer: '主催者',
        participants: const ['同席者'],
      );
      for (final record in [
        event('north', '北の予定'),
        event('south', '南の予定', venue: '南会場'),
        event('past', '過去の予定', date: past),
        event('attended', '参加済みの会', status: EventStatus.attended),
        event('canceled', '中止した会', status: EventStatus.canceled),
        event('online', 'ネットの予定', kind: EventKind.online),
      ]) {
        await store.saveEvent(record);
      }
      await showList(tester, store);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.text('6件の予定と記録'), findsNothing);
      expect(find.text('北の予定'), findsOneWidget);
      expect(find.text('ネットの予定'), findsOneWidget);

      await choose(tester, 'list-kind-filter', '生大喜利');
      expect(find.text('ネットの予定'), findsNothing);
      await choose(tester, 'list-status-filter', '参加予定');
      expect(find.text('参加済みの会'), findsNothing);
      expect(find.text('中止した会'), findsNothing);
      expect(find.byKey(const ValueKey('list-display-filter')), findsNothing);
      expect(find.text('過去の予定'), findsOneWidget);
      expect(find.text('南の予定'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('list-search')), '北会場');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('北の予定'), findsOneWidget);
      expect(find.text('南の予定'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('list-kind-filter')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StairMenuRow<int>>(
              find.byKey(const ValueKey('list-kind-filter')),
            )
            .value,
        EventKind.live.index,
      );
      expect(find.text('北の予定'), findsOneWidget);

      await choose(tester, 'list-kind-filter', 'すべて');
      await choose(tester, 'list-status-filter', 'すべて');
      await tester.enterText(find.byKey(const ValueKey('list-search')), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      for (final record in store.events.where(
        (event) => event.status != EventStatus.attended,
      )) {
        expect(find.text(record.title), findsOneWidget);
      }
      expect(find.text('参加済みの会'), findsNothing);
      await tester.tap(find.text('参加済'));
      await tester.pumpAndSettle();
      expect(find.text('参加済みの会'), findsOneWidget);
      expect(find.text('北の予定'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('empty list omits descriptive captions', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await showList(tester, store);
    expect(find.text('記録がありません'), findsOneWidget);
    expect(find.byKey(const ValueKey('list-display-filter')), findsNothing);
    final emptyText = tester.getRect(find.text('記録がありません'));
    final screen = tester.getRect(find.byType(EventListScreen));
    expect(emptyText.center.dx, closeTo(screen.center.dx, 1));
    expect(find.text('0件の予定と記録'), findsNothing);
    expect(find.text('最初の一席を残しましょう'), findsNothing);
    expect(find.text('「登録」タブから参加予定や過去の記録を追加できます。'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
