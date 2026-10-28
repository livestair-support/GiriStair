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

  test('rankings count attended events and dedupe each participant per event', () {
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
  });

  test('year uses actual event dates and excludes undated events only in filter', () {
    final events = [
      event('old', date: DateTime(2025, 12, 31)),
      event('live', date: DateTime(2026, 1, 1)),
      event('online', kind: EventKind.online, date: DateTime(2026, 4)),
      event('unknown'),
    ];
    expect(GiriAnalytics(events).attended.length, 4);
    expect(GiriAnalytics(events, year: 2026).attended.length, 2);
    expect(GiriAnalytics.yearsOf(events), [2026, 2025]);
  });

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
}
