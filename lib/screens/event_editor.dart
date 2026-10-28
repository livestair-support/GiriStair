import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../participant_import.dart';
import '../store.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import 'participant_import.dart';
import 'event_round_editor.dart';
import 'tournament_result_editor.dart';

/// Registration form shared by the registration tab and event editing routes.
class EventEditor extends StatefulWidget {
  const EventEditor({
    required this.store,
    this.event,
    this.onSaved,
    this.readImages = readParticipantImages,
    super.key,
  });

  final GiriStore store;
  final GiriEvent? event;
  final VoidCallback? onSaved;
  final Future<String?> Function() readImages;

  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _organizer = TextEditingController();
  final _venue = TextEditingController();
  final _participants = <TextEditingController>[];
  final _siteUrl = TextEditingController();
  final _memo = TextEditingController();
  final _result = TextEditingController();
  final _placement = TextEditingController();

  EventKind _kind = EventKind.live;
  MeetingType _meetingType = MeetingType.casual;
  EventStatus _status = EventStatus.planned;
  DateTime? _eventDate;
  DateTime? _startsAt;
  DateTime? _endsAt;
  List<EventRound> _rounds = [];
  TournamentResult _tournamentResult = TournamentResult();
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

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _loadEvent() {
    final event = widget.event;
    _title.text = event?.title ?? '';
    _organizer.text = event?.organizer ?? '';
    _venue.text = event?.venue ?? '';
    for (final controller in _participants) {
      controller.dispose();
    }
    _participants
      ..clear()
      ..addAll(
        (event?.participants.isNotEmpty == true
                ? event!.participants
                : const [''])
            .map((name) => TextEditingController(text: name)),
      );
    _siteUrl.text = event?.siteUrl ?? '';
    _memo.text = event?.memo ?? '';
    _result.text = event?.tournamentResult?.memo.isNotEmpty == true
        ? event!.tournamentResult!.memo
        : event?.resultText ?? '';
    _tournamentResult = event?.tournamentResult ?? TournamentResult();
    _placement.text = event?.placement?.toString() ?? '';
    _kind = event?.kind ?? EventKind.live;
    _meetingType = event?.meetingType ?? MeetingType.casual;
    _status = event?.status ?? EventStatus.planned;
    final existingDate = event?.eventDate ?? event?.startsAt ?? event?.endsAt;
    _eventDate = existingDate != null
        ? _dateOnly(existingDate)
        : event == null
        ? _dateOnly(DateTime.now())
        : null;
    _startsAt = event?.startsAt;
    _endsAt = event?.endsAt;
    _rounds = event?.effectiveRounds.toList() ?? [];
    if (event?.kind == EventKind.online && _rounds.isEmpty) {
      _rounds.add(EventRound(id: widget.store.newId(), name: '予選1回戦'));
    }
    _scheduleError = null;
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _organizer,
      _venue,
      ..._participants,
      _siteUrl,
      _memo,
      _result,
      _placement,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changeDate(DateTime? value) {
    final previous = _eventDate;
    DateTime? moveTime(DateTime? time) {
      if (time == null || value == null) return null;
      // Preserve an existing overnight end date when changing the meeting day.
      final offset = previous == null
          ? 0
          : DateTime.utc(time.year, time.month, time.day)
                .difference(
                  DateTime.utc(previous.year, previous.month, previous.day),
                )
                .inDays;
      return DateTime(
        value.year,
        value.month,
        value.day + offset,
        time.hour,
        time.minute,
      );
    }

    setState(() {
      _startsAt = moveTime(_startsAt);
      _endsAt = moveTime(_endsAt);
      _eventDate = value == null ? null : _dateOnly(value);
      _scheduleError = null;
    });
  }

  void _changeStart(DateTime? value) => setState(() {
    _startsAt = value;
    if (value != null) _eventDate ??= _dateOnly(value);
    _scheduleError = null;
  });

  void _changeEnd(DateTime? value) => setState(() {
    _endsAt = value;
    if (value != null) _eventDate ??= _dateOnly(value);
    _scheduleError = null;
  });

  String? _validateSchedule() {
    if (_kind == EventKind.live) {
      if (_startsAt != null &&
          _endsAt != null &&
          !_endsAt!.isAfter(_startsAt!)) {
        return '終了日時は開始日時より後にしてください。';
      }
      return null;
    }
    for (final round in _rounds) {
      for (final range in [
        ('投稿', round.submissionStart, round.submissionEnd),
        ('投票', round.votingStart, round.votingEnd),
      ]) {
        final prefix = _rounds.length > 1 ? '${round.name}：' : '';
        if ((range.$2 == null) != (range.$3 == null)) {
          return '$prefix${range.$1}期間は開始・終了の両方を入力してください。';
        }
        if (range.$2 != null && !range.$3!.isAfter(range.$2!)) {
          return '$prefix${range.$1}の終了日時は開始日時より後にしてください。';
        }
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final formValid = _formKey.currentState!.validate();
    final scheduleError = _validateSchedule();
    setState(() => _scheduleError = scheduleError);
    if (!formValid || scheduleError != null) return;
    final participants = _participants
        .map((controller) => controller.text.trim())
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
      eventDate: _kind == EventKind.live ? _eventDate : null,
      startsAt: _kind == EventKind.live ? _startsAt : null,
      endsAt: _kind == EventKind.live ? _endsAt : null,
      submissionStart: _kind == EventKind.online
          ? _rounds.firstOrNull?.submissionStart
          : null,
      submissionEnd: _kind == EventKind.online
          ? _rounds.firstOrNull?.submissionEnd
          : null,
      votingStart: _kind == EventKind.online
          ? _rounds.firstOrNull?.votingStart
          : null,
      votingEnd: _kind == EventKind.online
          ? _rounds.firstOrNull?.votingEnd
          : null,
      rounds: _kind == EventKind.online ? _rounds : const [],
      siteUrl: _kind == EventKind.online ? _siteUrl.text.trim() : '',
      status: _status,
      memo: _memo.text.trim(),
      resultText: _meetingType == MeetingType.tournament
          ? _result.text.trim()
          : '',
      placement: _meetingType != MeetingType.tournament
          ? null
          : switch (_tournamentResult.outcome) {
              TournamentOutcome.champion => 1,
              TournamentOutcome.runnerUp => 2,
              TournamentOutcome.placed || TournamentOutcome.unrecorded =>
                int.tryParse(_placement.text.trim()),
              _ => null,
            },
      tournamentResult: _meetingType == MeetingType.tournament
          ? _tournamentResult.copyWith(memo: _result.text.trim())
          : null,
    );
    setState(() => _saving = true);
    try {
      await widget.store.saveEvent(event);
      HapticFeedback.lightImpact();
      if (!mounted) return;
      if (original == null) {
        _formKey.currentState!.reset();
        setState(_loadEvent);
      }
      widget.onSaved?.call();
    } catch (_) {
      if (!mounted) return;
      showStairMessage(context, '保存できませんでした。入力内容を残しています。', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    Key? fieldKey,
    int? minLines,
    int? maxLines = 1,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    String? suffixText,
    FormFieldValidator<String>? validator,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Semantics(
      label: label,
      child: TextFormField(
        key: fieldKey,
        controller: controller,
        enabled: !_saving,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          hintText: label,
          suffixText: suffixText,
          constraints: const BoxConstraints(minHeight: 48),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        validator: validator,
      ),
    ),
  );

  Widget _liveTimes() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final buttons = [
          StairTimeButton(
            label: '開始',
            value: _startsAt,
            date: _eventDate,
            onChanged: _saving ? null : _changeStart,
          ),
          StairTimeButton(
            label: '終了',
            value: _endsAt,
            date: _endsAt == null ? _eventDate : _dateOnly(_endsAt!),
            onChanged: _saving ? null : _changeEnd,
          ),
        ];
        final reset = TextButton(
          onPressed: _saving
              ? null
              : () => setState(() {
                  _startsAt = null;
                  _endsAt = null;
                  _scheduleError = null;
                }),
          style: TextButton.styleFrom(
            foregroundColor: StairColors.action,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            minimumSize: const Size(44, 44),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restart_alt, size: 18),
              Text('未定', style: TextStyle(fontSize: 11)),
            ],
          ),
        );
        if (constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(17) > 21) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: buttons[0]),
                  reset,
                ],
              ),
              buttons[1],
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: buttons[0]),
            const SizedBox(width: 8),
            Expanded(child: buttons[1]),
            const SizedBox(width: 8),
            reset,
          ],
        );
      },
    ),
  );

  Future<void> _pickPastParticipants() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final entered = _participants
        .map((controller) => playerSearchKey(controller.text))
        .toSet();
    final history = widget.store.playerDirectory
        .where((player) => !entered.contains(playerSearchKey(player.name)))
        .toList();
    var query = '';
    if (history.isEmpty) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => StairCupertinoAlertDialog(
          title: const Text('プレイヤーを選ぶ'),
          content: const Text('設定の「大喜利プレイヤー一覧」に登録した人や、過去の参加者を選べます。'),
          actions: [
            StairCupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      return;
    }
    final selected = <String>{};
    final result = await showCupertinoSheet<List<String>>(
      context: context,
      topGap: 0.2,
      scrollableBuilder: (context, scrollController) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            top: false,
            child: SizedBox.expand(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Row(
                      children: [
                        CupertinoButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('キャンセル'),
                        ),
                        const Expanded(
                          child: Text(
                            'プレイヤーを選ぶ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        CupertinoButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.pop(
                                  context,
                                  history
                                      .map((player) => player.name)
                                      .where(selected.contains)
                                      .toList(),
                                ),
                          child: const Text('追加'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: '名前・フリガナで検索',
                        prefixIcon: Icon(CupertinoIcons.search, size: 20),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => query = playerSearchKey(value)),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final visible = history
                            .where(
                              (player) => playerSearchKey(
                                '${player.name} ${player.furigana}',
                              ).contains(query),
                            )
                            .toList();
                        return ListView.separated(
                          controller: scrollController,
                          itemCount: visible.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1, indent: 16),
                          itemBuilder: (context, index) {
                            final player = visible[index];
                            final name = player.name;
                            final checked = selected.contains(name);
                            return ListTile(
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: player.furigana.isEmpty
                                  ? null
                                  : Text(player.furigana),
                              dense: true,
                              trailing: Icon(
                                checked
                                    ? CupertinoIcons.check_mark_circled_solid
                                    : CupertinoIcons.circle,
                                color: checked
                                    ? StairColors.action
                                    : Theme.of(context).colorScheme.outline,
                              ),
                              selected: checked,
                              onTap: () => setSheetState(() {
                                if (!selected.add(name)) selected.remove(name);
                              }),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    _appendParticipants(result);
  }

  void _appendParticipants(List<String> names) {
    final entered = _participants
        .map((controller) => playerSearchKey(controller.text))
        .toSet();
    setState(() {
      for (final name in names) {
        if (name.trim().isEmpty || !entered.add(playerSearchKey(name))) {
          continue;
        }
        final empty = _participants
            .where((controller) => controller.text.trim().isEmpty)
            .firstOrNull;
        if (empty == null) {
          _participants.add(TextEditingController(text: name));
        } else {
          empty.text = name;
        }
      }
    });
  }

  Future<void> _importParticipants({bool images = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final names = await Navigator.of(context).push<List<String>>(
      CupertinoPageRoute(
        builder: (_) => ParticipantImportScreen(
          startWithImages: images,
          readImages: widget.readImages,
          existingNames: _participants
              .map((controller) => controller.text.trim())
              .toList(),
        ),
      ),
    );
    if (!mounted || names == null) return;
    _appendParticipants(names);
  }

  Widget _participantsSection() => StairFormSection(
    title: '参加者',
    icon: CupertinoIcons.person_2,
    accent: StairColors.online,
    trailing: Text(
      '${_participants.map((controller) => playerSearchKey(controller.text)).where((name) => name.isNotEmpty).toSet().length}人',
      key: const ValueKey('event-participant-count'),
      style: Theme.of(context).textTheme.bodySmall,
    ),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: CupertinoButton(
                key: const ValueKey('event-import-participants'),
                padding: const EdgeInsets.symmetric(vertical: 10),
                onPressed: _saving ? null : () => _importParticipants(),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.doc_text, size: 20),
                    SizedBox(width: 6),
                    Text('文字一括'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: CupertinoButton(
                key: const ValueKey('event-import-participant-images'),
                padding: const EdgeInsets.symmetric(vertical: 10),
                onPressed: _saving
                    ? null
                    : () => _importParticipants(images: true),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.doc_text_viewfinder, size: 20),
                    SizedBox(width: 6),
                    Text('OCR一括'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      for (var index = 0; index < _participants.length; index++)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '参加者${index + 1}',
                  child: TextFormField(
                    key: ValueKey('event-participant-$index'),
                    controller: _participants[index],
                    enabled: !_saving,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) {
                      if (index == _participants.length - 1) {
                        setState(
                          () => _participants.add(TextEditingController()),
                        );
                      }
                      FocusScope.of(context).nextFocus();
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      constraints: const BoxConstraints(minHeight: 44),
                      hintText: index == 0 ? '参加者名' : '参加者名を入力',
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _participants[index],
                builder: (context, value, child) {
                  if (_participants.length == 1 && value.text.isEmpty) {
                    return IconButton(
                      tooltip: 'プレイヤー一覧から選ぶ',
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _saving ? null : _pickPastParticipants,
                      icon: const Icon(CupertinoIcons.person_2, size: 22),
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    );
                  }
                  return IconButton(
                    tooltip: '参加者${index + 1}を削除',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            final removed = _participants.removeAt(index);
                            removed.dispose();
                            if (_participants.isEmpty) {
                              _participants.add(TextEditingController());
                            }
                          }),
                    icon: const Icon(CupertinoIcons.minus_circle, size: 22),
                    color: StairColors.action,
                  );
                },
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _saving
                  ? null
                  : () => setState(
                      () => _participants.add(TextEditingController()),
                    ),
              style: TextButton.styleFrom(
                foregroundColor: StairColors.action,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              ),
              icon: const Icon(CupertinoIcons.plus_circle, size: 23),
              label: const Text(
                '参加者を追加',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              ),
            ),
            TextButton(
              onPressed: _saving ? null : _pickPastParticipants,
              style: TextButton.styleFrom(
                foregroundColor: StairColors.action,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              child: const Text('一覧から選ぶ', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairPageHeader(
      title: widget.event == null ? '登録' : '記録を編集',
      icon: widget.event == null ? CupertinoIcons.add : CupertinoIcons.pencil,
      accent: StairColors.live,
      leading: widget.event == null ? null : const BackButton(),
      trailing: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _title,
        builder: (context, value, child) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const StairInfoButton(
              label: '登録',
              message: '会の予定や参加記録を保存できます。参加者は文章や画像から一括追加できます。',
            ),
            StairSaveButton(
              onPressed: value.text.trim().isEmpty || _saving ? null : _save,
              saving: _saving,
            ),
          ],
        ),
      ),
    ),
    body: Form(
      key: _formKey,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StairFormSection(
              title: '基本情報',
              icon: CupertinoIcons.slider_horizontal_3,
              accent: StairColors.live,
              children: [
                StairMenuRow<EventKind>(
                  label: '形式',
                  value: _kind,
                  items: const {
                    EventKind.live: '生大喜利',
                    EventKind.online: 'ネット大喜利',
                  },
                  info: '生大喜利は会場や参加者、ネット大喜利は投稿・投票期間を記録できます。',
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _kind = value;
                          if (value == EventKind.online && _rounds.isEmpty) {
                            _rounds.add(
                              EventRound(
                                id: widget.store.newId(),
                                name: '予選1回戦',
                              ),
                            );
                          }
                          _scheduleError = null;
                        }),
                ),
                StairMenuRow<MeetingType>(
                  label: '会の種類',
                  value: _meetingType,
                  items: const {
                    MeetingType.casual: '通常会',
                    MeetingType.tournament: '大会',
                  },
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _meetingType = value),
                ),
                StairMenuRow<EventStatus>(
                  label: '参加状況',
                  value: _status,
                  items: {
                    for (final status in EventStatus.values)
                      status: eventStatusLabel(status),
                  },
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _status = value),
                ),
                _textField(
                  label: '会・大会名 *',
                  controller: _title,
                  fieldKey: const ValueKey('event-title'),
                  textInputAction: TextInputAction.next,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'タイトルを入力してください'
                      : null,
                ),
                _textField(
                  label: '主催者',
                  controller: _organizer,
                  fieldKey: const ValueKey('event-organizer'),
                  textInputAction: TextInputAction.next,
                ),
                if (_kind == EventKind.live) ...[
                  StairDateRow(
                    label: '日付',
                    value: _eventDate,
                    dateOnly: true,
                    onChanged: _saving ? null : _changeDate,
                  ),
                  _liveTimes(),
                  if (_endsAt != null)
                    StairDateRow(
                      label: '終了日',
                      value: _dateOnly(_endsAt!),
                      dateOnly: true,
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) {
                                _changeEnd(null);
                                return;
                              }
                              _changeEnd(
                                DateTime(
                                  value.year,
                                  value.month,
                                  value.day,
                                  _endsAt!.hour,
                                  _endsAt!.minute,
                                ),
                              );
                            },
                    ),
                  _textField(
                    label: '会場名',
                    controller: _venue,
                    fieldKey: const ValueKey('event-venue'),
                  ),
                ] else
                  _textField(
                    label: 'サイトURL',
                    controller: _siteUrl,
                    fieldKey: const ValueKey('event-url'),
                    keyboardType: TextInputType.url,
                  ),
              ],
            ),
            if (_kind == EventKind.live)
              _participantsSection()
            else
              EventRoundEditor(
                rounds: _rounds,
                enabled: !_saving,
                newId: widget.store.newId,
                onChanged: (rounds) => setState(() {
                  _rounds = rounds;
                  _scheduleError = null;
                }),
              ),
            if (_scheduleError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
                child: Text(
                  _scheduleError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_meetingType == MeetingType.tournament)
              TournamentResultEditor(
                value: _tournamentResult,
                placement: _placement,
                memo: _result,
                enabled: !_saving,
                newId: widget.store.newId,
                onChanged: (result) =>
                    setState(() => _tournamentResult = result),
              ),
            StairFormSection(
              title: '振り返り',
              icon: CupertinoIcons.text_alignleft,
              accent: StairColors.memo,
              children: [
                _textField(
                  label: '気づいたことや振り返りを残す',
                  controller: _memo,
                  fieldKey: const ValueKey('event-memo'),
                  minLines: 3,
                  maxLines: 8,
                ),
              ],
            ),
          ],
        ),
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
