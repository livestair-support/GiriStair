import 'models.dart';

/// Counts participation, never treating another participant as an opponent.
class GiriAnalytics {
  GiriAnalytics(Iterable<GiriEvent> events, {this.year})
    : attended = List.unmodifiable(
        events.where(
          (event) =>
              event.status == EventStatus.attended &&
              (year == null || dateOf(event)?.year == year),
        ),
      );

  final int? year;
  final List<GiriEvent> attended;

  List<GiriEvent> get live => attended
      .where((event) => event.kind == EventKind.live)
      .toList(growable: false);
  List<GiriEvent> get online => attended
      .where((event) => event.kind == EventKind.online)
      .toList(growable: false);
  List<GiriEvent> get tournaments => attended
      .where((event) => event.meetingType == MeetingType.tournament)
      .toList(growable: false);
  List<GiriEvent> get ranked => tournaments
      .where((event) => event.effectivePlacement != null && event.effectivePlacement! > 0)
      .toList(growable: false);
  int get firstPlaceCount =>
      ranked.where((event) => event.effectivePlacement == 1).length;
  int get podiumCount => ranked.where((event) => event.effectivePlacement! <= 3).length;
  int get resultCount => tournaments.where((event) => event.hasRecordedResult).length;

  List<MapEntry<String, int>> get venues =>
      _counts(live.map((event) => event.venue));
  List<MapEntry<String, int>> get organizers =>
      _counts(attended.map((event) => event.organizer));
  List<MapEntry<String, int>> get participants => _counts(
    live.expand(
      (event) => event.participants
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet(),
    ),
  );

  /// A live event's calendar date stays distinct from a notification deadline.
  static DateTime? dateOf(GiriEvent event) {
    if (event.kind == EventKind.live) {
      return event.eventDate ?? event.startsAt?.toLocal();
    }
    final dates = [
      for (final round in event.effectiveRounds) ...[
        round.submissionStart,
        round.submissionEnd,
        round.votingStart,
        round.votingEnd,
      ],
    ].whereType<DateTime>().toList()..sort();
    return dates.isEmpty ? null : dates.last.toLocal();
  }

  static List<int> yearsOf(Iterable<GiriEvent> events) =>
      events
          .map(dateOf)
          .whereType<DateTime>()
          .map((date) => date.year)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

  static List<MapEntry<String, int>> _counts(Iterable<String> values) {
    final counts = <String, int>{};
    for (final value in values) {
      final name = value.trim();
      if (name.isNotEmpty) {
        counts.update(name, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return counts.entries.toList()..sort((a, b) {
      final order = b.value.compareTo(a.value);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
  }
}
