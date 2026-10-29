import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/notifications.dart';

GiriEvent meeting(
  String id, {
  EventKind kind = EventKind.live,
  MeetingType meetingType = MeetingType.casual,
  EventStatus status = EventStatus.planned,
  bool isParticipating = true,
  String? title,
  DateTime? date,
  DateTime? start,
  DateTime? submission,
  DateTime? voting,
  List<EventRound> rounds = const [],
}) => GiriEvent(
  id: id,
  title: title ?? '会$id',
  kind: kind,
  meetingType: meetingType,
  createdAt: DateTime(2026, 1),
  status: status,
  eventDate: date,
  startsAt: start,
  submissionEnd: submission,
  votingEnd: voting,
  rounds: rounds,
  isParticipating: isParticipating,
);

void main() {
  const enabled = AppPreferences(notificationsEnabled: true);
  final now = DateTime(2026, 10, 28, 8);

  test(
    'disabled, unjoined, canceled, attended live and elapsed reminders stay unscheduled',
    () {
      final events = [
        meeting('future', start: DateTime(2026, 10, 28, 12)),
        meeting('unjoined', start: DateTime(2026, 10, 28, 12), isParticipating: false),
        meeting('past', start: DateTime(2026, 10, 28, 8, 30)),
        meeting(
          'canceled',
          start: DateTime(2026, 10, 28, 12),
          status: EventStatus.canceled,
        ),
        meeting(
          'attended',
          start: DateTime(2026, 10, 28, 12),
          status: EventStatus.attended,
        ),
      ];
      expect(
        planGiriReminders(
          events: events,
          preferences: const AppPreferences(),
          now: now,
        ),
        isEmpty,
      );
      final plan = planGiriReminders(
        events: events,
        preferences: enabled,
        now: now,
      );
      expect(plan.map((item) => item.key), ['future:start']);
      expect(plan.single.when, DateTime(2026, 10, 28, 11));
    },
  );

  test('calendar-only meetings use the chosen local morning time', () {
    final plan = planGiriReminders(
      events: [
        meeting('day', date: DateTime(2026, 10, 29)),
        meeting('unknown'),
      ],
      preferences: enabled.copyWith(reminderHour: 10, reminderMinute: 15),
      now: now,
    );
    expect(plan.single.key, 'day:day');
    expect(plan.single.when, DateTime(2026, 10, 29, 10, 15));
  });

  test('start time takes priority over the calendar-only reminder', () {
    final plan = planGiriReminders(
      events: [
        meeting(
          'timed',
          date: DateTime(2026, 10, 29),
          start: DateTime(2026, 10, 29, 20),
        ),
      ],
      preferences: enabled,
      now: now,
    );
    expect(plan.length, 1);
    expect(plan.single.when, DateTime(2026, 10, 29, 19));
  });

  test('submission and voting deadlines remain distinct at the same time', () {
    final plan = planGiriReminders(
      events: [
        meeting(
          'online',
          kind: EventKind.online,
          submission: DateTime(2026, 10, 29, 23),
          voting: DateTime(2026, 10, 29, 23),
        ),
      ],
      preferences: enabled.copyWith(reminderMinutes: 30),
      now: now,
    );
    expect(plan.map((item) => item.key).toSet(), {
      'online:submission',
      'online:voting',
    });
    expect(
      plan.every((item) => item.when == DateTime(2026, 10, 29, 22, 30)),
      isTrue,
    );
  });

  test('iOS limit keeps the nearest 64 reminders in a stable order', () {
    final events = List.generate(
      80,
      (index) =>
          meeting('event$index', start: now.add(Duration(hours: 82 - index))),
    );
    final plan = planGiriReminders(
      events: events,
      preferences: enabled,
      now: now,
    );
    expect(plan.length, 64);
    expect(plan.first.eventId, 'event79');
    expect(plan.last.eventId, 'event16');
    expect(plan.map((item) => item.key).toSet().length, 64);
    expect(
      planGiriReminders(
        events: events,
        preferences: enabled,
        now: now,
        limit: 128,
      ).length,
      64,
    );
    expect(
      planGiriReminders(
        events: events,
        preferences: enabled,
        now: now,
        limit: 0,
      ),
      isEmpty,
    );
  });

  test('zero lead means the event or deadline itself, never earlier', () {
    final start = DateTime(2026, 10, 29, 20);
    final plan = planGiriReminders(
      events: [meeting('timed', start: start)],
      preferences: enabled.copyWith(reminderMinutes: 0),
      now: now,
    );
    expect(plan.single.when, start);
    expect(plan.single.body, '開始時刻です');
  });

  test('each round has distinct submission and voting reminders', () {
    final deadline = DateTime(2026, 10, 29, 23);
    final event = meeting(
      'online',
      kind: EventKind.online,
      meetingType: MeetingType.tournament,
      // Explicit rounds replace the old single-period fields.
      submission: DateTime(2026, 10, 30, 23),
      voting: DateTime(2026, 11, 1, 23),
      rounds: [
        EventRound(
          id: 'qualifier-1',
          name: '予選1回戦',
          submissionEnd: deadline,
          votingEnd: deadline,
        ),
        EventRound(
          id: 'final',
          name: '決勝',
          submissionEnd: deadline.add(const Duration(days: 14)),
        ),
      ],
    );
    final plan = planGiriReminders(
      events: [event],
      preferences: enabled.copyWith(reminderMinutes: 30),
      now: now,
    );
    expect(plan.map((item) => item.key).toSet(), {
      'online:round:qualifier-1:submission',
      'online:round:qualifier-1:voting',
      'online:round:final:submission',
    });
    expect(plan.first.when, DateTime(2026, 10, 29, 22, 30));
    expect(plan.first.body, '予選1回戦・お題1・投稿締切の30分前です');
    expect(plan.last.body, '決勝・お題1・投稿締切の30分前です');

    final renamed = event.copyWith(
      rounds: [
        event.rounds.last.copyWith(name: '決勝戦'),
        event.rounds.first.copyWith(name: '予選'),
      ],
    );
    final renamedPlan = planGiriReminders(
      events: [renamed],
      preferences: enabled.copyWith(reminderMinutes: 30),
      now: now,
    );
    expect(renamedPlan.map((item) => item.key), plan.map((item) => item.key));
    expect(renamedPlan.last.body, '決勝戦・お題1・投稿締切の30分前です');
  });

  test('elapsed and canceled rounds are skipped while attended voting remains', () {
    final event = meeting(
      'online',
      kind: EventKind.online,
      meetingType: MeetingType.tournament,
      rounds: [
        EventRound(
          id: 'past',
          name: '予選',
          submissionEnd: now.subtract(const Duration(days: 1)),
        ),
        EventRound(
          id: 'future',
          name: '本戦',
          votingEnd: now.add(const Duration(days: 7)),
        ),
        const EventRound(id: 'unknown', name: '決勝'),
      ],
    );
    final plan = planGiriReminders(
      events: [
        event,
        event.copyWith(id: 'canceled', status: EventStatus.canceled),
        event.copyWith(id: 'attended', status: EventStatus.attended),
        event.copyWith(id: 'preview', isParticipating: false),
      ],
      preferences: enabled.copyWith(reminderMinutes: 0),
      now: now,
    );
    expect(plan.map((item) => item.key), [
      'attended:round:future:voting',
      'online:round:future:voting',
    ]);
    expect(plan.every((item) => item.body == '本戦・お題1・投票の締切です'), isTrue);
    expect(plan.every((item) => item.when == now.add(const Duration(days: 7))), isTrue);
  });

  test('one long tournament still keeps only the nearest 64 deadlines', () {
    final event = meeting(
      'long',
      kind: EventKind.online,
      rounds: List.generate(
        40,
        (index) => EventRound(
          id: 'round$index',
          name: '${index + 1}回戦',
          submissionEnd: now.add(Duration(days: index * 2 + 1)),
          votingEnd: now.add(Duration(days: index * 2 + 2)),
        ),
      ).reversed.toList(),
    );
    final plan = planGiriReminders(
      events: [event],
      preferences: enabled,
      now: now,
    );
    expect(plan.length, 64);
    expect(plan.first.key, 'long:round:round0:submission');
    expect(plan.last.key, 'long:round:round31:voting');
    expect(plan.map((item) => item.key).toSet().length, 64);
  });

  test('eliminated players retain required voting but no posting reminders', () {
    final deadline = now.add(const Duration(days: 7));
    final event = meeting(
      'eliminated',
      kind: EventKind.online,
      meetingType: MeetingType.tournament,
      status: EventStatus.attended,
      title: '投票が必要なサイトの大会',
      rounds: [
        EventRound(
          id: 'final',
          name: '決勝',
          submissionEnd: deadline,
          votingEnd: deadline,
          submissionEnabled: false,
          votingRequired: true,
        ),
        EventRound(
          id: 'optional',
          name: '終了後',
          submissionEnd: deadline,
          votingEnd: deadline,
          votingRequired: false,
        ),
      ],
    ).copyWith(
      tournamentResult: TournamentResult(outcome: TournamentOutcome.eliminated),
    );
    final plan = planGiriReminders(
      events: [event],
      preferences: enabled,
      now: now,
    );
    expect(plan.single.key, 'eliminated:round:final:voting');
    expect(plan.single.title, '投票が必要なサイトの大会');
    expect(plan.single.body, '決勝・お題1・投票締切の60分前です');
    expect(
      planGiriReminders(
        events: [event.copyWith(status: EventStatus.canceled)],
        preferences: enabled,
        now: now,
      ),
      isEmpty,
    );
  });

  test('round posting and voting switches are independent while planned', () {
    final deadline = now.add(const Duration(days: 7));
    final plan = planGiriReminders(
      events: [
        meeting(
          'switches',
          kind: EventKind.online,
          rounds: [
            EventRound(
              id: 'post-only',
              name: '投稿',
              submissionEnd: deadline,
              votingEnd: deadline,
              votingRequired: false,
            ),
            EventRound(
              id: 'vote-only',
              name: '投票',
              submissionEnd: deadline,
              votingEnd: deadline,
              submissionEnabled: false,
            ),
            EventRound(
              id: 'disabled',
              name: '対象外',
              submissionEnd: deadline,
              votingEnd: deadline,
              submissionEnabled: false,
              votingRequired: false,
            ),
          ],
        ),
      ],
      preferences: enabled,
      now: now,
    );
    expect(plan.map((item) => item.key), [
      'switches:round:post-only:submission',
      'switches:round:vote-only:voting',
    ]);
  });

  test('same-stage prompt and block reminders retain stable separate keys', () {
    final deadline = now.add(const Duration(days: 7));
    final event = meeting(
      'site',
      kind: EventKind.online,
      meetingType: MeetingType.tournament,
      title: 'サイト名が分かる大会',
      rounds: [
        EventRound(
          id: 'round/a:1',
          name: '予選1回戦',
          stageId: 'qualifier',
          promptNumber: 1,
          block: 'Aブロック',
          votingEnd: deadline,
        ),
        EventRound(
          id: 'round/a:2',
          name: '予選1回戦',
          stageId: 'qualifier',
          promptNumber: 2,
          block: 'Bブロック',
          votingEnd: deadline,
        ),
      ],
    );
    final plan = planGiriReminders(
      events: [event],
      preferences: enabled,
      now: now,
    );
    expect(plan.map((item) => item.key).toSet(), {
      'site:round:${Uri.encodeComponent('round/a:1')}:voting',
      'site:round:${Uri.encodeComponent('round/a:2')}:voting',
    });
    expect(plan.every((item) => item.title == 'サイト名が分かる大会'), isTrue);
    expect(plan.map((item) => item.body).toSet(), {
      '予選1回戦・お題1・Aブロック・投票締切の60分前です',
      '予選1回戦・お題2・Bブロック・投票締切の60分前です',
    });
    final reordered = planGiriReminders(
      events: [
        event.copyWith(rounds: event.rounds.reversed.map(
          (round) => round.copyWith(name: '改名した予選'),
        ).toList()),
      ],
      preferences: enabled,
      now: now,
    );
    expect(reordered.map((item) => item.key), plan.map((item) => item.key));
  });

  test('ordinary site reminders show affiliation and topic without qualifiers', () {
    final event = meeting(
      'ordinary',
      kind: EventKind.online,
      title: '毎週参加するサイト',
      rounds: [
        EventRound(
          id: 'week',
          // A name left over from an older version must not imply a tournament.
          name: '予選1回戦',
          promptNumber: 3,
          block: 'お題A',
          votingEnd: now.add(const Duration(days: 7)),
        ),
      ],
    ).copyWith(affiliation: '一部', block: 'お題A');
    final plan = planGiriReminders(
      events: [event],
      preferences: enabled,
      now: now,
    );
    expect(plan.single.title, '毎週参加するサイト');
    expect(plan.single.body, 'お題3・一部・お題A・投票締切の60分前です');
    expect(plan.single.body, isNot(contains('予選')));
    expect(
      planGiriReminders(
        events: [event.copyWith(isParticipating: false)],
        preferences: enabled,
        now: now,
      ),
      isEmpty,
    );
  });

  test('legacy attended online entries retain the original required-vote key', () {
    final deadline = now.add(const Duration(days: 7));
    final plan = planGiriReminders(
      events: [
        meeting(
          'legacy',
          kind: EventKind.online,
          status: EventStatus.attended,
          submission: deadline,
          voting: deadline,
        ),
      ],
      preferences: enabled,
      now: now,
    );
    expect(plan.single.key, 'legacy:voting');
    expect(plan.single.title, '会legacy');
    expect(plan.single.body, '投票締切の60分前です');
  });
}
