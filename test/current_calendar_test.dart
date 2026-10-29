import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/current_calendar.dart';
import 'package:giristair/screens/event_list.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_theme.dart';

GiriEvent online({bool submission = true, bool voting = true}) => GiriEvent(
  id: 'online', title: '継続サイト', kind: EventKind.online,
  meetingType: MeetingType.casual, createdAt: DateTime(2026, 10, 1),
  rounds: [EventRound(id: 'round', name: '一部・お題A',
    submissionStart: DateTime(2026, 10, 1, 22),
    submissionEnd: DateTime(2026, 10, 8, 22),
    votingStart: DateTime(2026, 10, 8, 22),
    votingEnd: DateTime(2026, 10, 15, 22),
    submissionEnabled: submission, votingRequired: voting,
  )],
);

Widget app(Widget screen) => MaterialApp(
  locale: StairTypography.locale, supportedLocales: const [StairTypography.locale],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: stairTheme(Brightness.light), home: Scaffold(body: screen),
);

void main() {
  test('calendar keeps voting after submission is stopped', () {
    final periods = currentPeriodsFor([online(submission: false)]);
    expect(periods, hasLength(1));
    expect(periods.single.kind, CurrentPeriodKind.voting);
    expect(periods.single.label, '継続サイト · 投票');
    expect(periods.single.overlapsDay(DateTime(2026, 10, 8)), isTrue);
    expect(periods.single.overlapsDay(DateTime(2026, 10, 16)), isFalse);
  });

  test('midnight deadlines do not extend into the next calendar day', () {
    final event = online();
    final round = event.rounds.single.copyWith(votingEnd: DateTime(2026, 10, 15));
    final periods = currentPeriodsFor([event.copyWith(rounds: [round])]);
    final voting = periods.firstWhere((period) => period.kind == CurrentPeriodKind.voting);
    expect(voting.overlapsDay(DateTime(2026, 10, 14)), isTrue);
    expect(voting.overlapsDay(DateTime(2026, 10, 15)), isFalse);
    expect(currentPeriodsFor([event.copyWith(status: EventStatus.canceled)]), isEmpty);
  });

  testWidgets('month bars name the site and the display choice is saved', (tester) async {
    tester.view.physicalSize = const Size(393, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    final now = DateTime.now();
    final event = online().copyWith(rounds: [EventRound(id: 'now', name: '投稿・投票',
      submissionStart: DateTime(now.year, now.month, now.day),
      submissionEnd: DateTime(now.year, now.month, now.day + 7),
      votingStart: DateTime(now.year, now.month, now.day + 7),
      votingEnd: DateTime(now.year, now.month, now.day + 14),
    )]);
    await store.saveEvent(event);
    await tester.pumpWidget(app(EventListScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('カレント'));
    await tester.pumpAndSettle();
    expect(store.preferences.listCurrentMode, isTrue);
    expect(find.byType(CurrentCalendar), findsOneWidget);
    expect(find.text('継続サイト · 投稿'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('a site week opens without joining and joins from detail', (tester) async {
    tester.view.physicalSize = const Size(430, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.savePreferences(store.preferences.copyWith(selfName: '自分'));
    await store.saveOnlineSite(const OnlineSite(id: 'site', name: '毎週サイト', recurrence: SiteRecurrence.weekly));
    await tester.pumpWidget(app(EventListScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('site-site-week-0')));
    await tester.pumpAndSettle();
    expect(store.events.single.isParticipating, isFalse);
    await tester.tap(find.text('この回に参加する'));
    await tester.pumpAndSettle();
    expect(store.events.single.isParticipating, isTrue);
    expect(store.events.single.participants, ['自分']);
    expect(find.byKey(ValueKey('round-prompt-${store.events.single.id}-${store.events.single.rounds.single.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
