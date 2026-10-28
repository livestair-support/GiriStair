import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/tournament_presentation.dart';

void main() {
  GiriEvent event({TournamentResult? result, String legacy = '', int? rank}) =>
      GiriEvent(
        id: 'tournament',
        title: '大会',
        kind: EventKind.live,
        meetingType: MeetingType.tournament,
        createdAt: DateTime(2026),
        tournamentResult: result,
        resultText: legacy,
        placement: rank,
      );

  test('shows final outcome separately from stage wins and legacy notes', () {
    final record = event(
      result: TournamentResult(
        outcome: TournamentOutcome.eliminated,
        stages: [
          const ResultStage(
            id: 'qualifier',
            name: '予選',
            outcome: TournamentOutcome.advanced,
            placement: 2,
            memo: '敗者復活から本戦へ',
          ),
        ],
      ),
      legacy: '予選で優勝',
      rank: 1,
    );
    expect(tournamentResultSummary(record), '敗退 · 予選で優勝');
    expect(
      resultStageSummary(record.tournamentResult!.stages.single),
      '通過 · 2位 · 敗者復活から本戦へ',
    );
  });

  test(
    'championship has a single clear label and keeps old free-form notes',
    () {
      expect(
        tournamentResultSummary(
          event(result: TournamentResult(outcome: TournamentOutcome.champion)),
        ),
        '優勝',
      );
      expect(
        tournamentResultSummary(event(rank: 3, legacy: '決勝3位')),
        '3位 · 決勝3位',
      );
      expect(tournamentFormatLabel(TournamentFormat.pair), 'タッグ戦');
      expect(tournamentFormatLabel(TournamentFormat.team), 'チーム戦');
    },
  );
}
