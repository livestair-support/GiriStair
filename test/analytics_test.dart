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

  test(
    'current co-participants include both formats and exclude the normalized self name',
    () {
      final stats = GiriAnalytics([
        event('live', participants: [' A ', 'B', 'B']),
        event('online', kind: EventKind.online, participants: ['Ａ', 'B', 'C']),
        event(
          'notJoined',
          participants: ['D'],
        ).copyWith(isParticipating: false),
      ], selfName: 'Ａ');
      expect(stats.attended.length, 2);
      expect(stats.participants, hasLength(1));
      expect(stats.participants.single.key, 'B');
      expect(stats.participants.single.value, 1);
      expect(stats.coParticipants.map((entry) => entry.key), ['B', 'C']);
      expect(stats.coParticipants.map((entry) => entry.value), [2, 1]);
    },
  );

  test('team rosters contribute once per event without becoming opponents', () {
    final stats = GiriAnalytics([
      event('team', kind: EventKind.online, participants: ['自分', 'B']).copyWith(
        teams: [
          GiriTeam(id: 'team', name: 'チーム', members: ['自分', 'B', 'C']),
        ],
        tournamentResult: TournamentResult(
          format: TournamentFormat.team,
          members: ['自分', 'D'],
        ),
      ),
    ], selfName: '自分');
    expect(stats.coParticipants.map((entry) => entry.key), ['B', 'C', 'D']);
    expect(stats.coParticipants.every((entry) => entry.value == 1), isTrue);
    expect(stats.firstPlaceCount, 0);
    expect(stats.participants, isEmpty);
  });

  test(
    'year month format and meeting filters apply to the same attended set',
    () {
      final stats = GiriAnalytics(
        [
          event('live', date: DateTime(2026, 2)),
          event(
            'networkTournament',
            kind: EventKind.online,
            date: DateTime(2026, 2),
          ),
          event(
            'networkOrdinary',
            kind: EventKind.online,
            date: DateTime(2026, 2),
          ).copyWith(meetingType: MeetingType.casual),
          event(
            'differentMonth',
            kind: EventKind.online,
            date: DateTime(2026, 3),
          ).copyWith(meetingType: MeetingType.casual),
          event(
            'undated',
            kind: EventKind.online,
          ).copyWith(meetingType: MeetingType.casual),
        ],
        year: 2026,
        month: 2,
        kind: EventKind.online,
        meetingType: MeetingType.casual,
      );
      expect(stats.attended.single.id, 'networkOrdinary');
      expect(stats.live, isEmpty);
      expect(stats.online.length, 1);
      expect(stats.casual.length, 1);
      expect(stats.tournaments, isEmpty);
      expect(stats.monthly.single.month, DateTime(2026, 2));
    },
  );

  test(
    'other standings and stage wins do not become the users final prizes',
    () {
      final stats = GiriAnalytics([
        event('winner').copyWith(
          tournamentResult: TournamentResult(
            outcome: TournamentOutcome.champion,
          ),
        ),
        event('runnerUp').copyWith(
          tournamentResult: TournamentResult(
            outcome: TournamentOutcome.runnerUp,
          ),
        ),
        event('explicitPrize', placement: 8).copyWith(
          tournamentResult: TournamentResult(outcome: TournamentOutcome.placed),
        ),
        event('third', placement: 3),
        event('stageOnly').copyWith(
          tournamentResult: TournamentResult(
            stages: [
              const ResultStage(
                id: 'q',
                name: '予選',
                outcome: TournamentOutcome.champion,
              ),
            ],
          ),
        ),
        event('someoneElse').copyWith(
          standings: [
            TournamentStanding(
              id: 'winner',
              placement: 1,
              playerNames: ['別の人'],
            ),
          ],
        ),
      ]);
      expect(stats.firstPlaceCount, 1);
      expect(stats.runnerUpCount, 1);
      expect(stats.placedCount, 2);
      expect(stats.podiumCount, 3);
    },
  );

  test(
    'site cycles aggregate by their registered name and monthly format counts stay separate',
    () {
      final stats = GiriAnalytics(
        [
          event(
            'thisWeek',
            kind: EventKind.online,
            date: DateTime(2026, 6, 10),
          ).copyWith(onlineSiteId: 'site'),
          event(
            'nextWeek',
            kind: EventKind.online,
            date: DateTime(2026, 7, 1),
          ).copyWith(onlineSiteId: 'site'),
          event(
            'notJoined',
            kind: EventKind.online,
            date: DateTime(2026, 7, 15),
          ).copyWith(onlineSiteId: 'site', isParticipating: false),
          event('live', date: DateTime(2026, 6, 20)),
          event('undated'),
        ],
        siteNames: {'site': '継続サイト'},
      );
      expect(stats.sites.single.key, '継続サイト');
      expect(stats.sites.single.value, 2);
      expect(stats.undatedCount, 1);
      expect(stats.monthly.map((month) => month.month), [
        DateTime(2026, 6),
        DateTime(2026, 7),
      ]);
      expect(stats.monthly.first.live, 1);
      expect(stats.monthly.first.online, 1);
      expect(stats.monthly.first.total, 2);
      expect(stats.monthly.last.total, 1);
      expect(GiriAnalytics(stats.attended, year: 2026).monthly, hasLength(12));
    },
  );
}
