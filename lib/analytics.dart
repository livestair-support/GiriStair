import 'models.dart';
import 'participant_import.dart';

class MonthlyParticipation {
  const MonthlyParticipation({
    required this.month,
    required this.live,
    required this.online,
  });

  final DateTime month;
  final int live;
  final int online;
  int get total => live + online;
}

/// Counts actual participation, never inferring opponents or wins from a name.
class GiriAnalytics {
  GiriAnalytics(
    Iterable<GiriEvent> events, {
    this.year,
    this.month,
    this.kind,
    this.meetingType,
    this.selfName = '',
    Map<String, String> siteNames = const {},
  }) : siteNames = Map.unmodifiable(siteNames),
       attended = List.unmodifiable(
         events.where((event) {
           if (event.status != EventStatus.attended || !event.isParticipating) {
             return false;
           }
           if (kind != null && event.kind != kind) return false;
           if (meetingType != null && event.meetingType != meetingType) {
             return false;
           }
           if (year == null && month == null) return true;
           final date = dateOf(event);
           return date != null &&
               (year == null || date.year == year) &&
               (month == null || date.month == month);
         }),
       ) {
    final selectedMonth = month;
    if (selectedMonth != null && (selectedMonth < 1 || selectedMonth > 12)) {
      throw ArgumentError.value(
        selectedMonth,
        'month',
        'Month must be 1 through 12.',
      );
    }
  }

  final int? year;
  final int? month;
  final EventKind? kind;
  final MeetingType? meetingType;
  final String selfName;
  final Map<String, String> siteNames;
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
  List<GiriEvent> get casual => attended
      .where((event) => event.meetingType == MeetingType.casual)
      .toList(growable: false);
  List<GiriEvent> get ranked => tournaments
      .where(
        (event) =>
            event.effectivePlacement != null && event.effectivePlacement! > 0,
      )
      .toList(growable: false);

  int get firstPlaceCount =>
      ranked.where((event) => event.effectivePlacement == 1).length;
  int get runnerUpCount =>
      ranked.where((event) => event.effectivePlacement == 2).length;
  int get podiumCount =>
      ranked.where((event) => event.effectivePlacement! <= 3).length;

  /// Explicit prizes may include placements outside the top three.
  /// Champions and runners-up have their own counters.
  int get placedCount => tournaments.where((event) {
    final rank = event.effectivePlacement;
    if (rank == 1 || rank == 2) return false;
    return rank == 3 ||
        event.tournamentResult?.outcome == TournamentOutcome.placed;
  }).length;

  int get resultCount =>
      tournaments.where((event) => event.hasRecordedResult).length;
  int get undatedCount =>
      attended.where((event) => dateOf(event) == null).length;

  List<MapEntry<String, int>> get venues =>
      _counts(live.map((event) => event.venue));
  List<MapEntry<String, int>> get organizers =>
      _counts(attended.map((event) => event.organizer));

  /// Preserves the original live-only public API used by existing exports.
  List<MapEntry<String, int>> get participants => _participantsOf(live);

  /// Both formats contribute equally to the current participation summary.
  List<MapEntry<String, int>> get coParticipants =>
      _participantsOf(attended, includeTeams: true);

  List<MapEntry<String, int>> _participantsOf(
    Iterable<GiriEvent> events, {
    bool includeTeams = false,
  }) {
    final self = playerSearchKey(selfName);
    return _counts(
      events.expand((event) {
        final names = <String, String>{};
        for (final value in [
          ...event.participants,
          if (includeTeams) ...event.teams.expand((team) => team.members),
          if (includeTeams) ...?event.tournamentResult?.members,
        ]) {
          final name = value.trim();
          final key = playerSearchKey(name);
          if (key.isNotEmpty && key != self) names.putIfAbsent(key, () => name);
        }
        return names.values;
      }),
    );
  }

  String siteLabel(GiriEvent event) {
    final registered = siteNames[event.onlineSiteId]?.trim();
    if (registered != null && registered.isNotEmpty) return registered;
    final host = Uri.tryParse(event.siteUrl.trim())?.host ?? '';
    if (host.isNotEmpty) return host.replaceFirst(RegExp(r'^www\.'), '');
    return event.title.trim();
  }

  List<MapEntry<String, int>> get sites => _counts(online.map(siteLabel));

  List<MonthlyParticipation> get monthly {
    final counts = <DateTime, List<int>>{};
    for (final event in attended) {
      final date = dateOf(event);
      if (date == null) continue;
      final key = DateTime(date.year, date.month);
      final count = counts.putIfAbsent(key, () => [0, 0]);
      count[event.kind == EventKind.live ? 0 : 1]++;
    }
    final periods = year != null
        ? [
            for (final index
                in month == null
                    ? List.generate(12, (index) => index + 1)
                    : [month!])
              DateTime(year!, index),
          ]
        : (counts.keys.toList()..sort());
    return List.unmodifiable(
      periods.map((period) {
        final count = counts[period] ?? const [0, 0];
        return MonthlyParticipation(
          month: period,
          live: count[0],
          online: count[1],
        );
      }),
    );
  }

  /// A live calendar date stays distinct from a notification deadline.
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
    final displayed = <String, String>{};
    for (final value in values) {
      final name = value.trim();
      final key = playerSearchKey(name);
      if (key.isEmpty) continue;
      displayed.putIfAbsent(key, () => name);
      counts.update(key, (count) => count + 1, ifAbsent: () => 1);
    }
    return [
      for (final entry in counts.entries)
        MapEntry(displayed[entry.key]!, entry.value),
    ]..sort((a, b) {
      final order = b.value.compareTo(a.value);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
  }
}
