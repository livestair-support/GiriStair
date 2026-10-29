import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_native_controls.dart';
import '../ui/stair_theme.dart';
import 'result_stage_editor.dart';
import 'tournament_result_editor.dart';

/// A result can be entered after the meeting without reopening registration.
class ResultEntryScreen extends StatefulWidget {
  const ResultEntryScreen({
    super.key,
    required this.store,
    required this.eventId,
    this.initialRoundId,
  });
  final GiriStore store;
  final String eventId;
  final String? initialRoundId;

  @override
  State<ResultEntryScreen> createState() => _ResultEntryScreenState();
}

class _ResultEntryScreenState extends State<ResultEntryScreen> {
  final _form = GlobalKey<FormState>();
  late final _event = widget.store.events.where((event) => event.id == widget.eventId).firstOrNull;
  late TournamentResult _result;
  late final TextEditingController _placement;
  late final TextEditingController _memo;
  late List<TournamentStanding> _standings;
  final _targets = <String, String>{};
  final _existingStageIds = <String>{};
  String? _target;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final event = _event;
    _result = event?.tournamentResult ?? TournamentResult(format: event?.tournamentFormat ?? TournamentFormat.individual);
    _placement = TextEditingController(text: event?.placement?.toString() ?? '');
    _memo = TextEditingController(text: _result.memo.isNotEmpty ? _result.memo : event?.resultText ?? '');
    _standings = List.of(event?.standings ?? const <TournamentStanding>[]);
    _existingStageIds.addAll(_result.stages.map((stage) => stage.id));
    final stages = List<ResultStage>.of(_result.stages);
    final seen = <String>{};
    for (final round in event?.effectiveRounds ?? const <EventRound>[]) {
      if (seen.add(round.effectiveStageId)) {
        final stage = stages.where((stage) => stage.roundId == null && stage.stageId == round.effectiveStageId).firstOrNull ??
            ResultStage(id: widget.store.newId(), name: round.name, stageId: round.effectiveStageId);
        if (!stages.any((saved) => saved.id == stage.id)) stages.add(stage);
        _targets['stage:${round.effectiveStageId}'] = stage.id;
      }
      final prompt = stages.where((stage) => stage.roundId == round.id).firstOrNull ??
          ResultStage(id: widget.store.newId(), name: '${round.name} お題${round.promptNumber}', roundId: round.id, stageId: round.effectiveStageId);
      if (!stages.any((saved) => saved.id == prompt.id)) stages.add(prompt);
      _targets['round:${round.id}'] = prompt.id;
    }
    for (final stage in stages) {
      if (!_targets.values.contains(stage.id)) _targets['result:${stage.id}'] = stage.id;
    }
    _result = _result.copyWith(stages: stages);
    final initial = 'round:${widget.initialRoundId}';
    _target = widget.initialRoundId != null && _targets.containsKey(initial) ? initial : _targets.keys.firstOrNull;
  }

  @override
  void dispose() {
    _placement.dispose();
    _memo.dispose();
    super.dispose();
  }

  ResultStage? get _selected => _result.stages.where((stage) => stage.id == _targets[_target]).firstOrNull;

  void _changeStage(ResultStage value) => setState(() {
    _result = _result.copyWith(stages: [
      for (final stage in _result.stages) if (stage.id == value.id) value else stage,
    ]);
  });

  void _addStage() => setState(() {
    final id = widget.store.newId();
    final stage = ResultStage(id: id, name: '予選${_result.stages.where((stage) => stage.roundId == null).length + 1}回戦');
    _result = _result.copyWith(stages: [..._result.stages, stage]);
    _targets['result:$id'] = id;
    _target = 'result:$id';
    _existingStageIds.add(id);
  });

  Future<bool> _offerVotingOnly() async {
    final previous = _event?.tournamentResult;
    final eliminated = (_result.outcome == TournamentOutcome.eliminated && previous?.outcome != TournamentOutcome.eliminated) ||
        _result.stages.any((stage) => stage.roundId == null && stage.outcome == TournamentOutcome.eliminated && previous?.stages.where((old) => old.id == stage.id).firstOrNull?.outcome != TournamentOutcome.eliminated);
    if (_event?.kind != EventKind.online || !eliminated || _event!.effectiveRounds.isEmpty) return false;
    final answer = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StairCupertinoAlertDialog(
        title: const Text('以後の投稿・投票'),
        content: const Text('以後の投稿を止め、投票の日程と通知を残しますか？'),
        actions: [
          StairCupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('そのまま')),
          StairCupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(context, true), child: const Text('投票だけにする')),
        ],
      ),
    );
    return answer == true;
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final current = widget.store.events.where((event) => event.id == widget.eventId).firstOrNull;
    if (current == null) return;
    final votingOnly = await _offerVotingOnly();
    if (!mounted) return;
    final result = _result.copyWith(
      memo: _memo.text.trim(),
      stages: _result.stages.where((stage) => stage.hasRecord || _existingStageIds.contains(stage.id)).toList(),
    );
    int? placement = int.tryParse(_placement.text.trim());
    if (result.outcome == TournamentOutcome.champion) placement = 1;
    if (result.outcome == TournamentOutcome.runnerUp) placement = 2;
    if (result.outcome == TournamentOutcome.eliminated || result.outcome == TournamentOutcome.advanced) placement = null;
    var rounds = current.rounds;
    if (votingOnly) {
      final eliminatedStages = result.stages.where((stage) => stage.roundId == null && stage.outcome == TournamentOutcome.eliminated).map((stage) => stage.stageId).whereType<String>().toSet();
      final all = current.effectiveRounds;
      var cutoff = -1;
      for (var index = 0; index < all.length; index++) {
        if (eliminatedStages.contains(all[index].effectiveStageId)) cutoff = index;
      }
      final now = DateTime.now();
      rounds = [
        for (var index = 0; index < all.length; index++)
          if ((cutoff < 0 || index > cutoff) &&
              (all[index].submissionEnd?.isAfter(now) ??
                  all[index].submissionStart?.isAfter(now) ?? false))
            all[index].copyWith(submissionEnabled: false)
          else all[index],
      ];
    }
    setState(() => _saving = true);
    try {
      await widget.store.saveEvent(current.copyWith(tournamentResult: result, placement: placement, resultText: _memo.text.trim(), standings: _standings, rounds: rounds));
      StairNativeControls.saveFeedback();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) showStairMessage(context, '結果を保存できませんでした。入力内容を残しています。', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_event == null) {
      return const Scaffold(body: Center(child: Text('記録がありません')));
    }
    final selected = _selected;
    return Scaffold(
      appBar: StairNavigationBar(title: const Text('結果を入力'), actions: [
        Padding(padding: const EdgeInsets.only(right: 12), child: StairSaveButton(onPressed: _saving ? null : _save, saving: _saving)),
      ]),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TournamentResultEditor(
              value: _result,
              placement: _placement,
              memo: _memo,
              enabled: !_saving,
              newId: widget.store.newId,
              rounds: _event!.effectiveRounds,
              showStages: false,
              onChanged: (result) => setState(() => _result = result),
            ),
            StairFormSection(
              title: '途中の結果・得点',
              icon: CupertinoIcons.list_number,
              accent: StairColors.result,
              children: [
                if (_target != null)
                  StairMenuRow<String>(
                    label: '対象', value: _target!,
                    items: {
                      for (final entry in _targets.entries)
                        entry.key: _result.stages.firstWhere((stage) => stage.id == entry.value).name,
                    },
                    onChanged: _saving ? null : (target) => setState(() => _target = target),
                  ),
                if (selected != null)
                  ResultStageEditor(
                    key: ValueKey(selected.id),
                    value: selected,
                    enabled: !_saving,
                    allowName: selected.stageId == null && selected.roundId == null,
                    team: _event!.tournamentFormat != TournamentFormat.individual || _result.format != TournamentFormat.individual,
                    onChanged: _changeStage,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextButton.icon(onPressed: _saving ? null : _addStage, icon: const Icon(CupertinoIcons.plus_circle, size: 20), label: const Text('段階の結果を追加')),
                ),
              ],
            ),
            StairFormSection(
              title: '大会全体の結果',
              icon: CupertinoIcons.rosette,
              accent: StairColors.result,
              children: [
                for (var index = 0; index < _standings.length; index++)
                  _StandingFields(
                    key: ValueKey(_standings[index].id),
                    value: _standings[index],
                    enabled: !_saving,
                    onChanged: (standing) => setState(() => _standings[index] = standing),
                    onRemove: () => setState(() => _standings.removeAt(index)),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextButton.icon(
                    key: const ValueKey('tournament-standing-add'),
                    onPressed: _saving ? null : () => setState(() => _standings.add(TournamentStanding(id: widget.store.newId(), placement: _standings.length + 1))),
                    icon: const Icon(CupertinoIcons.plus_circle, size: 20),
                    label: const Text('入賞者・入賞チームを追加'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StandingFields extends StatelessWidget {
  const _StandingFields({super.key, required this.value, required this.onChanged, required this.onRemove, required this.enabled});
  final TournamentStanding value;
  final ValueChanged<TournamentStanding> onChanged;
  final VoidCallback onRemove;
  final bool enabled;

  Widget _field(String field, String hint, String initial, ValueChanged<String> change, {bool number = false, bool multiline = false}) => TextFormField(
    key: ValueKey('standing-${value.id}-$field'),
    initialValue: initial, enabled: enabled,
    style: StairTypography.role(StairTextRole.input),
    keyboardType: number ? TextInputType.number : null,
    maxLines: multiline ? 3 : 1,
    decoration: InputDecoration(hintText: hint, suffixText: number ? '位' : null),
    onChanged: change,
    validator: number
        ? (text) => int.tryParse(text ?? '') == null || int.parse(text!) < 1 ? '1以上の順位を入力してください' : null
        : field == 'players'
        ? (text) => (text?.trim().isEmpty ?? true) && value.teamName.trim().isEmpty ? '入賞者かチーム名を入力してください' : null
        : null,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _field('placement', '順位', value.placement.toString(), (text) {
          final rank = int.tryParse(text); if (rank != null && rank > 0) onChanged(value.copyWith(placement: rank));
        }, number: true)),
        CupertinoButton(padding: EdgeInsets.zero, minimumSize: const Size(36, 40), onPressed: enabled ? onRemove : null, child: const Icon(CupertinoIcons.minus_circle, size: 20)),
      ]),
      _field('team', 'チーム名（チーム戦の場合）', value.teamName, (name) => onChanged(value.copyWith(teamName: name))),
      _field('players', '入賞者・メンバー（1行に1人）', value.playerNames.join('\n'), (text) => onChanged(value.copyWith(playerNames: text.split(RegExp(r'[\n、,]')).map((name) => name.trim()).where((name) => name.isNotEmpty).toList())), multiline: true),
      _field('memo', '補足メモ', value.memo, (memo) => onChanged(value.copyWith(memo: memo))),
    ]),
  );
}
