import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/aggregate.dart';
import 'package:giristair/screens/event_list.dart';
import 'package:giristair/screens/venues.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_theme.dart';

GiriEvent participation(
  String id, {
  EventKind kind = EventKind.live,
  String venue = '',
  String? siteId,
  List<String> participants = const [],
  bool joined = true,
}) => GiriEvent(
  id: id,
  title: '記録$id',
  kind: kind,
  meetingType: MeetingType.casual,
  createdAt: DateTime(2026, 6),
  eventDate: kind == EventKind.live ? DateTime(2026, 6, 10) : null,
  submissionEnd: kind == EventKind.online ? DateTime(2026, 6, 10) : null,
  status: EventStatus.attended,
  isParticipating: joined,
  onlineSiteId: siteId,
  participants: participants,
  venue: venue,
);

Future<void> openAggregate(WidgetTester tester, GiriStore store) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 2600);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: stairTheme(Brightness.light),
      home: AggregateScreen(store: store),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'both formats have equal metrics and the format menu filters them',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await store.savePreferences(store.preferences.copyWith(selfName: '自分'));
      await store.saveEvent(participation('live', participants: ['自分', 'A']));
      await store.saveEvent(
        participation(
          'online',
          kind: EventKind.online,
          participants: ['自分', 'B'],
        ),
      );
      await store.saveEvent(
        participation('notJoined', kind: EventKind.online, joined: false),
      );
      await openAggregate(tester, store);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('aggregate-live-count')))
            .data,
        '1回',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('aggregate-online-count')))
            .data,
        '1回',
      );
      expect(find.text('月別の参加回数'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aggregate-kind')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ネット大喜利').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('aggregate-live-count')))
            .data,
        '0回',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('aggregate-online-count')))
            .data,
        '1回',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('venue ranking opens its venue profile', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.saveVenue(
      const GiriVenue(id: 'venue', name: '会場A', prefecture: '東京都'),
    );
    await store.saveEvent(participation('live', venue: '会場A'));
    await openAggregate(tester, store);
    await tester.tap(find.text('会場A'));
    await tester.pumpAndSettle();
    expect(find.byType(VenueDetailScreen), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('venue-detail-name'))).data,
      '会場A',
    );
    expect(find.text('東京都'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('site ranking uses the registered name and opens its cycles', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.saveOnlineSite(const OnlineSite(id: 'site', name: '継続サイト'));
    await store.saveEvent(
      participation('week1', kind: EventKind.online, siteId: 'site'),
    );
    await store.saveEvent(
      participation('week2', kind: EventKind.online, siteId: 'site'),
    );
    await store.saveEvent(
      participation(
        'notJoined',
        kind: EventKind.online,
        siteId: 'site',
        joined: false,
      ),
    );
    await openAggregate(tester, store);
    await tester.tap(find.text('継続サイト'));
    await tester.pumpAndSettle();
    expect(find.byType(EventListCard), findsNWidgets(2));
    expect(find.text('記録notJoined'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
