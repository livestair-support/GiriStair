import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/event_editor.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_controls.dart';
import 'package:giristair/ui/stair_theme.dart';

Widget editor(
  GiriStore store, {
  GiriEvent? event,
  Future<String?> Function()? readImages,
}) => MaterialApp(
  locale: const Locale('ja'),
  supportedLocales: const [Locale('ja')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: stairTheme(Brightness.light),
  home: EventEditor(
    store: store,
    event: event,
    readImages: readImages ?? () async => null,
  ),
);

Finder participant(int index) =>
    find.byKey(ValueKey('event-participant-$index'));

Future<void> enter(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new event resets status and text before the next record', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await tester.pumpWidget(editor(store));

    await tester.tap(find.byType(StairMenuRow<EventStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('参加済み'));
    await tester.pumpAndSettle();
    await enter(tester, find.byKey(const ValueKey('event-title')), '最初の大喜利会');
    await enter(
      tester,
      find.byKey(const ValueKey('event-organizer')),
      '最初の主催者',
    );
    await save(tester);

    expect(store.events, hasLength(1));
    expect(store.events.single.title, '最初の大喜利会');
    expect(store.events.single.status, EventStatus.attended);
    expect(store.events.single.organizer, '最初の主催者');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('event-title')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('event-organizer')))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<StairMenuRow<EventStatus>>(
            find.byType(StairMenuRow<EventStatus>),
          )
          .value,
      EventStatus.planned,
    );

    await enter(tester, find.byKey(const ValueKey('event-title')), '次の大喜利会');
    await save(tester);
    expect(store.events, hasLength(2));
    final second = store.events.singleWhere((event) => event.title == '次の大喜利会');
    expect(second.status, EventStatus.planned);
    expect(second.organizer, isEmpty);
    expect(second.id, isNot(store.events.first.id));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('header save stays disabled for an empty or whitespace title', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await tester.pumpWidget(editor(store));
    final saveButton = find.descendant(
      of: find.byType(StairSaveButton),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(saveButton).onPressed, isNull);
    await enter(tester, find.byKey(const ValueKey('event-title')), '  ');
    expect(tester.widget<OutlinedButton>(saveButton).onPressed, isNull);
    expect(store.events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'individual participant rows trim, deduplicate and remove names',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await tester.pumpWidget(editor(store));
      await enter(tester, find.byKey(const ValueKey('event-title')), '参加者の記録');
      await enter(tester, participant(0), '  一人目  ');
      await tester.ensureVisible(find.text('参加者を追加'));
      await tester.tap(find.text('参加者を追加'));
      await tester.pumpAndSettle();
      await enter(tester, participant(1), '一人目');
      await tester.ensureVisible(find.text('参加者を追加'));
      await tester.tap(find.text('参加者を追加'));
      await tester.pumpAndSettle();
      await enter(tester, participant(2), '削除する人');
      final remove = find.byTooltip('参加者3を削除');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(participant(2), findsNothing);
      await tester.ensureVisible(find.text('参加者を追加'));
      await tester.tap(find.text('参加者を追加'));
      await tester.pumpAndSettle();
      await enter(tester, participant(2), '二人目、別名');
      await save(tester);

      expect(store.events.single.participants, ['一人目', '二人目、別名']);
      expect(
        tester.widget<TextFormField>(participant(0)).controller!.text,
        isEmpty,
      );
      expect(participant(1), findsNothing);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('past participant selection adds to current individual rows', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.saveEvent(
      GiriEvent(
        id: 'past',
        title: '過去の会',
        kind: EventKind.live,
        meetingType: MeetingType.casual,
        createdAt: DateTime(2026, 10, 1),
        participants: ['先輩', '一人目'],
      ),
    );
    await tester.pumpWidget(editor(store));
    await enter(tester, find.byKey(const ValueKey('event-title')), '今回の会');
    await enter(tester, participant(0), '一人目');
    await tester.ensureVisible(find.text('一覧から選ぶ'));
    await tester.tap(find.text('一覧から選ぶ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('先輩'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    await save(tester);

    final event = store.events.singleWhere((event) => event.title == '今回の会');
    expect(event.participants, ['一人目', '先輩']);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('bulk import keeps entered names and adds a 70-player roster', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await tester.pumpWidget(editor(store));
    await enter(tester, find.byKey(const ValueKey('event-title')), '70人の会');
    await enter(tester, participant(0), '先に入力した人');
    final bulk = find.byKey(const ValueKey('event-import-participants'));
    await tester.ensureVisible(bulk);
    await tester.tap(bulk);
    await tester.pumpAndSettle();
    final names = ['先に入力した人', ...List.generate(69, (i) => '参加者${i + 1}')];
    await tester.enterText(
      find.byKey(const ValueKey('participant-import-source')),
      names.join('\n'),
    );
    await tester.tap(find.byKey(const ValueKey('participant-import-preview')));
    await tester.pumpAndSettle();
    expect(find.text('69人を追加'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('participant-import-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('event-participant-69')), findsOneWidget);
    await save(tester);
    expect(store.events.single.participants, names);
    expect(store.playerDirectory, hasLength(70));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('canceling bulk import leaves the participant draft intact', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await tester.pumpWidget(editor(store));
    await enter(tester, participant(0), '入力済み');
    final bulk = find.byKey(const ValueKey('event-import-participants'));
    await tester.ensureVisible(bulk);
    await tester.tap(bulk);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('participant-import-source')),
      '追加しない人',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(participant(0)).controller!.text,
      '入力済み',
    );
    expect(participant(1), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('live date-only registration keeps unknown times unset', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await tester.pumpWidget(editor(store));
    await enter(tester, find.byKey(const ValueKey('event-title')), '時刻未定の会');
    await save(tester);

    expect(store.events.single.eventDate, isNotNull);
    expect(store.events.single.startsAt, isNull);
    expect(store.events.single.endsAt, isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'editing preserves an overnight end, participants and record identity',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      final original = GiriEvent(
        id: 'existing',
        title: '深夜の大喜利',
        kind: EventKind.live,
        meetingType: MeetingType.tournament,
        createdAt: DateTime(2026, 10, 1),
        organizer: '主催者',
        venue: '会場',
        participants: ['先輩', '後輩'],
        startsAt: DateTime(2026, 10, 28, 23),
        endsAt: DateTime(2026, 10, 29, 2),
        resultText: '準優勝',
        placement: 2,
        memo: '振り返り',
        status: EventStatus.attended,
      );
      await store.saveEvent(original);
      await tester.pumpWidget(editor(store, event: original));
      await enter(
        tester,
        find.byKey(const ValueKey('event-title')),
        '深夜の大喜利・更新',
      );
      await save(tester);

      expect(store.events, hasLength(1));
      final updated = store.events.single;
      expect(updated.id, original.id);
      expect(updated.createdAt, original.createdAt);
      expect(updated.participants, original.participants);
      expect(updated.startsAt, original.startsAt);
      expect(updated.endsAt, original.endsAt);
      expect(updated.resultText, original.resultText);
      expect(updated.placement, original.placement);
      expect(updated.memo, original.memo);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'incomplete online period is rejected and draft remains editable',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      final original = GiriEvent(
        id: 'online',
        title: 'ネット大喜利',
        kind: EventKind.online,
        meetingType: MeetingType.casual,
        createdAt: DateTime(2026, 10, 1),
        submissionStart: DateTime(2026, 10, 28, 12),
      );
      await tester.pumpWidget(editor(store, event: original));
      await save(tester);
      expect(store.events, isEmpty);
      expect(find.text('投稿期間は開始・終了の両方を入力してください。'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('event-title')))
            .controller!
            .text,
        'ネット大喜利',
      );
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  testWidgets('participant count is in header and OCR starts with one tap', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    var reads = 0;
    await tester.pumpWidget(
      editor(
        store,
        readImages: () async {
          reads++;
          return '一人目\n二人目';
        },
      ),
    );
    final count = find.byKey(const ValueKey('event-participant-count'));
    expect(
      find.ancestor(of: count, matching: find.byType(StairSectionTitle)),
      findsOneWidget,
    );
    final ocr = find.byKey(const ValueKey('event-import-participant-images'));
    await tester.ensureVisible(ocr);
    await tester.tap(ocr);
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('OCRで一括追加'), findsOneWidget);
    expect(find.text('2人を追加'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('participant-import-apply')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(count).data, '2人');
    expect(
      tester.widget<TextFormField>(participant(1)).controller!.text,
      '二人目',
    );
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'online schedule appends and reorders named rounds without losing dates',
    (tester) async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      final original = GiriEvent(
        id: 'rounds',
        title: '繰り返す大会',
        kind: EventKind.online,
        meetingType: MeetingType.tournament,
        createdAt: DateTime(2026),
        rounds: [
          EventRound(
            id: 'first',
            name: '予選1回戦',
            submissionStart: DateTime(2026, 10, 1),
            submissionEnd: DateTime(2026, 10, 8),
            votingStart: DateTime(2026, 10, 8),
            votingEnd: DateTime(2026, 10, 15),
          ),
        ],
      );
      await tester.pumpWidget(editor(store, event: original));
      final add = find.byKey(const ValueKey('event-round-add'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('予選2回戦'), findsWidgets);
      expect(find.textContaining('思考に表示'), findsNothing);
      await save(tester);
      final updated = store.events.single;
      expect(updated.rounds, hasLength(2));
      expect(updated.rounds.first.id, 'first');
      expect(updated.rounds.first.votingEnd, original.rounds.first.votingEnd);
      expect(updated.rounds.last.name, '予選2回戦');
      expect(updated.rounds.last.id, isNot('first'));
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('team tournament saves stages separately from final outcome', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    final original = GiriEvent(
      id: 'team',
      title: 'チーム大会',
      kind: EventKind.live,
      meetingType: MeetingType.tournament,
      createdAt: DateTime(2026),
      placement: 3,
      tournamentResult: TournamentResult(
        format: TournamentFormat.team,
        outcome: TournamentOutcome.placed,
        teamName: '元チーム',
        members: ['本人', '先輩'],
      ),
    );
    await tester.pumpWidget(editor(store, event: original));
    final teamName = find.byWidgetPredicate((widget) => widget is TextFormField && widget.key is ValueKey<String> && (widget.key as ValueKey<String>).value.startsWith('team-name-'));
    await enter(tester, teamName, 'スリザリン');
    final addMember = find.text('メンバーを追加');
    await tester.ensureVisible(addMember);
    await tester.tap(addMember);
    await tester.pumpAndSettle();
    final members = find.byWidgetPredicate((widget) => widget.key is ValueKey<String> && (widget.key as ValueKey<String>).value.startsWith('team-member-'));
    await enter(tester, members.last, '後輩');
    final add = find.byKey(const ValueKey('event-result-stage-add'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final stageMenu = find.byWidgetPredicate(
      (widget) =>
          widget is StairMenuRow<TournamentOutcome> && widget.label == '結果',
    );
    await tester.ensureVisible(stageMenu);
    await tester.tap(stageMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('通過'));
    await tester.pumpAndSettle();
    final finalMenu = find.byKey(const ValueKey('event-final-outcome'));
    await tester.ensureVisible(finalMenu);
    await tester.tap(finalMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('敗退'));
    await tester.pumpAndSettle();
    await save(tester);
    final updated = store.events.single;
    expect(updated.tournamentResult!.format, TournamentFormat.team);
    expect(updated.tournamentResult!.teamName, 'スリザリン');
    expect(updated.tournamentResult!.members, ['本人', '先輩', '後輩']);
    expect(updated.tournamentResult!.outcome, TournamentOutcome.eliminated);
    expect(
      updated.tournamentResult!.stages.single.outcome,
      TournamentOutcome.advanced,
    );
    expect(updated.placement, isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
