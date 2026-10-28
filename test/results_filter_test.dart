import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/results.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_theme.dart';

GiriEvent tournament(
  String title,
  EventKind kind, {
  String result = '',
  EventStatus status = EventStatus.attended,
  MeetingType meetingType = MeetingType.tournament,
}) => GiriEvent(
  id: title,
  title: title,
  kind: kind,
  meetingType: meetingType,
  status: status,
  resultText: result,
  createdAt: DateTime(2026),
  eventDate: kind == EventKind.live ? DateTime(2026, 10, 28) : null,
);

Future<void> showResults(WidgetTester tester, GiriStore store) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 2400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: stairTheme(Brightness.light),
      home: ResultsScreen(store: store),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String key, String value) async {
  final row = find.byKey(ValueKey(key));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(
          of: find.byType(CupertinoButton),
          matching: find.text(value),
        )
        .last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'format and result menus combine without changing tournament rules',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      for (final event in [
        tournament('生の結果あり', EventKind.live, result: '優勝'),
        tournament('生の未入力', EventKind.live),
        tournament('ネットの結果あり', EventKind.online, result: '決勝進出'),
        tournament('ネットの未入力', EventKind.online),
        tournament('中止した大会', EventKind.live, status: EventStatus.canceled),
        tournament('通常会', EventKind.live, meetingType: MeetingType.casual),
      ]) {
        await store.saveEvent(event);
      }
      await showResults(tester, store);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.text('大会の結果や順位を、記録から追記できます。'), findsNothing);
      expect(find.text('中止した大会'), findsNothing);
      expect(find.text('通常会'), findsNothing);
      expect(find.text('生の結果あり'), findsOneWidget);
      expect(find.text('ネットの未入力'), findsOneWidget);

      await choose(tester, 'results-format', 'ネット大喜利');
      expect(find.text('生の結果あり'), findsNothing);
      expect(find.text('生の未入力'), findsNothing);
      expect(find.text('ネットの結果あり'), findsOneWidget);
      expect(find.text('ネットの未入力'), findsOneWidget);

      await choose(tester, 'results-result-filter', '結果あり');
      expect(find.text('ネットの結果あり'), findsOneWidget);
      expect(find.text('ネットの未入力'), findsNothing);
      await choose(tester, 'results-result-filter', '未入力');
      expect(find.text('ネットの結果あり'), findsNothing);
      expect(find.text('ネットの未入力'), findsOneWidget);
      await choose(tester, 'results-format', 'すべて');
      expect(find.text('生の未入力'), findsOneWidget);
      expect(find.text('ネットの未入力'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('results-result-filter')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('生の未入力'), findsOneWidget);
      expect(find.text('ネットの結果あり'), findsNothing);
      expect(store.events, hasLength(6));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty results show a brief state without instructional captions',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await showResults(tester, store);
      expect(find.text('大会の記録がありません'), findsOneWidget);
      expect(find.text('「登録」で大会を選ぶと、ここに参加予定や結果が並びます。'), findsNothing);
      expect(find.text('結果の絞り込みを変えてみてください。'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('typed final result and team stages remain visible in detail', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.saveEvent(
      tournament('チーム大会', EventKind.online).copyWith(
        rounds: [
          EventRound(
            id: 'q',
            name: '予選1回戦',
            submissionEnd: DateTime(2026, 10, 30),
          ),
          EventRound(id: 'f', name: '決勝', votingEnd: DateTime(2026, 11, 15)),
        ],
        tournamentResult: TournamentResult(
          format: TournamentFormat.team,
          outcome: TournamentOutcome.champion,
          teamName: 'チーム星',
          members: ['A', 'B', 'C'],
          stages: [
            const ResultStage(
              id: 'q',
              name: '予選',
              outcome: TournamentOutcome.advanced,
              placement: 2,
            ),
            const ResultStage(
              id: 'r',
              name: '敗者復活',
              outcome: TournamentOutcome.advanced,
              memo: '同点決選',
            ),
            const ResultStage(
              id: 'f',
              name: '決勝',
              outcome: TournamentOutcome.champion,
            ),
          ],
        ),
      ),
    );
    await showResults(tester, store);
    await choose(tester, 'results-result-filter', '結果あり');
    expect(find.text('チーム大会'), findsOneWidget);
    expect(find.text('チーム戦 · チーム星'), findsOneWidget);
    expect(find.text('優勝'), findsOneWidget);
    await tester.tap(find.text('チーム大会'));
    await tester.pumpAndSettle();
    expect(find.text('参加記録'), findsOneWidget);
    expect(find.text('予選1回戦'), findsOneWidget);
    expect(find.text('チーム星'), findsOneWidget);
    expect(find.text('A、B、C'), findsOneWidget);
    await tester.ensureVisible(find.text('敗者復活'));
    expect(find.text('通過 · 同点決選'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
