import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'stair_theme.dart';
import 'stair_native_controls.dart';

/// A native-style choice row, shared by the registration form's menus.
class StairMenuRow<T> extends StatelessWidget {
  const StairMenuRow({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    this.onChanged,
    this.info,
    this.accent,
    this.selectionFeedback = false,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T>? onChanged;
  final String? info;
  final Color? accent;
  final bool selectionFeedback;

  Future<void> _choose(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final width = math.min(250.0, screen.width - 32);
    final rowHeight = math.max(
      44.0,
      MediaQuery.textScalerOf(context).scale(17) + 20,
    );
    final height = math.min(
      items.length * rowHeight + 16,
      screen.height - padding.vertical - 32,
    );
    final top = origin.dy.clamp(
      padding.top + 12,
      math.max(padding.top + 12, screen.height - padding.bottom - height - 12),
    );
    final left = (origin.dx + box.size.width - width - 16).clamp(
      16.0,
      screen.width - width - 16,
    );
    final selected = await showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'メニューを閉じる',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              alignment: Alignment.topRight,
              scale: Tween(begin: .97, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          ),
      pageBuilder: (context, animation, secondaryAnimation) => Stack(
        children: [
          Positioned(
            left: left,
            top: top.toDouble(),
            width: width,
            height: height,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.94),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shrinkWrap: true,
                      children: [
                        for (final item in items.entries)
                          Semantics(
                            selected: item.key == value,
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              minimumSize: Size(0, rowHeight),
                              onPressed: () =>
                                  Navigator.of(context).pop(item.key),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    child: item.key == value
                                        ? Icon(
                                            CupertinoIcons.check_mark,
                                            size: 18,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      item.value,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (context.mounted && selected != null && selected != value) {
      if (selectionFeedback) HapticFeedback.selectionClick();
      onChanged?.call(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (StairNativeControls.available) {
      final entries = items.entries.toList();
      return StairFormRow(
        label: label,
        info: info == null
            ? null
            : StairInfoButton(label: label, message: info!),
        child: Align(
          alignment: Alignment.centerRight,
          child: StairNativeMenu(
            label: label,
            labels: entries.map((entry) => entry.value).toList(),
            selectedIndex: entries.indexWhere((entry) => entry.key == value),
            enabled: onChanged != null,
            onSelected: (index) {
              if (selectionFeedback) HapticFeedback.selectionClick();
              onChanged?.call(entries[index].key);
            },
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      enabled: onChanged != null,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onChanged == null ? null : () => _choose(context),
        child: StairFormRow(
          label: label,
          info: info == null
              ? null
              : StairInfoButton(label: label, message: info!),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  items[value] ?? '',
                  textAlign: TextAlign.right,
                  style: StairTypography.role(
                    StairTextRole.value,
                    color: onChanged == null
                        ? Theme.of(context).disabledColor
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                CupertinoIcons.chevron_up_chevron_down,
                size: 13,
                color: onChanged == null
                    ? Theme.of(context).disabledColor
                    : accent ?? Theme.of(context).colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A calendar row that commits changes only after the picker is confirmed.
class StairDateRow extends StatelessWidget {
  const StairDateRow({
    super.key,
    required this.label,
    this.value,
    this.onChanged,
    this.dateOnly = false,
    this.info,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?>? onChanged;
  final bool dateOnly;
  final String? info;

  Future<void> _choose(BuildContext context) async {
    final current = value ?? DateTime.now();
    final local = dateOnly ? current : current.toLocal();
    final selected = dateOnly
        ? await showCupertinoDialog<_DateSelection>(
            context: context,
            barrierDismissible: true,
            builder: (context) => _CalendarDialog(label: label, initial: local),
          )
        : await _showPicker(
            context,
            label: label,
            initial: local,
            mode: CupertinoDatePickerMode.dateAndTime,
          );
    if (context.mounted && selected != null) {
      final date = selected.value;
      onChanged?.call(
        dateOnly && date != null
            ? DateTime(date.year, date.month, date.day)
            : date,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onChanged != null,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onChanged == null ? null : () => _choose(context),
      child: StairFormRow(
        label: label,
        info: info == null
            ? null
            : StairInfoButton(label: label, message: info!),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                value == null ? '未設定' : _dateLabel(value!, dateOnly: dateOnly),
                textAlign: TextAlign.right,
                style: StairTypography.role(
                  value == null ? StairTextRole.value : StairTextRole.dateValue,
                  color: value == null || onChanged == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );
}

/// A time label and capsule, matching LiveStair's compact time fields.
class StairTimeButton extends StatelessWidget {
  const StairTimeButton({
    super.key,
    required this.label,
    this.value,
    this.onChanged,
    this.date,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?>? onChanged;
  final DateTime? date;

  Future<void> _choose(BuildContext context) async {
    final local = value?.toLocal();
    final calendar = date ?? local ?? DateTime.now();
    final clock = local ?? DateTime.now();
    final selected = await _showPicker(
      context,
      label: label,
      initial: DateTime(
        calendar.year,
        calendar.month,
        calendar.day,
        clock.hour,
        clock.minute,
      ),
      mode: CupertinoDatePickerMode.time,
    );
    if (context.mounted && selected != null) {
      final time = selected.value;
      onChanged?.call(
        time == null
            ? null
            : DateTime(
                calendar.year,
                calendar.month,
                calendar.day,
                time.hour,
                time.minute,
              ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final local = value?.toLocal();
    final calendar = date ?? local ?? DateTime.now();
    final clock = local ?? DateTime.now();
    return Wrap(
      spacing: 9,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: StairTypography.role(
            StairTextRole.formLabel,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (StairNativeControls.available)
          StairNativeTime(
            label: label,
            initial: DateTime(
              calendar.year,
              calendar.month,
              calendar.day,
              clock.hour,
              clock.minute,
            ),
            hasValue: value != null,
            onChanged: onChanged,
          )
        else
          Semantics(
            label: label,
            value: value == null ? '未定' : _timeLabel(value!.toLocal()),
            button: true,
            enabled: onChanged != null,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: onChanged == null ? null : () => _choose(context),
              child: ExcludeSemantics(
                child: Container(
                  width: 70,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF36363C)
                        : const Color(0xFFE8E8ED),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    value == null ? '--:--' : _timeLabel(value!.toLocal()),
                    textAlign: TextAlign.center,
                    style:
                        StairTypography.role(
                          StairTextRole.value,
                          color: onChanged == null
                              ? Theme.of(context).disabledColor
                              : scheme.onSurface,
                        ).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class StairInfoButton extends StatelessWidget {
  const StairInfoButton({
    super.key,
    required this.label,
    required this.message,
  });

  final String label;
  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$labelの説明',
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(30, 32),
      onPressed: () => showCupertinoDialog<void>(
        context: context,
        builder: (context) => _cupertinoTheme(
          context,
          StairCupertinoAlertDialog(
            title: Text(label),
            content: Text(message),
            actions: [
              StairCupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
        ),
      ),
      child: const Icon(
        CupertinoIcons.info_circle,
        size: 15,
        color: StairColors.action,
      ),
    ),
  );
}

/// LiveStair commits a calendar day on tap and closes the calendar. Dismissing
/// without choosing a day leaves the previous value unchanged.
class _CalendarDialog extends StatefulWidget {
  const _CalendarDialog({required this.label, required this.initial});
  final String label;
  final DateTime initial;
  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends State<_CalendarDialog> {
  late final DateTime _selection = widget.initial;
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(32),
      side: BorderSide(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .28),
      ),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル', style: TextStyle(fontSize: 15)),
                  ),
                ],
              ),
            ),
            StairCalendar(
              value: _selection,
              firstDate: DateTime(math.min(1900, _selection.year)),
              lastDate: DateTime(math.max(2200, _selection.year), 12, 31),
              onDateChanged: (date) =>
                  Navigator.pop(context, _DateSelection(date)),
            ),
            const Divider(height: 1),
            Row(
              children: [
                CupertinoButton(
                  onPressed: () =>
                      Navigator.pop(context, const _DateSelection(null)),
                  child: const Text('未定に戻す', style: TextStyle(fontSize: 15)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Compact Japanese calendar using Cupertino controls rather than the
/// Material date picker's year header, ink effects and Android typography.
class StairCalendar extends StatefulWidget {
  const StairCalendar({
    super.key,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
  });

  final DateTime value;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;

  @override
  State<StairCalendar> createState() => _StairCalendarState();
}

class _StairCalendarState extends State<StairCalendar> {
  late DateTime _month = DateTime(widget.value.year, widget.value.month);
  bool _showingMonthPicker = false;
  late int _pickerYear = _month.year;
  late int _pickerMonth = _month.month;
  FixedExtentScrollController? _years;
  FixedExtentScrollController? _months;

  @override
  void dispose() {
    _years?.dispose();
    _months?.dispose();
    super.dispose();
  }

  void _toggleMonthPicker() {
    if (!_showingMonthPicker) {
      _pickerYear = _month.year;
      _pickerMonth = _month.month;
      _years?.dispose();
      _months?.dispose();
      _years = FixedExtentScrollController(
        initialItem: _pickerYear - widget.firstDate.year,
      );
      _months = FixedExtentScrollController(initialItem: _pickerMonth - 1);
    }
    setState(() => _showingMonthPicker = !_showingMonthPicker);
  }

  @override
  void didUpdateWidget(covariant StairCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value.year != widget.value.year ||
        oldWidget.value.month != widget.value.month) {
      _month = DateTime(widget.value.year, widget.value.month);
    }
  }

  void _move(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = _month.weekday % 7;
    final rows = ((days + offset) / 7).ceil();
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  key: const ValueKey('calendar-month-picker'),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  onPressed: _toggleMonthPicker,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_month.year}年${_month.month}月',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        _showingMonthPicker
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 15,
                        color: StairColors.action,
                      ),
                    ],
                  ),
                ),
              ),
              CupertinoButton(
                key: const ValueKey('calendar-previous-month'),
                padding: EdgeInsets.zero,
                onPressed: !_showingMonthPicker && _month.isAfter(firstMonth)
                    ? () => _move(-1)
                    : null,
                child: Semantics(
                  label: '前の月',
                  child: const Icon(CupertinoIcons.chevron_left, size: 21),
                ),
              ),
              CupertinoButton(
                key: const ValueKey('calendar-next-month'),
                padding: EdgeInsets.zero,
                onPressed: !_showingMonthPicker && _month.isBefore(lastMonth)
                    ? () => _move(1)
                    : null,
                child: Semantics(
                  label: '次の月',
                  child: const Icon(CupertinoIcons.chevron_right, size: 21),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_showingMonthPicker)
            _monthPicker()
          else ...[
            Row(
              children: [
                for (final weekday in const ['日', '月', '火', '水', '木', '金', '土'])
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        weekday,
                        textAlign: TextAlign.center,
                        style: StairTypography.role(StairTextRole.caption)
                            .copyWith(
                              fontWeight: FontWeight.w600,
                              color: weekday == '日'
                                  ? CupertinoColors.systemRed
                                  : weekday == '土'
                                  ? CupertinoColors.systemBlue
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var row = 0; row < rows; row++) ...[
              Row(
                children: [
                  for (var column = 0; column < 7; column++)
                    Expanded(child: _day(row * 7 + column - offset + 1, now)),
                ],
              ),
              if (row + 1 < rows) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _monthPicker() => Column(
    children: [
      SizedBox(
        height: 170,
        child: Row(
          children: [
            Expanded(
              child: CupertinoPicker(
                scrollController: _years,
                itemExtent: 32,
                onSelectedItemChanged: (value) =>
                    _pickerYear = widget.firstDate.year + value,
                children: [
                  for (
                    var year = widget.firstDate.year;
                    year <= widget.lastDate.year;
                    year++
                  )
                    Text('$year年'),
                ],
              ),
            ),
            Expanded(
              child: CupertinoPicker(
                scrollController: _months,
                itemExtent: 32,
                onSelectedItemChanged: (value) => _pickerMonth = value + 1,
                children: [
                  for (var month = 1; month <= 12; month++) Text('$month月'),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      CupertinoButton.filled(
        key: const ValueKey('calendar-apply-month'),
        borderRadius: BorderRadius.circular(24),
        onPressed: () => setState(() {
          _month = DateTime(_pickerYear, _pickerMonth);
          _showingMonthPicker = false;
        }),
        child: const Text(
          'この年月を表示',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  Widget _day(int day, DateTime now) {
    final date = DateTime(_month.year, _month.month, day);
    final isCurrentMonth = date.month == _month.month;
    final selected = DateUtils.isSameDay(date, widget.value);
    final today = DateUtils.isSameDay(date, now);
    final enabled =
        !date.isBefore(DateUtils.dateOnly(widget.firstDate)) &&
        !date.isAfter(DateUtils.dateOnly(widget.lastDate));
    return Semantics(
      label: _dateLabel(date, dateOnly: true),
      selected: selected,
      button: true,
      enabled: enabled,
      child: ExcludeSemantics(
        child: CupertinoButton(
          key: ValueKey('calendar-${date.year}-${date.month}-${date.day}'),
          minimumSize: const Size(0, 42),
          padding: EdgeInsets.zero,
          onPressed: enabled
              ? () {
                  widget.onDateChanged(date);
                }
              : null,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? StairColors.action
                  : today
                  ? StairColors.action.withValues(alpha: .16)
                  : null,
            ),
            child: Text(
              '${date.day}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: !enabled
                    ? Theme.of(context).disabledColor
                    : selected
                    ? Colors.white
                    : date.weekday == DateTime.sunday
                    ? CupertinoColors.systemRed.withValues(
                        alpha: isCurrentMonth ? 1 : .28,
                      )
                    : date.weekday == DateTime.saturday
                    ? CupertinoColors.systemBlue.withValues(
                        alpha: isCurrentMonth ? 1 : .28,
                      )
                    : !isCurrentMonth
                    ? Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .28)
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateSelection {
  const _DateSelection(this.value);

  final DateTime? value;
}

Future<_DateSelection?> _showPicker(
  BuildContext context, {
  required String label,
  required DateTime initial,
  required CupertinoDatePickerMode mode,
}) async {
  FocusScope.of(context).unfocus();
  if (StairNativeControls.available) {
    try {
      final selected = await StairNativeControls.pickDate(
        label: label,
        initial: initial,
        mode: mode == CupertinoDatePickerMode.time ? 'time' : 'dateAndTime',
        dark: Theme.of(context).brightness == Brightness.dark,
      );
      return selected == null ? null : _DateSelection(selected.value);
    } on PlatformException {
      if (!context.mounted) return null;
    } on MissingPluginException {
      if (!context.mounted) return null;
    }
  }
  if (!context.mounted) return null;
  return showCupertinoModalPopup<_DateSelection>(
    context: context,
    semanticsDismissible: true,
    builder: (context) => _cupertinoTheme(
      context,
      _DatePickerSheet(label: label, initial: initial, mode: mode),
    ),
  );
}

class _DatePickerSheet extends StatefulWidget {
  const _DatePickerSheet({
    required this.label,
    required this.initial,
    required this.mode,
  });

  final String label;
  final DateTime initial;
  final CupertinoDatePickerMode mode;

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _selection = widget.initial;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      height: math.min(380, media.size.height - media.padding.top),
      color: CupertinoColors.systemBackground.resolveFrom(context),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: CupertinoTheme.of(context).textTheme.textStyle
                        .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () =>
                      Navigator.of(context).pop(_DateSelection(_selection)),
                  child: const Text('完了'),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: widget.mode,
                initialDateTime: widget.initial,
                dateOrder: DatePickerDateOrder.ymd,
                use24hFormat: true,
                onDateTimeChanged: (value) => _selection = value,
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              onPressed: () =>
                  Navigator.of(context).pop(const _DateSelection(null)),
              child: const Text('未定に戻す'),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _cupertinoTheme(BuildContext context, Widget child) => CupertinoTheme(
  data: CupertinoTheme.of(context).copyWith(
    brightness: Theme.of(context).brightness,
    primaryColor: StairColors.action,
  ),
  child: child,
);

String _dateLabel(DateTime value, {required bool dateOnly}) {
  final date = dateOnly ? value : value.toLocal();
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final label =
      '${date.year}年${date.month}月${date.day}日(${weekdays[date.weekday - 1]})';
  return dateOnly ? label : '$label ${_timeLabel(date)}';
}

String _timeLabel(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
