import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

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

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );

  Widget _dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _pickDate(value, onChanged),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('$label\n${formatEventDate(value)}'),
              ),
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
            icon: const Icon(Icons.close, size: 20),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.event == null ? '次の一席を、記録しよう。' : '参加記録を編集',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('予定だけでも、終わってからでも。結果や参加者は後から追加できます。'),
          const SizedBox(height: 20),
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
            const SizedBox(height: 14),
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
            TextFormField(
              controller: _title,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: 'タイトル *'),
              textInputAction: TextInputAction.next,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'タイトルを入力してください'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _organizer,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: '主催者'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<EventStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: '参加状態'),
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
          ]),
          if (_kind == EventKind.live)
            _section('会場・日時', [
              TextFormField(
                controller: _venue,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: '会場'),
              ),
              const SizedBox(height: 14),
              _dateField('開始日時', _startsAt, (value) => _startsAt = value),
              _dateField('終了日時', _endsAt, (value) => _endsAt = value),
              TextFormField(
                controller: _participants,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '参加者',
                  helperText: '「、」または改行で区切って入力。後から追加できます。',
                  helperMaxLines: 2,
                ),
              ),
            ])
          else
            _section('サイト・スケジュール', [
              TextFormField(
                controller: _siteUrl,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'サイトURL'),
              ),
              const SizedBox(height: 14),
              const Text('投稿期間を設定すると、期間中に「思考」タブへ表示されます。'),
              const SizedBox(height: 14),
              _dateField(
                '投稿開始',
                _submissionStart,
                (value) => _submissionStart = value,
              ),
              _dateField(
                '投稿締切',
                _submissionEnd,
                (value) => _submissionEnd = value,
              ),
              const SizedBox(height: 6),
              _dateField('投票開始', _votingStart, (value) => _votingStart = value),
              _dateField('投票締切', _votingEnd, (value) => _votingEnd = value),
              const Text('投稿期間と投票期間は、それぞれ独立して設定できます。'),
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
              const Text('大会が終わったら追記できます。分かる範囲の入力で大丈夫です。'),
              const SizedBox(height: 14),
              TextFormField(
                controller: _result,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: '結果',
                  hintText: '優勝、準決勝敗退、予選敗退など',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _placement,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '順位（任意）',
                  suffixText: '位',
                ),
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
            TextFormField(
              controller: _memo,
              enabled: !_saving,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'メモ'),
            ),
          ]),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_saving ? '保存中…' : '記録を保存'),
            ),
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
