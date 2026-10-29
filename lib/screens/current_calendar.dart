import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../japanese_holidays.dart';
import '../models.dart';
import '../ui/stair_theme.dart';

enum CurrentPeriodKind { live, submission, voting }

/// Calendar spans are half-open, matching submission/voting deadlines.
class CurrentPeriod {
  const CurrentPeriod({
    required this.event,
    required this.start,
    required this.end,
    required this.kind,
    this.round,
  });

  final GiriEvent event;
  final EventRound? round;
  final DateTime start;
  final DateTime end;
  final CurrentPeriodKind kind;

  String get phase => switch (kind) {
    CurrentPeriodKind.live => '生大喜利',
    CurrentPeriodKind.submission => '投稿',
    CurrentPeriodKind.voting => '投票',
  };
  Color get color => switch (kind) {
    CurrentPeriodKind.live => StairColors.live,
    CurrentPeriodKind.submission => StairColors.online,
    CurrentPeriodKind.voting => StairColors.memo,
  };
  String get label => '${event.title} · $phase';

  bool overlapsDay(DateTime day) {
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    return start.isBefore(to) && end.isAfter(from);
  }
}

List<CurrentPeriod> currentPeriodsFor(Iterable<GiriEvent> events) {
  final periods = <CurrentPeriod>[];
  void add(GiriEvent event, EventRound? round, DateTime? start,
      DateTime? end, CurrentPeriodKind kind) {
    if (start == null || end == null || !end.isAfter(start)) return;
    periods.add(CurrentPeriod(
      event: event, round: round, start: start, end: end, kind: kind,
    ));
  }
  for (final event in events) {
    if (event.status == EventStatus.canceled) continue;
    if (event.kind == EventKind.live) {
      final date = event.startsAt ?? event.eventDate;
      add(event, null, date,
          event.endsAt ?? (date == null ? null : DateTime(date.year, date.month, date.day + 1)),
          CurrentPeriodKind.live);
      continue;
    }
    for (final round in event.effectiveRounds) {
      if (round.submissionEnabled) {
        add(event, round, round.submissionStart, round.submissionEnd,
            CurrentPeriodKind.submission);
      }
      if (round.votingRequired) {
        add(event, round, round.votingStart, round.votingEnd,
            CurrentPeriodKind.voting);
      }
    }
  }
  periods.sort((a, b) {
    final order = a.start.compareTo(b.start);
    return order == 0 ? a.event.title.compareTo(b.event.title) : order;
  });
  return periods;
}

Color calendarDateColor(BuildContext context, DateTime day) {
  if (day.weekday == DateTime.sunday || isJapaneseHoliday(day)) {
    return CupertinoColors.systemRed.resolveFrom(context);
  }
  if (day.weekday == DateTime.saturday) {
    return CupertinoColors.systemBlue.resolveFrom(context);
  }
  return Theme.of(context).colorScheme.onSurface;
}

class CurrentCalendar extends StatelessWidget {
  const CurrentCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.periods,
    required this.onMonthChanged,
    required this.onSelected,
    required this.onOpenPeriod,
  });

  final DateTime month;
  final DateTime selected;
  final List<CurrentPeriod> periods;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onSelected;
  final ValueChanged<CurrentPeriod> onOpenPeriod;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final gridStart = DateTime(first.year, first.month, 1 - first.weekday % 7);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final weeks = ((first.weekday % 7 + count) / 7).ceil();
    return StairCard(
      accent: StairColors.online,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        children: [
          Row(children: [
            CupertinoButton(
              key: const ValueKey('current-previous-month'),
              padding: const EdgeInsets.all(10),
              onPressed: () => onMonthChanged(DateTime(month.year, month.month - 1)),
              child: const Icon(CupertinoIcons.chevron_left, size: 18),
            ),
            Expanded(child: Text('${month.year}年${month.month}月',
              textAlign: TextAlign.center,
              style: StairTypography.style(const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            )),
            CupertinoButton(
              key: const ValueKey('current-next-month'),
              padding: const EdgeInsets.all(10),
              onPressed: () => onMonthChanged(DateTime(month.year, month.month + 1)),
              child: const Icon(CupertinoIcons.chevron_right, size: 18),
            ),
          ]),
          Row(children: [
            for (var index = 0; index < 7; index++) Expanded(child: Text(
              const ['日', '月', '火', '水', '木', '金', '土'][index],
              textAlign: TextAlign.center,
              style: StairTypography.role(StairTextRole.caption,
                color: index == 0 ? CupertinoColors.systemRed.resolveFrom(context)
                    : index == 6 ? CupertinoColors.systemBlue.resolveFrom(context)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )),
          ]),
          for (var week = 0; week < weeks; week++) _week(
            context,
            DateTime(gridStart.year, gridStart.month, gridStart.day + week * 7),
          ),
        ],
      ),
    );
  }

  Widget _week(BuildContext context, DateTime start) {
    final end = DateTime(start.year, start.month, start.day + 7);
    final visible = periods.where((period) =>
      period.start.isBefore(end) && period.end.isAfter(start)).toList();
    return Column(children: [
      Row(children: [
        for (var day = 0; day < 7; day++) Expanded(child: _day(
          context, DateTime(start.year, start.month, start.day + day),
        )),
      ]),
      for (final period in visible) LayoutBuilder(builder: (context, constraints) {
        final firstDay = DateTime(period.start.year, period.start.month, period.start.day);
        final lastInstant = period.end.subtract(const Duration(microseconds: 1));
        final lastDay = DateTime(lastInstant.year, lastInstant.month, lastInstant.day);
        int offset(DateTime day) => DateTime.utc(day.year, day.month, day.day)
            .difference(DateTime.utc(start.year, start.month, start.day)).inDays;
        final first = firstDay.isBefore(start) ? 0 : offset(firstDay).clamp(0, 6);
        final last = lastDay.isAfter(end) ? 6 : offset(lastDay).clamp(0, 6);
        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            if (first > 0) SizedBox(width: constraints.maxWidth / 7 * first),
            SizedBox(
              width: constraints.maxWidth / 7 * (last - first + 1),
              child: Semantics(
                button: true,
                label: '${period.label} ${period.round?.name ?? ''}',
                child: Tooltip(
                  message: '${period.label} ${period.round?.name ?? ''}',
                  child: GestureDetector(
                    onTap: () => onOpenPeriod(period),
                    child: Container(
                      height: (MediaQuery.textScalerOf(context).scale(11) + 8).clamp(21, 48).toDouble(),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: period.color.withValues(alpha: period.event.isParticipating ? .19 : .08),
                        border: Border.all(color: period.color.withValues(alpha: .6), width: .6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(period.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: StairTypography.style(TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: period.color))),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        );
      }),
      const SizedBox(height: 5),
    ]);
  }

  Widget _day(BuildContext context, DateTime day) {
    final chosen = DateUtils.isSameDay(day, selected);
    final today = DateUtils.isSameDay(day, DateTime.now());
    final foreground = calendarDateColor(context, day);
    final holiday = japaneseHolidayName(day);
    return Semantics(
      label: '${day.month}月${day.day}日${holiday == null ? '' : ' $holiday'}',
      selected: chosen,
      child: CupertinoButton(
        key: ValueKey('current-day-${day.year}-${day.month}-${day.day}'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        minimumSize: const Size(36, 40),
        onPressed: () => onSelected(day),
        child: Container(
          width: 32, height: 32, alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: chosen ? StairColors.action : Colors.transparent,
            border: today && !chosen ? Border.all(color: StairColors.action) : null,
          ),
          child: Text('${day.day}', style: StairTypography.style(TextStyle(
            fontSize: 15, fontWeight: today || chosen ? FontWeight.w700 : FontWeight.w400,
            color: chosen ? Colors.white : foreground.withValues(alpha: day.month == month.month ? 1 : .35),
          ))),
        ),
      ),
    );
  }
}
