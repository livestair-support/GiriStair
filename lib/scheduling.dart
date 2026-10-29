import 'models.dart';

/// Calendar arithmetic preserves local clock time across daylight-saving changes.
DateTime addCalendarDays(DateTime value, int days) => value.isUtc
    ? DateTime.utc(value.year, value.month, value.day + days, value.hour,
        value.minute, value.second, value.millisecond, value.microsecond)
    : DateTime(value.year, value.month, value.day + days, value.hour,
        value.minute, value.second, value.millisecond, value.microsecond);

DateTime fiveMinuteSelection(DateTime value) => value.isUtc
    ? DateTime.utc(value.year, value.month, value.day, value.hour,
        value.minute ~/ 5 * 5)
    : DateTime(value.year, value.month, value.day, value.hour,
        value.minute ~/ 5 * 5);

DateTime defaultSubmissionStart(DateTime day, AppPreferences preferences) =>
    day.isUtc
        ? DateTime.utc(day.year, day.month,
            day.day + preferences.submissionStartDayOffset,
            preferences.submissionStartHour, preferences.submissionStartMinute)
        : DateTime(day.year, day.month,
            day.day + preferences.submissionStartDayOffset,
            preferences.submissionStartHour, preferences.submissionStartMinute);

/// Only empty fields are derived; manual dates are never silently overwritten.
EventRound completeRoundSchedule(EventRound round, {
  int submissionDays = 7, int votingDays = 7,
}) {
  final start = round.submissionStart;
  if (start == null) return round;
  final end = round.submissionEnd ?? addCalendarDays(start, submissionDays);
  final voting = round.votingStart ?? end;
  return round.copyWith(
    submissionEnd: end,
    votingStart: voting,
    votingEnd: round.votingEnd ?? addCalendarDays(voting, votingDays),
  );
}

DateTime siteCycleStart(OnlineSite site, DateTime weekOf, {int weekOffset = 0}) {
  final day = site.recurrence == SiteRecurrence.weekly
      ? weekOf.day - weekOf.weekday % 7 + site.weekday % 7 + weekOffset * 7
      : weekOf.day + weekOffset * (site.submissionDays + site.votingDays);
  return weekOf.isUtc
      ? DateTime.utc(weekOf.year, weekOf.month, day, site.startHour, site.startMinute)
      : DateTime(weekOf.year, weekOf.month, day, site.startHour, site.startMinute);
}

String cycleKeyFor(DateTime start) =>
    '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}T${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';

String nextStageName(String name) {
  final match = RegExp(r'^(.*?)(\d+)回戦$').firstMatch(name.trim());
  if (match != null) return '${match[1]}${int.parse(match[2]!) + 1}回戦';
  if (name.contains('予選')) return '本戦1回戦';
  if (name.contains('準々決勝')) return '準決勝';
  if (name.contains('準決勝')) return '決勝';
  if (name.contains('決勝')) return '追加日程';
  return '予選1回戦';
}

EventRound addNextRound(EventRound? previous, {
  required String id, bool sameStage = false, bool tournament = true,
  required DateTime defaultStart, int submissionDays = 7, int votingDays = 7,
}) {
  final start = previous?.votingEnd ?? previous?.submissionEnd ?? defaultStart;
  return completeRoundSchedule(EventRound(
    id: id,
    name: tournament
        ? sameStage && previous != null ? previous.name : nextStageName(previous?.name ?? '')
        : '投稿・投票',
    stageId: sameStage ? previous?.effectiveStageId ?? id : id,
    promptNumber: sameStage ? (previous?.promptNumber ?? 0) + 1 : 1,
    block: previous?.block ?? '',
    submissionStart: start,
  ), submissionDays: submissionDays, votingDays: votingDays);
}

bool eventNeedsResult(GiriEvent event, DateTime now) {
  if (event.kind != EventKind.live || event.meetingType != MeetingType.tournament ||
      event.status == EventStatus.canceled || !event.isParticipating || event.hasFinalResult) return false;
  final end = event.endsAt;
  if (end != null) return !now.isBefore(end);
  final day = event.eventDate ?? event.startsAt;
  return day != null && !now.isBefore(DateTime(day.year, day.month, day.day + 1));
}

String nextRoundName(String name) => nextStageName(name);

EventRound nextEventRound({
  required List<EventRound> rounds,
  required String id,
  required AppPreferences preferences,
  bool sameStage = false,
  bool tournament = true,
  DateTime? referenceDate,
}) => addNextRound(
  rounds.isEmpty ? null : rounds.last,
  id: id,
  sameStage: sameStage,
  tournament: tournament,
  defaultStart: defaultSubmissionStart(referenceDate ?? DateTime.now(), preferences),
  submissionDays: preferences.submissionDays,
  votingDays: preferences.votingDays,
);
