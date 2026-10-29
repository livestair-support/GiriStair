import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../japanese_holidays.dart';
import '../models.dart';
import '../ui/stair_theme.dart';
import '../ui/stair_symbols.dart';

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
  void add(
    GiriEvent event,
    EventRound? round,
    DateTime? start,
    DateTime? end,
    CurrentPeriodKind kind,
  ) {
    if (start == null || end == null || !end.isAfter(start)) {
      return;
    }
    periods.add(
      CurrentPeriod(
        event: event,
        round: round,
        start: start,
        end: end,
        kind: kind,
      ),
    );
  }

  for (final event in events) {
    if (event.status == EventStatus.canceled) {
      continue;
    }
    if (event.kind == EventKind.live) {
      final date = event.startsAt ?? event.eventDate;
      add(
        event,
        null,
        date,
        event.endsAt ??
            (date == null
                ? null
                : DateTime(date.year, date.month, date.day + 1)),
        CurrentPeriodKind.live,
      );
      continue;
    }
    for (final round in event.effectiveRounds) {
      if (round.submissionEnabled) {
        add(
          event,
          round,
          round.submissionStart,
          round.submissionEnd,
          CurrentPeriodKind.submission,
        );
      }
      if (round.votingRequired) {
        add(
          event,
          round,
          round.votingStart,
          round.votingEnd,
          CurrentPeriodKind.voting,
        );
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

class CurrentCalendar extends StatefulWidget {
  const CurrentCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.periods,
    required this.onMonthChanged,
    required this.onSelected,
    required this.onOpenPeriod,
    this.accent = StairColors.online,
  });

  final DateTime month;
  final DateTime selected;
  final List<CurrentPeriod> periods;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onSelected;
  final ValueChanged<CurrentPeriod> onOpenPeriod;
  final Color accent;

  @override
  State<CurrentCalendar> createState() => _CurrentCalendarState();
}

class _CurrentCalendarState extends State<CurrentCalendar> {
  bool _showPicker = false;
  late int _pickerYear = widget.month.year;
  late int _pickerMonth = widget.month.month;
  int _pickerGeneration = 0;

  DateTime get month => widget.month;
  DateTime get selected => widget.selected;
  List<CurrentPeriod> get periods => widget.periods;
  Color get accent => widget.accent;
  DateTime get _minimumMonth =>
      DateTime(DateTime.now().year, DateTime.now().month - 240);
  DateTime get _maximumMonth =>
      DateTime(DateTime.now().year, DateTime.now().month + 240);
  bool get _isToday =>
      DateUtils.isSameDay(selected, DateTime.now()) &&
      month.year == DateTime.now().year &&
      month.month == DateTime.now().month;

  void _changeMonth(DateTime value) {
    final target = DateTime(value.year, value.month);
    if (target.isBefore(_minimumMonth) || target.isAfter(_maximumMonth)) {
      return;
    }
    widget.onMonthChanged(target);
  }

  void _togglePicker() => setState(() {
    if (!_showPicker) {
      _pickerYear = month.year;
      _pickerMonth = month.month;
      _pickerGeneration++;
    }
    _showPicker = !_showPicker;
  });

  void _applyMonth() {
    var target = DateTime(_pickerYear, _pickerMonth);
    if (target.isBefore(_minimumMonth)) {
      target = _minimumMonth;
    }
    if (target.isAfter(_maximumMonth)) {
      target = _maximumMonth;
    }
    widget.onMonthChanged(target);
    setState(() => _showPicker = false);
  }

  void _today() {
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() => _showPicker = false);
    widget.onMonthChanged(DateTime(today.year, today.month));
    widget.onSelected(today);
  }

  void _select(DateTime day) {
    if (day.year != month.year || day.month != month.month) {
      _changeMonth(DateTime(day.year, day.month));
    }
    widget.onSelected(day);
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final gridStart = DateTime(first.year, first.month, 1 - first.weekday % 7);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final weeks = ((first.weekday % 7 + count) / 7).ceil();
    return StairCard(
      accent: accent,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Column(
        children: [
          _header(context),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                ignoring: _showPicker,
                child: ExcludeSemantics(
                  excluding: _showPicker,
                  child: AnimatedOpacity(
                    opacity: _showPicker ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    child: GestureDetector(
                      onHorizontalDragEnd: _showPicker
                          ? null
                          : (details) {
                              final velocity = details.primaryVelocity ?? 0;
                              if (velocity.abs() > 150) {
                                _changeMonth(
                                  DateTime(
                                    month.year,
                                    month.month + (velocity < 0 ? 1 : -1),
                                  ),
                                );
                              }
                            },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 248),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                for (var index = 0; index < 7; index++)
                                  Expanded(
                                    child: Text(
                                      const [
                                        '日',
                                        '月',
                                        '火',
                                        '水',
                                        '木',
                                        '金',
                                        '土',
                                      ][index],
                                      textAlign: TextAlign.center,
                                      style: StairTypography.role(
                                        StairTextRole.caption,
                                        color: index == 0
                                            ? CupertinoColors.systemRed
                                                  .resolveFrom(context)
                                            : index == 6
                                            ? CupertinoColors.systemBlue
                                                  .resolveFrom(context)
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            for (var week = 0; week < weeks; week++)
                              _week(
                                context,
                                DateTime(
                                  gridStart.year,
                                  gridStart.month,
                                  gridStart.day + week * 7,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_showPicker,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    child: _showPicker
                        ? _pickerArea(context)
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final end = DateTime(month.year, month.month + 1);
    final first = DateTime(month.year, month.month);
    final count = periods
        .where(
          (period) => period.start.isBefore(end) && period.end.isAfter(first),
        )
        .map((period) => period.event.id)
        .toSet()
        .length;
    final primary = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Semantics(
                  hint: '年月を選んで移動します',
                  child: CupertinoButton(
                    key: const ValueKey('current-month-picker-toggle'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    onPressed: _togglePicker,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${month.year}年${month.month}月',
                            maxLines: 1,
                            style: StairTypography.style(
                              TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                color: primary,
                              ),
                              role: StairTextRole.sectionTitle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        StairSymbolIcon(
                          icon: _showPicker
                              ? CupertinoIcons.chevron_up
                              : CupertinoIcons.chevron_down,
                          size: 14,
                          weight: FontWeight.w700,
                          color: accent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  '$count件',
                  style: StairTypography.role(
                    StairTextRole.caption,
                    color: accent,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        CupertinoButton(
          key: const ValueKey('current-today'),
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 36),
          onPressed: _today,
          child: Container(
            height: 30,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: _isToday ? .14 : .07),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: accent.withValues(alpha: _isToday ? .32 : .16),
                width: 1,
              ),
            ),
            child: Text(
              '今日',
              style: StairTypography.style(
                TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _isToday ? accent : primary,
                ),
                role: StairTextRole.sectionTitle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _monthArrow(context, -1),
        _monthArrow(context, 1),
      ],
    );
  }

  Widget _monthArrow(BuildContext context, int amount) => Semantics(
    label: amount < 0 ? '前の月' : '次の月',
    child: Opacity(
      opacity: _showPicker ? .35 : 1,
      child: CupertinoButton(
        key: ValueKey(
          amount < 0 ? 'current-previous-month' : 'current-next-month',
        ),
        padding: EdgeInsets.zero,
        minimumSize: const Size(36, 36),
        onPressed: _showPicker
            ? null
            : () => _changeMonth(DateTime(month.year, month.month + amount)),
        child: StairSymbolIcon(
          icon: amount < 0
              ? CupertinoIcons.chevron_left
              : CupertinoIcons.chevron_right,
          size: 21,
          weight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );

  Widget _pickerArea(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 170,
              child: _CalendarMonthWheels(
                key: ValueKey('current-month-wheels-$_pickerGeneration'),
                year: _pickerYear,
                month: _pickerMonth,
                firstYear: _minimumMonth.year,
                lastYear: _maximumMonth.year,
                onYearChanged: (year) => _pickerYear = year,
                onMonthChanged: (month) => _pickerMonth = month,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: CupertinoButton(
                  key: const ValueKey('current-apply-month'),
                  padding: EdgeInsets.zero,
                  color: accent,
                  borderRadius: BorderRadius.circular(30),
                  onPressed: _applyMonth,
                  child: Text(
                    'この年月を表示',
                    style: StairTypography.role(
                      StairTextRole.saveButton,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _week(BuildContext context, DateTime start) {
    final end = DateTime(start.year, start.month, start.day + 7);
    final visible = periods
        .where(
          (period) => period.start.isBefore(end) && period.end.isAfter(start),
        )
        .toList();
    return Column(
      children: [
        Row(
          children: [
            for (var day = 0; day < 7; day++)
              Expanded(
                child: _day(
                  context,
                  DateTime(start.year, start.month, start.day + day),
                ),
              ),
          ],
        ),
        for (final period in visible)
          LayoutBuilder(
            builder: (context, constraints) {
              final firstDay = DateTime(
                period.start.year,
                period.start.month,
                period.start.day,
              );
              final lastInstant = period.end.subtract(
                const Duration(microseconds: 1),
              );
              final lastDay = DateTime(
                lastInstant.year,
                lastInstant.month,
                lastInstant.day,
              );
              int offset(DateTime day) =>
                  DateTime.utc(day.year, day.month, day.day)
                      .difference(
                        DateTime.utc(start.year, start.month, start.day),
                      )
                      .inDays;
              final first = firstDay.isBefore(start)
                  ? 0
                  : offset(firstDay).clamp(0, 6);
              final last = lastDay.isAfter(end)
                  ? 6
                  : offset(lastDay).clamp(0, 6);
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    if (first > 0)
                      SizedBox(width: constraints.maxWidth / 7 * first),
                    SizedBox(
                      width: constraints.maxWidth / 7 * (last - first + 1),
                      child: Semantics(
                        button: true,
                        label: '${period.label} ${period.round?.name ?? ''}',
                        child: Tooltip(
                          message:
                              '${period.label} ${period.round?.name ?? ''}',
                          child: GestureDetector(
                            onTap: () => widget.onOpenPeriod(period),
                            child: Container(
                              height:
                                  (MediaQuery.textScalerOf(context).scale(11) +
                                          8)
                                      .clamp(21, 48)
                                      .toDouble(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: period.color.withValues(
                                  alpha: period.event.isParticipating
                                      ? .19
                                      : .08,
                                ),
                                border: Border.all(
                                  color: period.color.withValues(alpha: .6),
                                  width: .6,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                period.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: StairTypography.style(
                                  TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: period.color,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 5),
      ],
    );
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
        onPressed: () => _select(day),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: chosen ? StairColors.action : Colors.transparent,
            border: today && !chosen
                ? Border.all(color: StairColors.action)
                : null,
          ),
          child: Text(
            '${day.day}',
            style: StairTypography.style(
              TextStyle(
                fontSize: 15,
                fontWeight: today || chosen ? FontWeight.w700 : FontWeight.w400,
                color: chosen
                    ? Colors.white
                    : foreground.withValues(
                        alpha: day.month == month.month ? 1 : .35,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarMonthWheels extends StatefulWidget {
  const _CalendarMonthWheels({
    super.key,
    required this.year,
    required this.month,
    required this.firstYear,
    required this.lastYear,
    required this.onYearChanged,
    required this.onMonthChanged,
  });
  final int year, month, firstYear, lastYear;
  final ValueChanged<int> onYearChanged, onMonthChanged;
  @override
  State<_CalendarMonthWheels> createState() => _CalendarMonthWheelsState();
}

class _CalendarMonthWheelsState extends State<_CalendarMonthWheels> {
  late final _year = FixedExtentScrollController(
    initialItem: widget.year - widget.firstYear,
  );
  late final _month = FixedExtentScrollController(
    initialItem: widget.month - 1,
  );
  @override
  void dispose() {
    _year.dispose();
    _month.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: CupertinoPicker.builder(
          key: const ValueKey('current-year-wheel'),
          scrollController: _year,
          itemExtent: 34,
          childCount: widget.lastYear - widget.firstYear + 1,
          onSelectedItemChanged: (index) =>
              widget.onYearChanged(widget.firstYear + index),
          itemBuilder: (context, index) =>
              Center(child: Text('${widget.firstYear + index}年')),
        ),
      ),
      Expanded(
        child: CupertinoPicker.builder(
          key: const ValueKey('current-month-wheel'),
          scrollController: _month,
          itemExtent: 34,
          childCount: 12,
          onSelectedItemChanged: (index) => widget.onMonthChanged(index + 1),
          itemBuilder: (context, index) => Center(child: Text('${index + 1}月')),
        ),
      ),
    ],
  );
}
