import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/thinking.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';

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
}
