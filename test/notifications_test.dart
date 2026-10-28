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
);

void main() {
  const enabled = AppPreferences(notificationsEnabled: true);
  final now = DateTime(2026, 10, 28, 8);

  test('disabled, canceled, attended and elapsed reminders stay unscheduled', () {
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
  });

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
    expect(plan.every((item) => item.when == DateTime(2026, 10, 29, 22, 30)), isTrue);
  });

  test('iOS limit keeps the nearest 64 reminders in a stable order', () {
    final events = List.generate(
      80,
      (index) => meeting(
        'event$index',
        start: now.add(Duration(hours: 82 - index)),
      ),
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
}
