import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';

void main() {
  final start = DateTime.utc(2026, 10, 27, 9);
  final end = DateTime.utc(2026, 10, 28, 9);

  GiriEvent onlineEvent({EventStatus status = EventStatus.planned}) =>
      GiriEvent(
        id: 'online-1',
        title: 'ネット大会',
        kind: EventKind.online,
        meetingType: MeetingType.tournament,
        createdAt: start,
        submissionStart: start,
        submissionEnd: end,
        status: status,
      );

  test('投稿期間は開始を含み、終了は含まない', () {
    final event = onlineEvent();
    expect(
      event.isSubmissionOpen(start.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(event.isSubmissionOpen(start), isTrue);
    expect(event.isSubmissionOpen(end), isFalse);
    expect(
      onlineEvent(status: EventStatus.canceled).isSubmissionOpen(start),
      isFalse,
    );
    expect(
      event.copyWith(kind: EventKind.live).isSubmissionOpen(start),
      isFalse,
    );
    expect(
      event.copyWith(submissionStart: null).isSubmissionOpen(start),
      isFalse,
    );
    expect(
      event.copyWith(submissionEnd: null).isSubmissionOpen(start),
      isFalse,
    );
  });

  test('端末の日時設定に依存せず記録した瞬間を復元する', () {
    final event = onlineEvent().copyWith(
      participants: ['プレイヤーA', 'プレイヤーB'],
      resultText: '準決勝敗退',
      placement: 4,
      votingStart: end,
      votingEnd: end.add(const Duration(days: 1)),
    );
    final restored = GiriEvent.fromJson(event.toJson());
    expect(restored.submissionStart!.isAtSameMomentAs(start), isTrue);
    expect(restored.submissionEnd!.isAtSameMomentAs(end), isTrue);
    expect(restored.participants, ['プレイヤーA', 'プレイヤーB']);
    expect(restored.resultText, '準決勝敗退');
    expect(restored.placement, 4);
    expect(restored.copyWith(placement: null).placement, isNull);
    expect(restored.copyWith(title: '修正').placement, 4);
  });

  test('参加者の元リストや公開されたリストから記録を変更できない', () {
    final participants = ['プレイヤーA'];
    final event = onlineEvent().copyWith(participants: participants);
    participants.add('元リストへの追記');
    expect(event.participants, ['プレイヤーA']);
    expect(() => event.participants.add('追記'), throwsUnsupportedError);
  });

  test('未保存の任意項目は初期値で読み込み、未知の種別は拒否する', () {
    final record = <String, dynamic>{
      'id': 'live-1',
      'title': '通常会',
      'kind': 'live',
      'meetingType': 'casual',
      'createdAt': start.toIso8601String(),
    };
    final event = GiriEvent.fromJson(record);
    expect(event.status, EventStatus.planned);
    expect(event.resultText, isEmpty);
    expect(event.participants, isEmpty);
    expect(event.startsAt, isNull);
    expect(event.eventDate, isNull);
    expect(
      () => GiriEvent.fromJson({...record, 'kind': 'future-kind'}),
      throwsFormatException,
    );
    expect(
      () => GiriEvent.fromJson({...record, 'startsAt': 'invalid'}),
      throwsFormatException,
    );
  });

  test('時刻未定の開催日を時差変換せず保存し、日時と区別する', () {
    final day = DateTime.utc(2026, 10, 28);
    final event = GiriEvent(
      id: 'date-only',
      title: '時刻未定の通常会',
      kind: EventKind.live,
      meetingType: MeetingType.casual,
      createdAt: start,
      eventDate: day,
    );
    final json = event.toJson();
    expect(json['eventDate'], '2026-10-28');
    expect(json['startsAt'], isNull);
    expect(json['endsAt'], isNull);
    final restored = GiriEvent.fromJson(json);
    expect(restored.eventDate, DateTime(2026, 10, 28));
    expect(restored.startsAt, isNull);
    expect(restored.endsAt, isNull);
    expect(restored.copyWith(title: '改題').eventDate, restored.eventDate);
    expect(restored.copyWith(eventDate: null).eventDate, isNull);

    final timed = restored.copyWith(startsAt: end);
    final timedRestored = GiriEvent.fromJson(timed.toJson());
    expect(timedRestored.eventDate, DateTime(2026, 10, 28));
    expect(timedRestored.startsAt!.isAtSameMomentAs(end), isTrue);
  });

  test('存在しない開催日や日時形式の値を開催日として読み込まない', () {
    final json = onlineEvent().toJson();
    for (final invalid in [
      '2026-02-29',
      '2026-13-01',
      '2026-10-00',
      '2026-10-28T09:00:00Z',
      '2026-1-2',
      20261028,
    ]) {
      expect(
        () => GiriEvent.fromJson({...json, 'eventDate': invalid}),
        throwsFormatException,
      );
    }
    expect(
      GiriEvent.fromJson({...json, 'eventDate': '2028-02-29'}).eventDate,
      DateTime(2028, 2, 29),
    );
  });

  test('メモの会への関連付けだけ解除して内容を保持できる', () {
    final note = ThoughtNote(
      id: 'note-1',
      title: '回答案',
      kind: NoteKind.answers,
      createdAt: start,
      updatedAt: end,
      body: '回答案1\n回答案2',
      eventId: 'online-1',
    );
    final restored = ThoughtNote.fromJson(note.toJson());
    final unlinked = restored.copyWith(eventId: null);
    expect(unlinked.eventId, isNull);
    expect(unlinked.body, note.body);
    expect(unlinked.kind, NoteKind.answers);
    expect(restored.copyWith(title: '回答').eventId, 'online-1');
  });
}
