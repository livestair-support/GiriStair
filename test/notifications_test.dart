import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/notifications.dart';

GiriEvent meeting(
  String id, {
  EventKind kind = EventKind.live,
  EventStatus status = EventStatus.planned,
  DateTime? date,
  DateTime? start,
  DateTime? submission,
  DateTime? voting,
  List<EventRound> rounds = const [],
}) => GiriEvent(
  id: id,
  title: '会$id',
  kind: kind,
  meetingType: MeetingType.casual,
  createdAt: DateTime(2026, 1),
  status: status,
  eventDate: date,
  startsAt: start,
  submissionEnd: submission,
  votingEnd: voting,
  rounds: rounds,
);

void main() {
  const enabled = AppPreferences(notificationsEnabled: true);
  final now = DateTime(2026, 10, 28, 8);

  test(
    'disabled, canceled, attended and elapsed reminders stay unscheduled',
    () {
      final events = [
        meeting('future', start: DateTime(2026, 10, 28, 12)),
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
    expect(plan.first.body, '予選1回戦・投稿締切の30分前です');
    expect(plan.last.body, '決勝・投稿締切の30分前です');

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
    expect(
      renamedPlan.map((item) => item.key),
      plan.map((item) => item.key),
    );
    expect(renamedPlan.last.body, '決勝戦・投稿締切の30分前です');
  });

  test('elapsed rounds and non-planned events do not produce reminders', () {
    final event = meeting(
      'online',
      kind: EventKind.online,
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
      ],
      preferences: enabled.copyWith(reminderMinutes: 0),
      now: now,
    );
    expect(plan.single.key, 'online:round:future:voting');
    expect(plan.single.body, '本戦・投票の締切です');
    expect(plan.single.when, now.add(const Duration(days: 7)));
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
}
