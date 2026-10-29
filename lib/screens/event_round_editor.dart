import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../scheduling.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import 'stage_name_row.dart';

class EventRoundEditor extends StatefulWidget {
  const EventRoundEditor({
    super.key,
    required this.rounds,
    required this.onChanged,
    required this.newId,
    this.enabled = true,
    this.tournament = true,
    this.preferences = const AppPreferences(),
    this.initialDate,
    this.autoFillRoundIds = const {},
    this.automaticFields,
    this.onAutomaticFieldsChanged,
  });

  final List<EventRound> rounds;
  final ValueChanged<List<EventRound>> onChanged;
  final String Function() newId;
  final bool enabled;
  final bool tournament;
  final AppPreferences preferences;
  final DateTime? initialDate;
  final Set<String> autoFillRoundIds;
  final Map<String, Set<String>>? automaticFields;
  final ValueChanged<Map<String, Set<String>>>? onAutomaticFieldsChanged;

  @override
  State<EventRoundEditor> createState() => _EventRoundEditorState();
}

class _EventRoundEditorState extends State<EventRoundEditor> {
  List<EventRound> get rounds => widget.rounds;
  ValueChanged<List<EventRound>> get onChanged => widget.onChanged;
  String Function() get newId => widget.newId;
  bool get enabled => widget.enabled;
  bool get tournament => widget.tournament;
  AppPreferences get preferences => widget.preferences;
  DateTime? get initialDate => widget.initialDate;
  final _automatic = <String, Set<String>>{};
  final _known = <String>{};

  void _rememberNewRounds() {
    for (final round in rounds) {
      if (_known.add(round.id)) {
        final remembered = widget.automaticFields?[round.id];
        if (remembered != null) {
          _automatic[round.id] = Set.of(remembered);
        } else if (widget.autoFillRoundIds.contains(round.id)) {
          _automatic[round.id] = {'submissionEnd', 'votingStart', 'votingEnd'};
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _rememberNewRounds();
  }

  @override
  void didUpdateWidget(covariant EventRoundEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberNewRounds();
  }

  void _submissionStart(int index, DateTime? date) {
    final old = rounds[index];
    final automatic = _automatic.putIfAbsent(old.id, () => <String>{});
    final draft = old.copyWith(
      submissionStart: date,
      submissionEnd: automatic.contains('submissionEnd') ? null : old.submissionEnd,
      votingStart: automatic.contains('votingStart') ? null : old.votingStart,
      votingEnd: automatic.contains('votingEnd') ? null : old.votingEnd,
    );
    if (date == null) { _replace(index, draft); return; }
    if (draft.submissionEnd == null) automatic.add('submissionEnd');
    if (draft.votingStart == null) automatic.add('votingStart');
    if (draft.votingEnd == null) automatic.add('votingEnd');
    _replace(index, completeRoundSchedule(draft, submissionDays: preferences.submissionDays, votingDays: preferences.votingDays));
  }

  void _submissionEnd(int index, DateTime? date) {
    final old = rounds[index];
    final automatic = _automatic.putIfAbsent(old.id, () => <String>{});
    automatic.remove('submissionEnd');
    final votingStart = automatic.contains('votingStart') ? date : old.votingStart;
    _replace(index, old.copyWith(
      submissionEnd: date,
      votingStart: votingStart,
      votingEnd: automatic.contains('votingEnd')
          ? votingStart == null ? null : addCalendarDays(votingStart, preferences.votingDays)
          : old.votingEnd,
    ));
  }

  void _votingStart(int index, DateTime? date) {
    final old = rounds[index];
    final automatic = _automatic.putIfAbsent(old.id, () => <String>{});
    automatic.remove('votingStart');
    _replace(index, old.copyWith(
      votingStart: date,
      votingEnd: automatic.contains('votingEnd')
          ? date == null ? null : addCalendarDays(date, preferences.votingDays)
          : old.votingEnd,
    ));
  }

  void _publishAutomatic() => widget.onAutomaticFieldsChanged?.call({
    for (final entry in _automatic.entries) entry.key: Set.of(entry.value),
  });

  void _replace(int index, EventRound round) {
    _publishAutomatic();
    final changed = List<EventRound>.of(rounds);
    changed[index] = round;
    onChanged(changed);
  }

  void _renameStage(int index, String name) {
    final stageId = rounds[index].effectiveStageId;
    onChanged([
      for (final round in rounds)
        if (round.effectiveStageId == stageId) round.copyWith(name: name) else round,
    ]);
  }

  void _move(int index, int offset) {
    final changed = List<EventRound>.of(rounds);
    final item = changed.removeAt(index);
    changed.insert(index + offset, item);
    onChanged(changed);
  }

  void _add({bool sameStage = false}) {
    final previous = rounds.lastOrNull;
    final next = addNextRound(
      previous,
      id: newId(),
      sameStage: sameStage,
      tournament: tournament,
      defaultStart: defaultSubmissionStart(initialDate ?? DateTime.now(), preferences),
      submissionDays: preferences.submissionDays,
      votingDays: preferences.votingDays,
    );
    _automatic[next.id] = {'submissionEnd', 'votingStart', 'votingEnd'};
    _known.add(next.id);
    _publishAutomatic();
    onChanged([...rounds, next]);
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      StairFormRow(
        label: label,
        child: Align(
          alignment: Alignment.centerRight,
          child: CupertinoSwitch(
            value: value,
            activeTrackColor: StairColors.online,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < rounds.length; index++)
        StairFormSection(
          key: ValueKey('event-round-${rounds[index].id}'),
          title: tournament ? rounds[index].name : '投稿・投票',
          icon: CupertinoIcons.calendar,
          accent: StairColors.online,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0)
                CupertinoButton(
                  minimumSize: const Size(28, 32),
                  padding: EdgeInsets.zero,
                  onPressed: enabled ? () => _move(index, -1) : null,
                  child: const Icon(CupertinoIcons.arrow_up, size: 16),
                ),
              if (index + 1 < rounds.length)
                CupertinoButton(
                  minimumSize: const Size(28, 32),
                  padding: EdgeInsets.zero,
                  onPressed: enabled ? () => _move(index, 1) : null,
                  child: const Icon(CupertinoIcons.arrow_down, size: 16),
                ),
              CupertinoButton(
                key: ValueKey('event-round-remove-${rounds[index].id}'),
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
                onPressed: enabled ? () => onChanged(List.of(rounds)..removeAt(index)) : null,
                child: const Icon(CupertinoIcons.minus_circle, size: 20),
              ),
            ],
          ),
          children: [
            if (tournament)
              StageNameRow(
                label: 'ステージ',
                value: rounds[index].name,
                onChanged: enabled ? (name) => _renameStage(index, name) : null,
              ),
            StairMenuRow<int>(
              label: 'お題',
              value: rounds[index].promptNumber,
              items: {
                for (var number = 1; number <= 20; number++) number: 'お題$number',
                if (rounds[index].promptNumber > 20)
                  rounds[index].promptNumber: 'お題${rounds[index].promptNumber}',
              },
              onChanged: enabled
                  ? (number) => _replace(index, rounds[index].copyWith(promptNumber: number))
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextFormField(
                key: ValueKey('event-round-block-${rounds[index].id}'),
                initialValue: rounds[index].block,
                enabled: enabled,
                style: StairTypography.role(StairTextRole.input),
                decoration: InputDecoration(
                  hintText: tournament ? '自分のブロック（任意）' : '所属・お題ブロック（任意）',
                ),
                onChanged: (block) => _replace(index, rounds[index].copyWith(block: block)),
              ),
            ),
            StairDateRow(
              label: '投稿開始',
              value: rounds[index].submissionStart,
              onChanged: enabled ? (date) => _submissionStart(index, date) : null,
            ),
            StairDateRow(
              label: '投稿締切',
              value: rounds[index].submissionEnd,
              onChanged: enabled
                  ? (date) => _submissionEnd(index, date)
                  : null,
            ),
            StairDateRow(
              label: '投票開始',
              value: rounds[index].votingStart,
              onChanged: enabled
                  ? (date) => _votingStart(index, date)
                  : null,
            ),
            StairDateRow(
              label: '投票締切',
              value: rounds[index].votingEnd,
              onChanged: enabled
                  ? (date) {
                      _automatic[rounds[index].id]?.remove('votingEnd');
                      _replace(index, rounds[index].copyWith(votingEnd: date));
                    }
                  : null,
            ),
            _switch('投稿する', rounds[index].submissionEnabled,
                (value) => _replace(index, rounds[index].copyWith(submissionEnabled: value))),
            _switch('投票する', rounds[index].votingRequired,
                (value) => _replace(index, rounds[index].copyWith(votingRequired: value))),
          ],
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('event-round-add'),
              onPressed: enabled ? _add : null,
              icon: const Icon(CupertinoIcons.plus_circle, size: 20),
              label: Text(tournament ? '次のステージを追加' : '投稿・投票を追加'),
            ),
            if (tournament && rounds.isNotEmpty)
              OutlinedButton.icon(
                key: const ValueKey('event-round-add-prompt'),
                onPressed: enabled ? () => _add(sameStage: true) : null,
                icon: const Icon(CupertinoIcons.plus, size: 18),
                label: const Text('同じステージにお題を追加'),
              ),
          ],
        ),
      ),
    ],
  );
}
