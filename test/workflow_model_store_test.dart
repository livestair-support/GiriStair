import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/scheduling.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';

class _Storage extends MemoryGiriStorage {
  bool fail = false;

  @override
  Future<void> write(String contents) async {
    if (fail) throw const FileSystemException('No space');
    await super.write(contents);
  }
}

GiriEvent _event({
  String organizer = '',
  List<String> participants = const [],
}) => GiriEvent(
  id: 'event',
  title: '大会',
  kind: EventKind.online,
  meetingType: MeetingType.tournament,
  createdAt: DateTime(2026, 10, 29),
  organizer: organizer,
  participants: participants,
);

void main() {
  test(
    'old backups retain legacy teams and acquire optional workflow defaults',
    () {
      final old = <String, dynamic>{
        'id': 'old',
        'title': '旧大会',
        'kind': 'online',
        'meetingType': 'tournament',
        'createdAt': '2026-10-28T09:00:00Z',
        'tournamentResult': {
          'format': 'team',
          'teamName': '旧チーム',
          'members': ['本人', '仲間'],
        },
      };
      final event = GiriEvent.fromJson(old);
      expect(event.tournamentFormat, TournamentFormat.team);
      expect(event.tournamentResult!.members, ['本人', '仲間']);
      expect(event.onlineSiteId, isNull);
      expect(event.teams, isEmpty);
      expect(event.standings, isEmpty);
      expect(event.isParticipating, isTrue);
      final preferences = AppPreferences.fromJson({'theme': 'light'});
      expect(preferences.submissionStartDayOffset, -1);
      expect(preferences.submissionStartHour, 22);
      expect(preferences.submissionDays, 7);
      expect(preferences.votingDays, 7);
    },
  );

  test('missing or invalid whole-tournament placement cannot become a win', () {
    for (final rank in [null, 0, -1, '1', 1.5]) {
      expect(
        () =>
            TournamentStanding.fromJson({'id': 'standing', 'placement': rank}),
        throwsFormatException,
      );
    }
    final standing = TournamentStanding.fromJson({
      'id': 'standing',
      'placement': 2,
      'playerNames': ['準優勝者'],
    });
    expect(standing.placement, 2);
  });

  test(
    'weighted scoring uses all available points and survives numeric JSON',
    () {
      final stage = ResultStage.fromJson({
        'id': 'score',
        'name': 'お題1',
        'points': 12,
        'voterCount': 10,
        'maxPointsPerVoter': 3,
      });
      expect(stage.points, 12.0);
      expect(stage.voteRate, 40.0);
      expect(stage.copyWith(points: 6).voteRate, 20.0);
      expect(stage.copyWith(points: null).voteRate, isNull);
      expect(stage.copyWith(voterCount: 0).voteRate, isNull);
      expect(stage.copyWith(voterCount: null).voteRate, isNull);
      expect(stage.copyWith(name: '訂正').maxPointsPerVoter, 3);
      expect(
        const ResultStage(id: 'draft', name: '人数のみ', voterCount: 0).hasRecord,
        isTrue,
      );
      expect(
        const ResultStage(
          id: 'draft',
          name: '配点のみ',
          maxPointsPerVoter: 3,
        ).hasRecord,
        isTrue,
      );
      for (final invalid in [double.nan, double.infinity, -1]) {
        expect(
          () => ResultStage.fromJson({...stage.toJson(), 'points': invalid}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'multiple prompts share a stable stage while results remain independent',
    () {
      final start = DateTime(2026, 10, 28, 22);
      final first = completeRoundSchedule(
        EventRound(
          id: 'prompt-1',
          name: '予選1回戦',
          block: 'A',
          submissionStart: start,
        ),
      );
      final second = addNextRound(
        first,
        id: 'prompt-2',
        sameStage: true,
        defaultStart: start,
      );
      expect(second.effectiveStageId, first.id);
      expect(second.promptNumber, 2);
      expect(second.name, '予選1回戦');
      expect(second.block, 'A');
      expect(second.submissionStart, first.votingEnd);
      final renamed = first.copyWith(name: '予選A');
      expect(renamed.effectiveStageId, second.effectiveStageId);
      expect(first.copyWith(id: 'copied').id, 'copied');
      final nextStage = addNextRound(
        second,
        id: 'next-stage',
        defaultStart: start,
      );
      expect(nextStage.effectiveStageId, 'next-stage');
      expect(nextStage.promptNumber, 1);
      expect(nextStage.name, '予選2回戦');
      final event = _event().copyWith(
        rounds: [first, second, nextStage],
        tournamentResult: TournamentResult(
          stages: [
            ResultStage(
              id: 'stage-result',
              name: '予選1回戦',
              stageId: first.effectiveStageId,
              outcome: TournamentOutcome.advanced,
              placement: 1,
            ),
          ],
        ),
      );
      expect(event.hasRecordedResult, isTrue);
      expect(event.hasFinalResult, isFalse);
      expect(event.effectivePlacement, isNull);
    },
  );

  test(
    'schedule derivation fills only missing fields and preserves manual dates',
    () {
      final start = DateTime(2026, 10, 28, 22);
      final round = EventRound(
        id: 'round',
        name: '投稿・投票',
        submissionStart: start,
      );
      final complete = completeRoundSchedule(round);
      expect(complete.submissionEnd, DateTime(2026, 11, 4, 22));
      expect(complete.votingStart, complete.submissionEnd);
      expect(complete.votingEnd, DateTime(2026, 11, 11, 22));
      final manual = complete.copyWith(
        submissionStart: DateTime(2026, 10, 30, 12),
        submissionEnd: DateTime(2026, 11, 3, 18),
        votingStart: DateTime(2026, 11, 5, 20),
        votingEnd: null,
      );
      final recomputed = completeRoundSchedule(manual, votingDays: 3);
      expect(recomputed.submissionEnd, manual.submissionEnd);
      expect(recomputed.votingStart, manual.votingStart);
      expect(recomputed.votingEnd, DateTime(2026, 11, 8, 20));
      expect(
        completeRoundSchedule(
          round.copyWith(submissionStart: null),
        ).submissionEnd,
        isNull,
      );
      expect(
        defaultSubmissionStart(DateTime(2026, 11, 1), const AppPreferences()),
        DateTime(2026, 10, 31, 22),
      );
      expect(
        addCalendarDays(DateTime.utc(2026, 12, 31, 22), 1),
        DateTime.utc(2027, 1, 1, 22),
      );
      expect(
        fiveMinuteSelection(DateTime.utc(2026, 10, 29, 12, 7)).isUtc,
        isTrue,
      );
    },
  );

  test(
    'elimination can disable posting while the required vote remains open',
    () {
      final now = DateTime(2026, 10, 29, 22);
      final round = EventRound(
        id: 'vote-only',
        name: '決勝',
        submissionEnabled: false,
        submissionStart: now.subtract(const Duration(days: 7)),
        submissionEnd: now.add(const Duration(days: 7)),
        votingStart: now,
        votingEnd: now.add(const Duration(days: 7)),
      );
      expect(round.isSubmissionOpen(now), isFalse);
      expect(round.isVotingOpen(now), isTrue);
      expect(round.copyWith(votingRequired: false).isVotingOpen(now), isFalse);
    },
  );

  test('weekly site cycles share the calendar Sunday boundary', () {
    const sunday = OnlineSite(
      id: 'sunday',
      name: '日曜開催',
      recurrence: SiteRecurrence.weekly,
      weekday: DateTime.sunday,
    );
    final saturday = DateTime(2026, 10, 31, 23, 55);
    final nextSunday = DateTime(2026, 11, 1, 0, 5);
    expect(siteCycleStart(sunday, saturday), DateTime(2026, 10, 25, 22));
    expect(
      siteCycleStart(sunday, saturday, weekOffset: 1),
      DateTime(2026, 11, 1, 22),
    );
    expect(siteCycleStart(sunday, nextSunday), DateTime(2026, 11, 1, 22));
    expect(
      siteCycleStart(sunday, DateTime(2026, 11, 2)),
      DateTime(2026, 11, 1, 22),
    );
    expect(
      siteCycleStart(sunday.copyWith(weekday: DateTime.monday), nextSunday),
      DateTime(2026, 11, 2, 22),
    );
    expect(
      siteCycleStart(sunday, DateTime.utc(2026, 11, 1)),
      DateTime.utc(2026, 11, 1, 22),
    );
  });

  test(
    'venue maps accept negative coordinates, retain identity and clear as a pair',
    () {
      final venue = GiriVenue.fromJson({
        'id': 'venue',
        'name': '会場',
        'latitude': -33.86,
        'longitude': 151.2,
        'mapAddress': '住所',
      });
      final restored = GiriVenue.fromJson(venue.copyWith(name: '改名').toJson());
      expect(restored.latitude, -33.86);
      expect(restored.longitude, 151.2);
      expect(restored.mapAddress, '住所');
      expect(restored.id, 'venue');
      expect(venue.copyWith(latitude: null, longitude: null).latitude, isNull);
      for (final changes in [
        {'latitude': 91.0},
        {'longitude': -181.0},
        {'latitude': double.nan},
        {'latitude': null},
      ]) {
        expect(
          () => GiriVenue.fromJson({...venue.toJson(), ...changes}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'site cycle creation serializes duplicates and joins an existing preview atomically',
    () async {
      final storage = _Storage();
      final store = GiriStore(storage: storage);
      await store.load();
      await store.savePreferences(const AppPreferences(selfName: '本人'));
      await store.saveOnlineSite(
        const OnlineSite(
          id: 'site',
          name: '継続サイト',
          recurrence: SiteRecurrence.weekly,
          weekday: DateTime.thursday,
          affiliation: '一部',
          block: 'お題A',
        ),
      );
      final week = DateTime(2026, 10, 29);
      final previews = await Future.wait([
        store.createSiteCycle('site', weekOf: week, join: false),
        store.createSiteCycle('site', weekOf: week, join: false),
      ]);
      expect(previews.first.id, previews.last.id);
      expect(store.events.length, 1);
      expect(store.events.single.isParticipating, isFalse);
      final before = storage.contents;
      storage.fail = true;
      await expectLater(
        store.createSiteCycle('site', weekOf: week),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.events.single.isParticipating, isFalse);
      expect(storage.contents, before);
      storage.fail = false;
      final joined = await store.createSiteCycle('site', weekOf: week);
      expect(joined.id, previews.first.id);
      expect(joined.isParticipating, isTrue);
      expect(joined.participants, ['本人']);
      expect(joined.affiliation, '一部');
      expect(joined.block, 'お題A');
      expect(joined.rounds.single.submissionStart, DateTime(2026, 10, 29, 22));
      final reopened = GiriStore(storage: storage);
      await reopened.load();
      expect(reopened.events.single.isParticipating, isTrue);
      await reopened.createSiteCycle('site', weekOf: week);
      expect(reopened.events.single.participants, ['本人']);
    },
  );

  test(
    'self-profile onboarding and initial player are one durable mutation',
    () async {
      final storage = _Storage();
      final store = GiriStore(storage: storage);
      await store.load();
      storage.fail = true;
      await expectLater(
        store.savePreferences(
          const AppPreferences(selfName: '本人', onboardingCompleted: true),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.preferences.onboardingCompleted, isFalse);
      expect(store.players, isEmpty);
      storage.fail = false;
      await store.savePreferences(
        const AppPreferences(selfName: '本人', onboardingCompleted: true),
      );
      expect(store.players.single.name, '本人');
      final reopened = GiriStore(storage: storage);
      await reopened.load();
      expect(reopened.preferences.selfName, '本人');
      expect(reopened.players.single.name, '本人');
    },
  );

  test(
    'player rename follows hosts, own team and podium without changing results',
    () async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await store.savePreferences(const AppPreferences(selfName: '本人'));
      await store.saveEvent(
        _event(organizer: '本人', participants: ['本人', '仲間']).copyWith(
          teams: [
            GiriTeam(
              id: 'own',
              name: 'チーム',
              members: ['本人', '仲間'],
              isMine: true,
            ),
          ],
          myTeamId: 'own',
          standings: [
            TournamentStanding(
              id: 'podium',
              placement: 1,
              playerNames: ['本人', '仲間'],
            ),
          ],
          tournamentResult: TournamentResult(
            format: TournamentFormat.team,
            members: ['本人', '仲間'],
          ),
        ),
      );
      final self = store.playerByName('本人')!;
      await store.savePlayer(self.copyWith(name: '新しい名前', region: '東京'));
      final saved = store.events.single;
      expect(store.preferences.selfName, '新しい名前');
      expect(saved.organizer, '新しい名前');
      expect(saved.participants, ['新しい名前', '仲間']);
      expect(saved.teams.single.members, ['新しい名前', '仲間']);
      expect(saved.standings.single.playerNames, ['新しい名前', '仲間']);
      expect(saved.standings.single.placement, 1);
      expect(saved.tournamentResult!.members, ['新しい名前', '仲間']);
      expect(store.playerByName('新しい名前')!.region, '東京');
    },
  );

  test(
    'history venue promotion preserves its map and updates only matching events',
    () async {
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await store.saveEvent(_event().copyWith(venue: '旧会場'));
      final history = store.venueDirectory.single;
      await store.saveVenue(
        history.copyWith(
          name: '新会場',
          prefecture: '東京都',
          latitude: 35.68,
          longitude: 139.76,
          mapAddress: '住所',
        ),
      );
      final venue = store.venues.single;
      expect(venue.id, isNot(startsWith('history:')));
      expect(venue.latitude, 35.68);
      expect(venue.longitude, 139.76);
      expect(venue.mapAddress, '住所');
      expect(store.events.single.venue, '新会場');
      expect(store.events.single.venueId, venue.id);
    },
  );

  test(
    'a malformed standings backup is rejected without replacing saved records',
    () async {
      final storage = MemoryGiriStorage();
      final store = GiriStore(storage: storage);
      await store.load();
      await store.saveEvent(_event());
      final contents = storage.contents;
      final corrupt = jsonDecode(store.exportBackup()) as Map<String, dynamic>;
      (corrupt['events'] as List).first['standings'] = [
        {
          'id': 'not-a-winner',
          'playerNames': ['不明'],
        },
      ];
      await expectLater(
        store.restoreBackup(jsonEncode(corrupt)),
        throwsFormatException,
      );
      expect(storage.contents, contents);
      expect(store.events.single.id, 'event');
    },
  );
}
