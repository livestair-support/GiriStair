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

  test('複数ラウンドの投稿期間を個別に判定し古い期間と二重にしない', () {
    final rounds = [
      EventRound(id: 'prelim', name: '予選1回戦',
        submissionStart: start, submissionEnd: end,
        votingStart: end, votingEnd: end.add(const Duration(days: 7))),
      EventRound(id: 'final', name: '決勝',
        submissionStart: end.add(const Duration(days: 7)),
        submissionEnd: end.add(const Duration(days: 14))),
    ];
    final event = onlineEvent().copyWith(rounds: rounds);
    rounds.clear();
    expect(event.rounds.length, 2);
    expect(event.isSubmissionOpen(start), isTrue);
    expect(event.isSubmissionOpen(end), isFalse);
    expect(event.isSubmissionOpen(end.add(const Duration(days: 7))), isTrue);
    expect(event.nextSubmissionEnd(start), end);
    expect(event.nextSubmissionEnd(end), isNull);
    expect(event.copyWith(status: EventStatus.canceled).isSubmissionOpen(start), isFalse);
    expect(event.copyWith(kind: EventKind.live).isSubmissionOpen(start), isFalse);
    final restored = GiriEvent.fromJson(event.toJson());
    expect(restored.rounds.map((round) => round.id), ['prelim', 'final']);
    expect(restored.rounds.last.submissionStart!.isAtSameMomentAs(end.add(const Duration(days: 7))), isTrue);
    expect(() => event.rounds.clear(), throwsUnsupportedError);
    expect(onlineEvent().effectiveRounds.single.id, 'legacy');
    final futureOnly = event.copyWith(rounds: [event.rounds.last]);
    expect(futureOnly.isSubmissionOpen(start), isFalse);
  });

  test('ラウンドの改名や日時削除で識別子を保持する', () {
    final round = EventRound(id: 'round-1', name: '予選', submissionStart: start, submissionEnd: end);
    final changed = round.copyWith(name: '予選2回戦', submissionStart: null);
    expect(changed.id, round.id);
    expect(changed.submissionStart, isNull);
    expect(changed.submissionEnd, end);
  });

  test('大会全体の戦績を途中のステージ結果や自由文から推測しない', () {
    final result = TournamentResult(
      format: TournamentFormat.team,
      teamName: 'チームA',
      members: ['A', 'B'],
      outcome: TournamentOutcome.eliminated,
      stages: [const ResultStage(id: 'qualifier', name: '予選', outcome: TournamentOutcome.champion, placement: 1, memo: '予選優勝')],
      memo: '本戦で敗退',
    );
    final event = onlineEvent().copyWith(resultText: '予選優勝', placement: 1, tournamentResult: result);
    final restored = GiriEvent.fromJson(event.toJson());
    expect(restored.hasRecordedResult, isTrue);
    expect(restored.effectivePlacement, isNull);
    expect(restored.tournamentResult!.teamName, 'チームA');
    expect(restored.tournamentResult!.members, ['A', 'B']);
    expect(restored.tournamentResult!.stages.single.placement, 1);
    expect(event.copyWith(tournamentResult: result.copyWith(outcome: TournamentOutcome.champion)).effectivePlacement, 1);
    expect(event.copyWith(tournamentResult: result.copyWith(outcome: TournamentOutcome.runnerUp)).effectivePlacement, 2);
    expect(event.copyWith(tournamentResult: result.copyWith(outcome: TournamentOutcome.advanced)).effectivePlacement, isNull);
    expect(event.copyWith(tournamentResult: null).resultText, '予選優勝');
    expect(() => result.members.add('C'), throwsUnsupportedError);
    expect(() => result.stages.clear(), throwsUnsupportedError);
  });

  test('お題・回答案・使用済み状態とラウンドの関連を保存する', () {
    final answers = ['回答1', '回答2'];
    final note = ThoughtNote(id: 'topic', title: '', kind: NoteKind.answers,
      createdAt: start, updatedAt: end, eventId: 'online-1', roundId: 'qualifier',
      prompt: 'こんな大会はいやだ', answers: answers, used: true, body: '古い本文');
    answers.clear();
    final restored = ThoughtNote.fromJson(note.toJson());
    expect(restored.prompt, note.prompt);
    expect(restored.answers, ['回答1', '回答2']);
    expect(restored.used, isTrue);
    expect(restored.roundId, 'qualifier');
    final unlinked = restored.copyWith(eventId: null, roundId: null);
    expect(unlinked.eventId, isNull);
    expect(unlinked.roundId, isNull);
    expect(unlinked.answers, restored.answers);
    expect(unlinked.body, '古い本文');
    expect(() => restored.answers.clear(), throwsUnsupportedError);
    final oldJson = Map<String, dynamic>.of(note.toJson())
      ..remove('prompt')..remove('answers')..remove('roundId')..remove('used');
    final old = ThoughtNote.fromJson(oldJson);
    expect(old.prompt, isEmpty);
    expect(old.answers, isEmpty);
    expect(old.roundId, isNull);
    expect(old.used, isFalse);
    expect(old.body, note.body);
  });

  test('追加された構造化項目の不正値を空データへ変換しない', () {
    final event = onlineEvent().toJson();
    final round = const EventRound(id: 'round', name: '予選').toJson();
    for (final invalid in [42, ['broken'], [round, round]]) {
      expect(() => GiriEvent.fromJson({...event, 'rounds': invalid}), throwsFormatException);
    }
    expect(() => GiriEvent.fromJson({...event, 'tournamentResult': 'broken'}), throwsFormatException);
    expect(() => TournamentResult.fromJson({'outcome': 'future-outcome'}), throwsFormatException);
    expect(() => ResultStage.fromJson({'id': 'stage', 'name': '予選', 'placement': 0}), throwsFormatException);
    final note = ThoughtNote(id: 'note', title: '', kind: NoteKind.prompts, createdAt: start, updatedAt: end).toJson();
    for (final value in [1, 'true']) {
      expect(() => ThoughtNote.fromJson({...note, 'used': value}), throwsFormatException);
    }
    expect(() => ThoughtNote.fromJson({...note, 'answers': [1]}), throwsFormatException);
    expect(() => ThoughtNote.fromJson({...note, 'roundId': 1}), throwsFormatException);
  });

}
