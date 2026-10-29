import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/event_editor.dart';
import 'package:giristair/screens/event_round_editor.dart';
import 'package:giristair/screens/result_entry.dart';
import 'package:giristair/scheduling.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_controls.dart';
import 'package:giristair/ui/stair_theme.dart';

Widget app(Widget child) => MaterialApp(
  locale: const Locale('ja', 'JP'),
  supportedLocales: const [Locale('ja', 'JP')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: stairTheme(Brightness.light),
  home: child,
);

Future<void> enter(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'editing retains site identity, teams, standings and joining state',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      final original = GiriEvent(
        id: 'site-cycle',
        title: '大会',
        kind: EventKind.online,
        meetingType: MeetingType.tournament,
        createdAt: DateTime(2026),
        onlineSiteId: 'site',
        cycleKey: '2026-10-29T22:00',
        affiliation: '一部',
        block: 'A',
        isParticipating: false,
        tournamentFormat: TournamentFormat.team,
        teamSize: 3,
        myTeamId: 'mine',
        teams: [
          GiriTeam(id: 'mine', name: '自チーム', members: ['本人'], isMine: true),
        ],
        standings: [
          TournamentStanding(id: 'winner', placement: 1, teamName: '優勝チーム'),
        ],
        rounds: [
          completeRoundSchedule(
            EventRound(
              id: 'round',
              name: '予選1回戦',
              submissionStart: DateTime(2026, 10, 29, 22),
            ),
          ),
        ],
      );
      await store.saveEvent(original);
      await tester.pumpWidget(app(EventEditor(store: store, event: original)));
      await enter(tester, 'event-title', '大会の名前を修正');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = store.events.single;
      expect(saved.title, '大会の名前を修正');
      expect(saved.onlineSiteId, original.onlineSiteId);
      expect(saved.cycleKey, original.cycleKey);
      expect(saved.isParticipating, isFalse);
      expect(saved.myTeamId, 'mine');
      expect(saved.teams.single.name, '自チーム');
      expect(saved.standings.single.teamName, '優勝チーム');
      expect(saved.affiliation, '一部');
      expect(saved.block, 'A');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'another organizer adds self once and own hosting remains distinguishable',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await store.savePreferences(
        store.preferences.copyWith(selfName: '本人', onboardingCompleted: true),
      );
      await tester.pumpWidget(app(EventEditor(store: store)));
      await enter(tester, 'event-title', '主催確認');
      await enter(tester, 'event-organizer', '別の主催者');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('event-participant-0')),
            )
            .controller!
            .text,
        '本人',
      );
      await enter(tester, 'event-organizer', '本人');
      expect(find.text('自分の主催'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('event-participant-0')),
            )
            .controller!
            .text,
        isEmpty,
      );
      await enter(tester, 'event-organizer', '別の主催者');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.events.single.participants, ['本人']);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'normal online registration creates one site and unjoined weeks',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await tester.pumpWidget(app(EventEditor(store: store)));
      final kind = find.byType(StairMenuRow<EventKind>);
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ネット大喜利'));
      await tester.pumpAndSettle();
      await enter(tester, 'event-title', '続いていくサイト');
      expect(find.text('予選1回戦'), findsNothing);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('サイトを登録'), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.onlineSites.single.name, '続いていくサイト');
      expect(store.events, hasLength(2));
      expect(store.events.every((event) => !event.isParticipating), isTrue);
      expect(store.events.map((event) => event.cycleKey).toSet(), hasLength(2));
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'generated schedule follows its anchor while manual dates remain fixed',
    (tester) async {
      var rounds = [
        completeRoundSchedule(
          EventRound(
            id: 'r',
            name: '予選1回戦',
            submissionStart: DateTime(2026, 10, 1, 22),
          ),
        ),
      ];
      await tester.pumpWidget(
        app(
          Scaffold(
            body: StatefulBuilder(
              builder: (context, change) => SingleChildScrollView(
                child: EventRoundEditor(
                  rounds: rounds,
                  autoFillRoundIds: const {'r'},
                  newId: () => 'new',
                  onChanged: (value) => change(() => rounds = value),
                ),
              ),
            ),
          ),
        ),
      );
      StairDateRow row(String label) => tester.widget<StairDateRow>(
        find.byWidgetPredicate(
          (widget) => widget is StairDateRow && widget.label == label,
        ),
      );
      row('投稿開始').onChanged!(DateTime(2026, 10, 3, 22));
      await tester.pump();
      expect(rounds.single.submissionEnd, DateTime(2026, 10, 10, 22));
      expect(rounds.single.votingEnd, DateTime(2026, 10, 17, 22));
      row('投票開始').onChanged!(DateTime(2026, 10, 13, 20));
      await tester.pump();
      row('投稿開始').onChanged!(DateTime(2026, 10, 4, 22));
      await tester.pump();
      expect(rounds.single.submissionEnd, DateTime(2026, 10, 11, 22));
      expect(rounds.single.votingStart, DateTime(2026, 10, 13, 20));
      expect(rounds.single.votingEnd, DateTime(2026, 10, 20, 20));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('same-stage prompts and next stages retain distinct stable IDs', (
    tester,
  ) async {
    var rounds = [
      completeRoundSchedule(
        const EventRound(id: 'first', stageId: 'stage', name: '予選1回戦'),
      ),
    ];
    var id = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, change) => SingleChildScrollView(
              child: EventRoundEditor(
                rounds: rounds,
                newId: () => 'new-${id++}',
                onChanged: (value) => change(() => rounds = value),
              ),
            ),
          ),
        ),
      ),
    );
    final prompt = find.byKey(const ValueKey('event-round-add-prompt'));
    await tester.ensureVisible(prompt);
    await tester.tap(prompt);
    await tester.pumpAndSettle();
    expect(rounds.last.effectiveStageId, 'stage');
    expect(rounds.last.promptNumber, 2);
    expect(rounds.last.name, '予選1回戦');
    final stage = find.byKey(const ValueKey('event-round-add'));
    await tester.ensureVisible(stage);
    await tester.tap(stage);
    await tester.pumpAndSettle();
    expect(rounds.last.effectiveStageId, isNot('stage'));
    expect(rounds.last.promptNumber, 1);
    expect(rounds.last.name, '予選2回戦');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'prompt score and overall winners do not imply self advancement',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await store.saveEvent(
        GiriEvent(
          id: 'tournament',
          title: '3お題の予選',
          kind: EventKind.online,
          meetingType: MeetingType.tournament,
          createdAt: DateTime(2026),
          rounds: [
            for (var number = 1; number <= 3; number++)
              EventRound(
                id: 'r$number',
                stageId: 'stage',
                name: '予選1回戦',
                promptNumber: number,
              ),
          ],
        ),
      );
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ResultEntryScreen(
                      store: store,
                      eventId: 'tournament',
                      initialRoundId: 'r2',
                    ),
                  ),
                ),
                child: const Text('結果を開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('結果を開く'));
      await tester.pumpAndSettle();
      Finder fieldEnding(String suffix) => find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField &&
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.endsWith(suffix),
      );
      Future<void> type(Finder field, String text) async {
        await tester.ensureVisible(field);
        await tester.enterText(field, text);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }

      await type(fieldEnding('-voters'), '20');
      await type(fieldEnding('-points'), '12');
      expect(find.text('60.00%'), findsOneWidget);
      final addWinner = find.byKey(const ValueKey('tournament-standing-add'));
      await tester.ensureVisible(addWinner);
      await tester.tap(addWinner);
      await tester.pumpAndSettle();
      await type(fieldEnding('-players'), '優勝した人');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = store.events.single;
      expect(saved.tournamentResult!.outcome, TournamentOutcome.unrecorded);
      expect(saved.effectivePlacement, isNull);
      expect(saved.tournamentResult!.stages, hasLength(1));
      final score = saved.tournamentResult!.stages.single;
      expect(score.roundId, 'r2');
      expect(score.stageId, 'stage');
      expect(score.voteRate, 60);
      expect(score.outcome, TournamentOutcome.unrecorded);
      expect(saved.standings.single.playerNames, ['優勝した人']);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
