import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';

GiriEvent _event(List<String> participants) => GiriEvent(
  id: 'event', title: '会', kind: EventKind.live,
  meetingType: MeetingType.casual, createdAt: DateTime(2026, 10, 28),
  participants: participants,
);

class _FailingStorage extends MemoryGiriStorage {
  bool fail = false;

  @override
  Future<void> write(String contents) async {
    if (fail) throw const FileSystemException('failed');
    return super.write(contents);
  }
}

void main() {
  test('旧形式を変更せず読み込み、過去の参加者を一覧に表示する', () async {
    final source = jsonEncode({
      'schemaVersion': 1,
      'events': [_event(['田中', '田中', '大喜利 A']).toJson()],
      'notes': [],
    });
    final storage = MemoryGiriStorage(source);
    final store = GiriStore(storage: storage);
    await store.load();
    expect(store.players, isEmpty);
    expect(store.playerDirectory.map((p) => p.name).toSet(), {'田中', '大喜利 A'});
    expect(store.preferences.theme, 'light');
    expect(storage.contents, source);
    final oldProfile = store.playerDirectory.firstWhere((p) => p.name == '田中');
    await store.savePlayer(oldProfile.copyWith(furigana: 'たなか'));
    final reopened = GiriStore(storage: storage);
    await reopened.load();
    expect(reopened.players.single.furigana, 'たなか');
    expect(reopened.players.single.id.startsWith('history:'), isFalse);
    expect(reopened.events.single.participants, ['田中', '田中', '大喜利 A']);
  });

  test('参加者70人を保存し名前とフリガナを再起動後も保持する', () async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    await store.saveEvent(_event(List.generate(70, (i) => '参加者$i')));
    expect(store.players.length, 70);
    final player = store.players[35];
    await store.savePlayer(player.copyWith(name: '新しい名前', furigana: 'あたらしいなまえ'));
    await store.savePreferences(store.preferences.copyWith(theme: 'dark', notificationsEnabled: true, reminderMinutes: 30));
    final reopened = GiriStore(storage: storage);
    await reopened.load();
    expect(reopened.playerDirectory.length, 70);
    expect(reopened.playerDirectory.first.name, '新しい名前');
    expect(reopened.events.single.participants[35], '新しい名前');
    expect(reopened.preferences.theme, 'dark');
    expect(reopened.preferences.notificationsEnabled, isTrue);
    expect(() => reopened.players.clear(), throwsUnsupportedError);
  });

  test('名前の重複を拒否し過去の記録を変更しない', () async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    await store.saveEvent(_event(['A', 'B']));
    final before = storage.contents;
    await expectLater(store.savePlayer(store.players.first.copyWith(name: 'Ｂ')), throwsFormatException);
    expect(storage.contents, before);
    expect(store.events.single.participants, ['A', 'B']);
  });

  test('プレイヤー情報を削除しても過去の参加者名を保持する', () async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.saveEvent(_event(['プレイヤー']));
    await store.deletePlayer(store.players.single.id);
    expect(store.players, isEmpty);
    expect(store.events.single.participants, ['プレイヤー']);
    expect(store.playerDirectory.single.name, 'プレイヤー');
  });

  test('バックアップは会・メモ・プレイヤー・設定を丸ごと復元する', () async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.saveEvent(_event(['田中']));
    await store.savePlayer(store.players.single.copyWith(furigana: 'たなか'));
    await store.savePreferences(store.preferences.copyWith(theme: 'system'));
    await store.saveNote(ThoughtNote(id: 'note', title: '回答', kind: NoteKind.answers, createdAt: DateTime(2026), updatedAt: DateTime(2026), body: '残す本文', eventId: 'event'));
    await store.recordBackupExported();
    final restored = GiriStore(storage: MemoryGiriStorage());
    await restored.load();
    await restored.restoreBackup(store.exportBackup());
    expect(restored.events.single.participants, ['田中']);
    expect(restored.notes.single.body, '残す本文');
    expect(restored.players.single.furigana, 'たなか');
    expect(restored.preferences.theme, 'system');
    expect(restored.lastBackupAt, isNotNull);
  });

  test('壊れたバックアップと書込失敗で現在データを失わない', () async {
    final storage = _FailingStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    await store.saveEvent(_event(['田中']));
    final before = storage.contents;
    final corrupt = jsonDecode(store.exportBackup()) as Map<String, dynamic>;
    corrupt['players'] = [{'id': 'broken'}];
    await expectLater(store.restoreBackup(jsonEncode(corrupt)), throwsFormatException);
    expect(storage.contents, before);
    expect(store.events.single.title, '会');
    final backup = jsonDecode(store.exportBackup()) as Map<String, dynamic>;
    backup['events'] = [];
    storage.fail = true;
    await expectLater(store.restoreBackup(jsonEncode(backup)), throwsA(isA<FileSystemException>()));
    expect(store.events.single.title, '会');
    expect(storage.contents, before);
    storage.fail = false;
    await store.savePreferences(store.preferences.copyWith(theme: 'dark'));
    expect(store.events.single.title, '会');
  });

  test('新規設定の破損を検出し空データで上書きしない', () async {
    final storage = MemoryGiriStorage(jsonEncode({
      'schemaVersion': 1, 'events': [], 'notes': [],
      'preferences': {'notificationsEnabled': 'yes'},
    }));
    final original = storage.contents;
    final store = GiriStore(storage: storage);
    await expectLater(store.load(), throwsFormatException);
    expect(store.loaded, isFalse);
    await expectLater(store.savePreferences(const AppPreferences()), throwsStateError);
    expect(storage.contents, original);
  });
}
