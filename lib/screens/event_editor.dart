import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui/stair_theme.dart';

/// Registration form shared by the registration tab and event editing routes.
class EventEditor extends StatefulWidget {
  const EventEditor({required this.store, this.event, this.onSaved, super.key});

  final GiriStore store;
  final GiriEvent? event;
  final VoidCallback? onSaved;

  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _organizer = TextEditingController();
  final _venue = TextEditingController();
  final _participants = TextEditingController();
  final _siteUrl = TextEditingController();
  final _memo = TextEditingController();
  final _result = TextEditingController();
  final _placement = TextEditingController();

  EventKind _kind = EventKind.live;
  MeetingType _meetingType = MeetingType.casual;
  EventStatus _status = EventStatus.planned;
  DateTime? _startsAt;
  DateTime? _endsAt;
  DateTime? _submissionStart;
  DateTime? _submissionEnd;
  DateTime? _votingStart;
  DateTime? _votingEnd;
  bool _saving = false;
  String? _scheduleError;

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  @override
  void didUpdateWidget(covariant EventEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event?.id != widget.event?.id) _loadEvent();
  }

  void _loadEvent() {
    final event = widget.event;
    _title.text = event?.title ?? '';
    _organizer.text = event?.organizer ?? '';
    _venue.text = event?.venue ?? '';
    _participants.text = event?.participants.join('、') ?? '';
    _siteUrl.text = event?.siteUrl ?? '';
    _memo.text = event?.memo ?? '';
    _result.text = event?.resultText ?? '';
    _placement.text = event?.placement?.toString() ?? '';
    _kind = event?.kind ?? EventKind.live;
    _meetingType = event?.meetingType ?? MeetingType.casual;
    _status = event?.status ?? EventStatus.planned;
    _startsAt = event?.startsAt;
    _endsAt = event?.endsAt;
    _submissionStart = event?.submissionStart;
    _submissionEnd = event?.submissionEnd;
    _votingStart = event?.votingStart;
    _votingEnd = event?.votingEnd;
    _scheduleError = null;
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _organizer,
      _venue,
      _participants,
      _siteUrl,
      _memo,
      _result,
      _placement,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(
    DateTime? current,
    ValueChanged<DateTime?> onChanged,
  ) async {
    final initial = (current ?? DateTime.now()).toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: '日付を選択',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '時刻を選択',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
      _scheduleError = null;
    });
  }

  String? _validateSchedule() {
    if (_kind == EventKind.live) {
      if (_startsAt != null &&
          _endsAt != null &&
          !_endsAt!.isAfter(_startsAt!)) {
        return '終了日時は開始日時より後にしてください。';
      }
      return null;
    }
    for (final range in [
      ('投稿', _submissionStart, _submissionEnd),
      ('投票', _votingStart, _votingEnd),
    ]) {
      if ((range.$2 == null) != (range.$3 == null)) {
        return '${range.$1}期間は開始・終了の両方を入力してください。';
      }
      if (range.$2 != null && !range.$3!.isAfter(range.$2!)) {
        return '${range.$1}の終了日時は開始日時より後にしてください。';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final formValid = _formKey.currentState!.validate();
    final scheduleError = _validateSchedule();
    setState(() => _scheduleError = scheduleError);
    if (!formValid || scheduleError != null) return;
    final participants = _participants.text
        .split(RegExp(r'[,、，\n]'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    final original = widget.event;
    final event = GiriEvent(
      id: original?.id ?? widget.store.newId(),
      title: _title.text.trim(),
      kind: _kind,
      meetingType: _meetingType,
      createdAt: original?.createdAt ?? DateTime.now(),
      organizer: _organizer.text.trim(),
      venue: _kind == EventKind.live ? _venue.text.trim() : '',
      participants: _kind == EventKind.live ? participants : const [],
      startsAt: _kind == EventKind.live ? _startsAt : null,
      endsAt: _kind == EventKind.live ? _endsAt : null,
      submissionStart: _kind == EventKind.online ? _submissionStart : null,
      submissionEnd: _kind == EventKind.online ? _submissionEnd : null,
      votingStart: _kind == EventKind.online ? _votingStart : null,
      votingEnd: _kind == EventKind.online ? _votingEnd : null,
      siteUrl: _kind == EventKind.online ? _siteUrl.text.trim() : '',
      status: _status,
      memo: _memo.text.trim(),
      resultText: _meetingType == MeetingType.tournament
          ? _result.text.trim()
          : '',
      placement: _meetingType == MeetingType.tournament
          ? int.tryParse(_placement.text.trim())
          : null,
    );
    setState(() => _saving = true);
    try {
      await widget.store.saveEvent(event);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('記録を保存しました')));
      if (original == null) {
        _formKey.currentState!.reset();
        setState(_loadEvent);
      }
      widget.onSaved?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存できませんでした。入力内容を残しています。もう一度お試しください。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, List<Widget> children) {
    final (icon, accent) = switch (title) {
      '形式' => (Icons.category_outlined, StairColors.live),
      '基本情報' => (Icons.edit_calendar_outlined, StairColors.live),
      '会場・日時' => (Icons.place_outlined, StairColors.venue),
      'サイト・スケジュール' => (Icons.language, StairColors.online),
      '大会の結果' => (Icons.emoji_events_outlined, StairColors.result),
      _ => (Icons.notes_outlined, StairColors.memo),
    };
    return StairSection(
      title: title,
      icon: icon,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    String? helperText,
    bool multiline = false,
    int? minLines,
    int? maxLines = 1,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    String? suffixText,
    FormFieldValidator<String>? validator,
  }) => StairFieldRow(
    label: label,
    multiline: multiline,
    child: Semantics(
      label: label,
      child: TextFormField(
        controller: controller,
        enabled: !_saving,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        decoration: InputDecoration(
          hintText: hintText,
          helperText: helperText,
          helperMaxLines: 2,
          suffixText: suffixText,
        ),
        validator: validator,
      ),
    ),
  );

  Widget _dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) => StairFieldRow(
    label: label,
    child: Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: _saving ? null : () => _pickDate(value, onChanged),
            style: TextButton.styleFrom(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(44, 44),
              foregroundColor: value == null
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onSurface,
            ),
            child: Semantics(
              label: label,
              child: Text(formatEventDate(value), textAlign: TextAlign.right),
            ),
          ),
        ),
        if (value != null)
          IconButton(
            tooltip: '$labelをクリア',
            onPressed: _saving
                ? null
                : () => setState(() {
                    onChanged(null);
                    _scheduleError = null;
                  }),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
            child: Text(
              '予定や参加記録を登録。結果・参加者は後から追加できます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _section('形式', [
            SegmentedButton<EventKind>(
              segments: const [
                ButtonSegment(
                  value: EventKind.live,
                  label: Text('生大喜利'),
                  icon: Icon(Icons.groups_outlined),
                ),
                ButtonSegment(
                  value: EventKind.online,
                  label: Text('ネット大喜利'),
                  icon: Icon(Icons.language),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _kind = value.first;
                      _scheduleError = null;
                    }),
            ),
            const SizedBox(height: 10),
            SegmentedButton<MeetingType>(
              segments: const [
                ButtonSegment(value: MeetingType.casual, label: Text('通常会')),
                ButtonSegment(value: MeetingType.tournament, label: Text('大会')),
              ],
              selected: {_meetingType},
              onSelectionChanged: _saving
                  ? null
                  : (value) => setState(() => _meetingType = value.first),
            ),
          ]),
          _section('基本情報', [
            _textField(
              label: 'タイトル *',
              controller: _title,
              hintText: '会・大会の名前',
              textInputAction: TextInputAction.next,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'タイトルを入力してください'
                  : null,
            ),
            const Divider(height: 1),
            _textField(
              label: '主催者',
              controller: _organizer,
              hintText: '未入力',
              textInputAction: TextInputAction.next,
            ),
            const Divider(height: 1),
            StairFieldRow(
              label: '参加状態',
              child: DropdownButtonFormField<EventStatus>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: EventStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(eventStatusLabel(status)),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _status = value);
                      },
              ),
            ),
          ]),
          if (_kind == EventKind.live)
            _section('会場・日時', [
              _textField(label: '会場', controller: _venue, hintText: '未入力'),
              const Divider(height: 1),
              _dateField('開始日時', _startsAt, (value) => _startsAt = value),
              const Divider(height: 1),
              _dateField('終了日時', _endsAt, (value) => _endsAt = value),
              const Divider(height: 1),
              _textField(
                label: '参加者',
                controller: _participants,
                multiline: true,
                minLines: 2,
                maxLines: 5,
                hintText: '名前を「、」または改行で区切って入力',
                helperText: '後から追加できます。',
              ),
            ])
          else
            _section('サイト・スケジュール', [
              _textField(
                label: 'サイトURL',
                controller: _siteUrl,
                hintText: 'https://',
                keyboardType: TextInputType.url,
              ),
              const Divider(height: 1),
              _dateField(
                '投稿開始',
                _submissionStart,
                (value) => _submissionStart = value,
              ),
              const Divider(height: 1),
              _dateField(
                '投稿締切',
                _submissionEnd,
                (value) => _submissionEnd = value,
              ),
              const Divider(height: 1),
              _dateField('投票開始', _votingStart, (value) => _votingStart = value),
              const Divider(height: 1),
              _dateField('投票締切', _votingEnd, (value) => _votingEnd = value),
              const SizedBox(height: 8),
              Text(
                '投稿期間中の会は「思考」に表示されます。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          if (_scheduleError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
              child: Text(
                _scheduleError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_meetingType == MeetingType.tournament)
            _section('大会の結果', [
              _textField(
                label: '結果',
                controller: _result,
                hintText: '優勝・予選敗退など',
              ),
              const Divider(height: 1),
              _textField(
                label: '順位（任意）',
                controller: _placement,
                keyboardType: TextInputType.number,
                hintText: '未入力',
                suffixText: '位',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final number = int.tryParse(value.trim());
                  return number == null || number < 1
                      ? '1以上の整数を入力してください'
                      : null;
                },
              ),
            ]),
          _section('振り返り', [
            _textField(
              label: 'メモ',
              controller: _memo,
              multiline: true,
              minLines: 3,
              maxLines: 8,
              hintText: '気づいたことや振り返りを残す',
            ),
          ]),
          const SizedBox(height: 14),
          StairSaveButton(
            onPressed: _saving ? null : _save,
            label: '記録を保存',
            saving: _saving,
          ),
        ],
      ),
    ),
  );
}

String formatEventDate(DateTime? value) {
  if (value == null) return '未設定';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String eventStatusLabel(EventStatus status) => switch (status) {
  EventStatus.planned => '参加予定',
  EventStatus.attended => '参加済み',
  EventStatus.canceled => 'キャンセル',
};
