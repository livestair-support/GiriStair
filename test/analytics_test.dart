import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/analytics.dart';
import 'package:giristair/models.dart';

void main() {
  GiriEvent event(
    String id, {
    EventStatus status = EventStatus.attended,
    EventKind kind = EventKind.live,
    DateTime? date,
    int? placement,
    String result = '',
    List<String> participants = const [],
    String venue = '',
  }) => GiriEvent(
    id: id,
    title: id,
    kind: kind,
    meetingType: MeetingType.tournament,
    createdAt: DateTime(2026),
    status: status,
    eventDate: kind == EventKind.live ? date : null,
    submissionEnd: kind == EventKind.online ? date : null,
    placement: placement,
    resultText: result,
    participants: participants,
    venue: venue,
  );

  test(
    'rankings count attended events and dedupe each participant per event',
    () {
      final analytics = GiriAnalytics([
        event('a', participants: [' A ', 'A', 'B'], venue: ' 会場 '),
        event('b', participants: ['A'], venue: '会場'),
        event('planned', status: EventStatus.planned, participants: ['A']),
        event('canceled', status: EventStatus.canceled, participants: ['A']),
        event('online', kind: EventKind.online, participants: ['A']),
      ]);
      expect(analytics.attended.length, 3);
      expect(analytics.live.length, 2);
      expect(analytics.online.length, 1);
      expect(analytics.participants.first.key, 'A');
      expect(analytics.participants.first.value, 2);
      expect(analytics.venues.single.value, 2);
    },
  );

  test(
    'year uses actual event dates and excludes undated events only in filter',
    () {
      final events = [
        event('old', date: DateTime(2025, 12, 31)),
        event('live', date: DateTime(2026, 1, 1)),
        event('online', kind: EventKind.online, date: DateTime(2026, 4)),
        event('unknown'),
      ];
      expect(GiriAnalytics(events).attended.length, 4);
      expect(GiriAnalytics(events, year: 2026).attended.length, 2);
      expect(GiriAnalytics.yearsOf(events), [2026, 2025]);
    },
  );

  test('only explicit positive rank is counted as a placing', () {
    final analytics = GiriAnalytics([
      event('first', placement: 1),
      event('third', placement: 3),
      event('text', result: '優勝には届かず'),
      event('missing'),
      event('invalid', placement: 0),
    ]);
    expect(analytics.ranked.length, 2);
    expect(analytics.firstPlaceCount, 1);
    expect(analytics.podiumCount, 2);
    expect(analytics.resultCount, 3);
  });

  test(
    'final outcome counts once and stage wins never become tournament wins',
    () {
      final analytics = GiriAnalytics([
        event('champion').copyWith(
          tournamentResult: TournamentResult(
            format: TournamentFormat.team,
            outcome: TournamentOutcome.champion,
            teamName: 'チーム',
            stages: [
              const ResultStage(
                id: 'q',
                name: '予選',
                outcome: TournamentOutcome.champion,
              ),
              const ResultStage(
                id: 'f',
                name: '決勝',
                outcome: TournamentOutcome.champion,
              ),
            ],
          ),
        ),
        event('runnerUp').copyWith(
          tournamentResult: TournamentResult(
            outcome: TournamentOutcome.runnerUp,
          ),
        ),
        event('stageWin', placement: 1).copyWith(
          tournamentResult: TournamentResult(
            outcome: TournamentOutcome.eliminated,
            stages: [
              const ResultStage(
                id: 'q',
                name: '予選',
                outcome: TournamentOutcome.champion,
              ),
              const ResultStage(
                id: 'f',
                name: '本戦',
                outcome: TournamentOutcome.eliminated,
              ),
            ],
          ),
        ),
        event('prose', result: '予選優勝、決勝敗退'),
        event('missing'),
      ]);
      expect(analytics.firstPlaceCount, 1);
      expect(analytics.podiumCount, 2);
      expect(analytics.ranked.length, 2);
      expect(analytics.resultCount, 4);
    },
  );

  test(
    'online year follows the final scheduled round rather than stale legacy dates',
    () {
      final online =
          event(
            'rounds',
            kind: EventKind.online,
            date: DateTime(2025),
          ).copyWith(
            rounds: [
              EventRound(
                id: 'q',
                name: '予選',
                submissionEnd: DateTime(2026, 12, 30),
              ),
              EventRound(id: 'f', name: '決勝', votingEnd: DateTime(2027, 1, 3)),
            ],
          );
      expect(GiriAnalytics.dateOf(online), DateTime(2027, 1, 3));
      expect(GiriAnalytics([online], year: 2027).attended.length, 1);
      expect(GiriAnalytics([online], year: 2025).attended, isEmpty);
    },
  );
}
