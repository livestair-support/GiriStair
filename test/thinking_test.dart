import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/thinking.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_controls.dart';

Future<void> _selectMenu(WidgetTester tester, String key, String label) async {
  final menu = find.byKey(ValueKey(key));
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .descendant(
          of: find.byType(CupertinoButton),
          matching: find.text(label),
        )
        .last,
  );
  await tester.pumpAndSettle();
}

class _FailingStorage extends MemoryGiriStorage {
  bool fail = false;

  @override
  Future<void> write(String contents) async {
    if (fail) throw const FileSystemException('保存できません');
    await super.write(contents);
  }
}

GiriEvent _onlineEvent(
  String id, {
  required DateTime start,
  required DateTime end,
  EventKind kind = EventKind.online,
  EventStatus status = EventStatus.planned,
}) => GiriEvent(
  id: id,
  title: '会 $id',
  kind: kind,
  meetingType: MeetingType.tournament,
  status: status,
  createdAt: start,
  submissionStart: start,
  submissionEnd: end,
);

Future<void> _showThinking(WidgetTester tester, GiriStore store) async {
  await tester.binding.setSurfaceSize(const Size(430, 1100));
  addTearDown(() async {
    // In particular, dispose the screen's periodic deadline refresh timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    store.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(MaterialApp(home: ThinkingScreen(store: store)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('現在投稿期間中のネット大喜利だけを表示する', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final tomorrow = now.add(const Duration(days: 1));
    await store.saveEvent(
      _onlineEvent('open', start: yesterday, end: tomorrow),
    );
    await store.saveEvent(
      _onlineEvent(
        'future',
        start: tomorrow,
        end: now.add(const Duration(days: 2)),
      ),
    );
    await store.saveEvent(
      _onlineEvent(
        'closed',
        start: now.subtract(const Duration(days: 2)),
        end: yesterday,
      ),
    );
    await store.saveEvent(
      _onlineEvent(
        'live',
        start: yesterday,
        end: tomorrow,
        kind: EventKind.live,
      ),
    );
    await store.saveEvent(
      _onlineEvent(
        'canceled',
        start: yesterday,
        end: tomorrow,
        status: EventStatus.canceled,
      ),
    );

    await _showThinking(tester, store);

    expect(find.text('会 open'), findsOneWidget);
    expect(find.text('会 future'), findsNothing);
    expect(find.text('会 closed'), findsNothing);
    expect(find.text('会 live'), findsNothing);
    expect(find.text('会 canceled'), findsNothing);
  });

  testWidgets('投稿期間が終わった会の回答メモもメモ一覧から開ける', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    final now = DateTime.now();
    await store.saveEvent(
      _onlineEvent(
        'closed',
        start: now.subtract(const Duration(days: 2)),
        end: now.subtract(const Duration(days: 1)),
      ),
    );
    await store.saveNote(
      ThoughtNote(
        id: 'past-answer',
        title: '締切後に見返したい回答',
        kind: NoteKind.answers,
        createdAt: now,
        updatedAt: now,
        eventId: 'closed',
        body: '提出した回答\n次に試したい回答',
      ),
    );

    await _showThinking(tester, store);

    expect(find.text('投稿期間中のネット大喜利はありません'), findsOneWidget);
    await tester.ensureVisible(find.text('締切後に見返したい回答'));
    await tester.tap(find.text('締切後に見返したい回答'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(
      tester.widget<TextField>(fields.at(1)).controller!.text,
      '提出した回答\n次に試したい回答',
    );
  });

  testWidgets('主催会向けのお題を作成して保存し、再起動しても復元できる', (tester) async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    await _showThinking(tester, store);

    await tester.tap(find.text('お題を作る'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '主催会のお題候補');
    await tester.enterText(
      find.byType(TextField).at(1),
      'こんな受付は嫌だ\n未来の運動会で起きたこと',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(store.notes.single.kind, NoteKind.prompts);
    expect(find.text('主催会のお題候補'), findsOneWidget);
    final reopened = GiriStore(storage: storage);
    await reopened.load();
    expect(reopened.notes.single.title, '主催会のお題候補');
    expect(reopened.notes.single.body, 'こんな受付は嫌だ\n未来の運動会で起きたこと');
    reopened.dispose();
  });

  testWidgets('保存失敗時も書きかけの回答を残し、そのまま再試行できる', (tester) async {
    final storage = _FailingStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    await _showThinking(tester, store);

    await tester.tap(find.text('回答メモ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '考え中の回答');
    await tester.enterText(find.byType(TextField).at(1), '一つ目の案\n二つ目の案');
    storage.fail = true;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(store.notes, isEmpty);
    expect(find.text('保存できませんでした。内容を残したまま再試行できます。'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '考え中の回答',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '一つ目の案\n二つ目の案',
    );

    storage.fail = false;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.notes.single.body, '一つ目の案\n二つ目の案');
    expect(find.text('考え中の回答'), findsOneWidget);
  });

  testWidgets('メモの種類はプルダウンで絞り込み説明キャプションを表示しない', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    final now = DateTime.now();
    for (final kind in NoteKind.values) {
      await store.saveNote(
        ThoughtNote(
          id: kind.name,
          title: '保存した${kind.name}',
          kind: kind,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await _showThinking(tester, store);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('回答やお題の下書きを残せます。'), findsNothing);
    expect(find.text('登録で投稿の開始・締切を設定すると、ここに表示されます。'), findsNothing);
    final filter = find.byKey(const ValueKey('thinking-note-filter'));
    await tester.ensureVisible(filter);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(CupertinoButton),
            matching: find.text('お題'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(find.text('保存したprompts'), findsOneWidget);
    expect(find.text('保存したanswers'), findsNothing);
    expect(find.text('保存したfree'), findsNothing);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(CupertinoButton),
            matching: find.text('すべて'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(find.text('保存したanswers'), findsOneWidget);
    expect(find.text('保存したfree'), findsOneWidget);
    expect(store.notes, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('メモ編集の種類もプルダウンで選び保存できる', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await _showThinking(tester, store);
    await tester.tap(find.text('回答メモ'));
    await tester.pumpAndSettle();
    final kindMenu = find.byKey(const ValueKey('thought-editor-kind'));
    expect(find.byType(StairMenuRow<NoteKind>), findsOneWidget);
    await tester.tap(kindMenu);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(CupertinoButton),
            matching: find.text('お題'),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '種類を変えたメモ');
    await tester.enterText(find.byType(TextField).at(1), '保存する本文');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.notes.single.kind, NoteKind.prompts);
    expect(store.notes.single.title, '種類を変えたメモ');
    expect(store.notes.single.body, '保存する本文');
    expect(tester.takeException(), isNull);
  });

  testWidgets('投稿中の回戦ごとにお題を作り回答案を並べて保存する', (tester) async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    final now = DateTime.now();
    await store.saveEvent(
      GiriEvent(
        id: 'round-event',
        title: '長期ネット大会',
        kind: EventKind.online,
        meetingType: MeetingType.tournament,
        createdAt: now,
        rounds: [
          EventRound(
            id: 'preliminary-1',
            name: '予選1回戦',
            submissionStart: now.subtract(const Duration(days: 1)),
            submissionEnd: now.add(const Duration(days: 1)),
          ),
          EventRound(
            id: 'final',
            name: '決勝',
            submissionStart: now.add(const Duration(days: 8)),
            submissionEnd: now.add(const Duration(days: 15)),
          ),
        ],
      ),
    );
    await _showThinking(tester, store);
    expect(
      find.byKey(const ValueKey('active-round-round-event-preliminary-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('active-round-round-event-final')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('active-round-round-event-preliminary-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('round-add-topic')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('thought-editor-prompt')),
      '未来の学校にある変な授業',
    );
    await tester.enterText(
      find.byKey(const ValueKey('thought-editor-body')),
      '一つ目の回答案\n\n二つ目の回答案',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final note = store.notes.single;
    expect(note.eventId, 'round-event');
    expect(note.roundId, 'preliminary-1');
    expect(note.prompt, '未来の学校にある変な授業');
    expect(note.answers, ['一つ目の回答案', '二つ目の回答案']);
    expect(find.text('未来の学校にある変な授業'), findsOneWidget);
    final reopened = GiriStore(storage: storage);
    await reopened.load();
    expect(reopened.notes.single.roundId, 'preliminary-1');
    expect(reopened.notes.single.answers, hasLength(2));
    reopened.dispose();
  });

  testWidgets('お題を一件ずつ保存し使用済みを絞り込める', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await _showThinking(tester, store);
    await tester.tap(find.text('お題を作る'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('thought-editor-prompt')),
      '一件のお題',
    );
    await tester.tap(find.byKey(const ValueKey('thought-editor-used')));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.notes.single.prompt, '一件のお題');
    expect(store.notes.single.used, isTrue);
    await _selectMenu(tester, 'thinking-used-filter', '未使用');
    expect(find.text('一件のお題'), findsNothing);
    await _selectMenu(tester, 'thinking-used-filter', '使用済み');
    expect(find.text('一件のお題'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(ValueKey('note-actions-${store.notes.single.id}')),
    );
    await tester.tap(
      find.byKey(ValueKey('note-actions-${store.notes.single.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('未使用に戻す'));
    await tester.pumpAndSettle();
    expect(store.notes.single.used, isFalse);
    expect(find.text('一件のお題'), findsNothing);
    await _selectMenu(tester, 'thinking-used-filter', '未使用');
    expect(find.text('一件のお題'), findsOneWidget);
  });

  testWidgets('終了した回戦にも日程を選んでお題を追加できる', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    final now = DateTime.now();
    await store.saveEvent(
      GiriEvent(
        id: 'ended',
        title: '終了した大会',
        kind: EventKind.online,
        meetingType: MeetingType.tournament,
        createdAt: now,
        rounds: [
          EventRound(
            id: 'past',
            name: '予選2回戦',
            submissionStart: now.subtract(const Duration(days: 10)),
            submissionEnd: now.subtract(const Duration(days: 3)),
          ),
        ],
      ),
    );
    await _showThinking(tester, store);
    await tester.tap(find.text('回答メモ'));
    await tester.pumpAndSettle();
    await _selectMenu(tester, 'thought-editor-event', '終了した大会');
    await _selectMenu(tester, 'thought-editor-round', '予選2回戦');
    await tester.enterText(
      find.byKey(const ValueKey('thought-editor-prompt')),
      '振り返るお題',
    );
    await tester.enterText(
      find.byKey(const ValueKey('thought-editor-body')),
      '投稿した回答',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.notes.single.roundId, 'past');
    expect(store.notes.single.answers.single, '投稿した回答');
  });

  testWidgets('削除した回戦のお題を残った回戦に振り替えない', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    final now = DateTime.now();
    final event = GiriEvent(
      id: 'orphan',
      title: '日程を編集した大会',
      kind: EventKind.online,
      meetingType: MeetingType.tournament,
      createdAt: now,
      rounds: [EventRound(id: 'remaining', name: '決勝')],
    );
    await store.saveEvent(event);
    await store.saveNote(
      ThoughtNote(
        id: 'orphan-note',
        title: '削除日程のお題',
        prompt: '削除日程のお題',
        kind: NoteKind.answers,
        eventId: event.id,
        roundId: 'deleted-round',
        answers: ['保存した回答'],
        body: '保存した回答',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _showThinking(tester, store);
    expect(find.textContaining('削除された日程'), findsOneWidget);
    await tester.ensureVisible(find.text('削除日程のお題'));
    await tester.tap(find.text('削除日程のお題'));
    await tester.pumpAndSettle();
    expect(find.text('削除された日程'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.notes.single.roundId, 'deleted-round');
    expect(store.notes.single.answers, ['保存した回答']);
  });
}
