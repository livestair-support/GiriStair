import 'package:flutter/cupertino.dart';
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
    await tester.pumpWidget(app(Column(children: [
      EventListModeButton(store: store), Expanded(child: EventListScreen(store: store)),
    ])));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('list-search')), '別の名前');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('継続サイト'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('list-mode-button')));
    await tester.pumpAndSettle();
    expect(store.preferences.listCurrentMode, isTrue);
    expect(find.byType(CurrentCalendar), findsOneWidget);
    expect(find.text('継続サイト · 投稿'), findsWidgets);
    expect(find.byKey(const ValueKey('list-search')), findsNothing);
    expect(find.byKey(const ValueKey('list-attendance-tabs')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('list-mode-button')));
    await tester.pumpAndSettle();
    expect(store.preferences.listCurrentMode, isFalse);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('list-search'))).controller!.text, '別の名前');
    expect(find.text('継続サイト'), findsNothing);
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

  testWidgets('month wheels preserve grid height and the selected day through jumps', (tester) async {
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final year = DateTime.now().year;
    var month = DateTime(year, 10);
    var selected = DateTime(year, 10, 28);
    final original = selected;
    await tester.pumpWidget(app(StatefulBuilder(builder: (context, update) => SingleChildScrollView(
      child: CurrentCalendar(month: month, selected: selected, periods: const [],
        onMonthChanged: (value) => update(() => month = value),
        onSelected: (value) => update(() => selected = value), onOpenPeriod: (_) {},
      ),
    ))));
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byType(CurrentCalendar)).height;
    await tester.tap(find.byKey(const ValueKey('current-month-picker-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(CurrentCalendar)).height, closeTo(height, .1));
    expect(tester.widget<CupertinoButton>(find.byKey(const ValueKey('current-previous-month'))).onPressed, isNull);
    expect(tester.widget<CupertinoButton>(find.byKey(const ValueKey('current-next-month'))).onPressed, isNull);
    final yearWheel = tester.widget<CupertinoPicker>(find.byKey(const ValueKey('current-year-wheel')));
    final monthWheel = tester.widget<CupertinoPicker>(find.byKey(const ValueKey('current-month-wheel')));
    yearWheel.scrollController!.jumpToItem(22);
    monthWheel.scrollController!.jumpToItem(4);
    await tester.pumpAndSettle();
    expect(month, DateTime(year, 10));
    await tester.tap(find.byKey(const ValueKey('current-apply-month')));
    await tester.pumpAndSettle();
    expect(month, DateTime(year + 2, 5));
    expect(selected, original);
    expect(find.byKey(const ValueKey('current-year-wheel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('current-previous-month')));
    await tester.pumpAndSettle();
    expect(month, DateTime(year + 2, 4));
    expect(selected, original);
    await tester.tap(find.byKey(const ValueKey('current-next-month')));
    await tester.pumpAndSettle();
    expect(month, DateTime(year + 2, 5));
    expect(selected, original);

    await tester.tap(find.byKey(const ValueKey('current-month-picker-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('current-today')));
    await tester.pumpAndSettle();
    final today = DateUtils.dateOnly(DateTime.now());
    expect(month, DateTime(today.year, today.month));
    expect(selected, today);
    expect(find.byKey(const ValueKey('current-year-wheel')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('current-month-picker-toggle')));
    await tester.pumpAndSettle();
    final draft = tester.widget<CupertinoPicker>(find.byKey(const ValueKey('current-year-wheel')));
    draft.scrollController!.jumpToItem(21);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('current-month-picker-toggle')));
    await tester.pumpAndSettle();
    expect(month, DateTime(today.year, today.month));
    expect(selected, today);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed mode saves keep the list selected', (tester) async {
    final store = GiriStore(storage: _UnwritableStorage());
    await store.load();
    await tester.pumpWidget(app(EventListModeButton(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('list-mode-button')));
    await tester.pumpAndSettle();
    expect(store.preferences.listCurrentMode, isFalse);
    expect(find.text('表示方法を保存できませんでした。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}

class _UnwritableStorage implements GiriStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String contents) async => throw StateError('write failed');
}
