import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'stair_theme.dart';

/// A native-style choice row, shared by the registration form's menus.
class StairMenuRow<T> extends StatelessWidget {
  const StairMenuRow({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    this.onChanged,
    this.info,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T>? onChanged;
  final String? info;

  Future<void> _choose(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final selected = await showCupertinoModalPopup<T>(
      context: context,
      builder: (context) => _cupertinoTheme(
        context,
        CupertinoActionSheet(
          title: Text(label),
          actions: [
            for (final item in items.entries)
              CupertinoActionSheetAction(
                isDefaultAction: item.key == value,
                onPressed: () => Navigator.of(context).pop(item.key),
                child: Text(item.value),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
        ),
      ),
    );
    if (context.mounted && selected != null) onChanged?.call(selected);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onChanged != null,
    child: InkWell(
      onTap: onChanged == null ? null : () => _choose(context),
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
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: onChanged == null
                      ? Theme.of(context).disabledColor
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.unfold_more_rounded,
              size: 19,
              color: onChanged == null
                  ? Theme.of(context).disabledColor
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    ),
  );
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
    final selected = await _showPicker(
      context,
      label: label,
      initial: dateOnly ? DateTime(local.year, local.month, local.day) : local,
      mode: dateOnly
          ? CupertinoDatePickerMode.date
          : CupertinoDatePickerMode.dateAndTime,
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
    child: InkWell(
      onTap: onChanged == null ? null : () => _choose(context),
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
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
                  color: value == null || onChanged == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
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
    return Wrap(
      spacing: 9,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 17, color: scheme.onSurfaceVariant),
        ),
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
                constraints: const BoxConstraints(minWidth: 70),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF36363C)
                      : const Color(0xFFE8E8ED),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  value == null ? '--:--' : _timeLabel(value!.toLocal()),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: onChanged == null
                        ? Theme.of(context).disabledColor
                        : scheme.onSurface,
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
  Widget build(BuildContext context) => IconButton(
    tooltip: '$labelの説明',
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 36, minHeight: 44),
    icon: const Icon(
      Icons.info_outline_rounded,
      size: 15,
      color: StairColors.action,
    ),
    onPressed: () => showCupertinoDialog<void>(
      context: context,
      builder: (context) => _cupertinoTheme(
        context,
        CupertinoAlertDialog(
          title: Text(label),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      ),
    ),
  );
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
}) {
  FocusScope.of(context).unfocus();
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
  data: CupertinoThemeData(
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
