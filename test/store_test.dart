import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';

final _now = DateTime.utc(2026, 10, 27, 9);

GiriEvent _event(String id) => GiriEvent(
  id: id,
  title: '大喜利会 $id',
  kind: EventKind.live,
  meetingType: MeetingType.casual,
  createdAt: _now,
);

ThoughtNote _note(String id, {String? eventId}) => ThoughtNote(
  id: id,
  title: 'お題案',
  kind: NoteKind.prompts,
  createdAt: _now,
  updatedAt: _now,
  body: '作成中のお題\n次のお題',
  eventId: eventId,
);

class _FailingStorage extends MemoryGiriStorage {
  bool fail = false;

  @override
  Future<void> write(String contents) async {
    if (fail) throw const FileSystemException('保存できません');
    await super.write(contents);
  }
}

class _SlowStorage extends MemoryGiriStorage {
  @override
  Future<void> write(String contents) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await super.write(contents);
  }
}

void main() {
  test('初回起動と再起動後の記録・メモの復元', () async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    expect(store.loaded, isTrue);
    expect(store.events, isEmpty);
    expect(store.notes, isEmpty);
    await store.saveEvent(_event('event-1'));
    await store.saveNote(_note('note-1', eventId: 'event-1'));
    final reopened = GiriStore(storage: storage);
    await reopened.load();
    expect(reopened.events.single.title, '大喜利会 event-1');
    expect(reopened.notes.single.body, '作成中のお題\n次のお題');
    expect(reopened.notes.single.eventId, 'event-1');
  });

  test('同時に保存しても後の保存で先の記録を失わない', () async {
    final storage = _SlowStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    await Future.wait([
      store.saveEvent(_event('event-1')),
      store.saveEvent(_event('event-2')),
      store.saveNote(_note('note-1')),
    ]);
    final reopened = GiriStore(storage: storage);
    await reopened.load();
    expect(reopened.events.map((event) => event.id), ['event-1', 'event-2']);
    expect(reopened.notes.single.id, 'note-1');
  });

  test('書き込み失敗時は画面上・保存済みの記録を維持し再試行できる', () async {
    final storage = _FailingStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    await store.saveEvent(_event('event-1'));
    final previousContents = storage.contents;
    storage.fail = true;
    await expectLater(
      store.saveEvent(_event('event-2')),
      throwsA(isA<FileSystemException>()),
    );
    expect(store.events.single.id, 'event-1');
    expect(storage.contents, previousContents);
    storage.fail = false;
    await store.saveNote(_note('retry'));
    expect(store.notes.single.id, 'retry');
    expect(store.events.single.id, 'event-1');
  });

  test('壊れたデータを空データとして上書きしない', () async {
    final contents = jsonEncode({
      'schemaVersion': 1,
      'events': [_event('valid').toJson()],
      'notes': [
        <String, dynamic>{'id': 'broken'},
      ],
    });
    final storage = MemoryGiriStorage(contents);
    final store = GiriStore(storage: storage);
    await expectLater(store.load(), throwsFormatException);
    expect(store.loaded, isFalse);
    expect(store.events, isEmpty);
    await expectLater(store.saveEvent(_event('new')), throwsStateError);
    expect(storage.contents, contents);
  });

  test('未知のデータバージョンを拒否し元ファイルを保持する', () async {
    final storage = MemoryGiriStorage(
      '{"schemaVersion":2,"events":[],"notes":[]}',
    );
    final store = GiriStore(storage: storage);
    await expectLater(store.load(), throwsFormatException);
    expect(store.loaded, isFalse);
    expect(storage.contents, '{"schemaVersion":2,"events":[],"notes":[]}');
  });

  test('会を削除しても関連する思考メモの本文は残る', () async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    await store.saveEvent(_event('event-1'));
    await store.saveNote(_note('note-1', eventId: 'event-1'));
    await store.deleteEvent('event-1');
    final reopened = GiriStore(storage: storage);
    await reopened.load();
    expect(reopened.events, isEmpty);
    expect(reopened.notes.single.eventId, isNull);
    expect(reopened.notes.single.body, '作成中のお題\n次のお題');
  });

  test('会とメモを更新・削除しても公開リストを直接変更できない', () async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.saveEvent(_event('event-1'));
    await store.saveEvent(_event('event-1').copyWith(title: '編集後'));
    expect(store.events.single.title, '編集後');
    expect(() => store.events.clear(), throwsUnsupportedError);
    await store.saveNote(_note('note-1'));
    await store.saveNote(_note('note-1').copyWith(body: '編集した本文'));
    expect(store.notes.single.body, '編集した本文');
    expect(() => store.notes.clear(), throwsUnsupportedError);
    await store.deleteNote('note-1');
    expect(store.notes, isEmpty);
  });

  test('ファイル保存では直前の完全なデータをバックアップに残す', () async {
    final directory = await Directory.systemTemp.createTemp('giristair-test-');
    addTearDown(() => directory.delete(recursive: true));
    final storage = FileGiriStorage(directory: directory);
    expect(await storage.read(), isNull);
    await storage.write('first document');
    await storage.write('second document');
    expect(await storage.read(), 'second document');
    final backup = File('${directory.path}/giristair.json.bak');
    expect(await backup.readAsString(), 'first document');
    await File('${directory.path}/giristair.json').delete();
    expect(await storage.read(), 'first document');
  });

  test('日程削除でもお題と回答案と元のラウンド識別子を保持する', () async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    final event = _event('event-1').copyWith(
      kind: EventKind.online,
      rounds: [
        const EventRound(id: 'qualifier', name: '予選'),
        const EventRound(id: 'final', name: '決勝'),
      ],
    );
    await store.saveEvent(event);
    final note = _note('topic', eventId: event.id).copyWith(
      roundId: 'qualifier',
      prompt: 'お題の本文',
      answers: ['回答案'],
      used: true,
    );
    await store.saveNote(note);
    await store.saveEvent(event.copyWith(rounds: [event.rounds.last]));
    final reopened = GiriStore(storage: storage);
    await reopened.load();
    final saved = reopened.notes.single;
    expect(saved.eventId, event.id);
    expect(saved.roundId, 'qualifier');
    expect(saved.prompt, 'お題の本文');
    expect(saved.answers, ['回答案']);
    expect(saved.used, isTrue);
    await reopened.deleteEvent(event.id);
    expect(reopened.notes.single.eventId, isNull);
    expect(reopened.notes.single.roundId, isNull);
    expect(reopened.notes.single.answers, ['回答案']);
  });

  test('不正なラウンドを含むバックアップの復元では元データを保持する', () async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    await store.saveEvent(_event('current'));
    final previous = storage.contents;
    final malformed = _event('bad').toJson()..['rounds'] = ['invalid'];
    await expectLater(
      store.restoreBackup(
        jsonEncode({
          'schemaVersion': 1,
          'events': [malformed],
          'notes': [],
        }),
      ),
      throwsFormatException,
    );
    expect(storage.contents, previous);
    expect(store.events.single.id, 'current');
  });
}
