import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../tournament_presentation.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import 'result_stage_editor.dart';

class TournamentResultEditor extends StatelessWidget {
  const TournamentResultEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.newId,
    required this.placement,
    required this.memo,
    this.enabled = true,
    this.rounds = const [],
    this.showStages = true,
  });

  final TournamentResult value;
  final ValueChanged<TournamentResult> onChanged;
  final String Function() newId;
  final TextEditingController placement;
  final TextEditingController memo;
  final bool enabled;
  final List<EventRound> rounds;
  final bool showStages;

  void _stage(int index, ResultStage stage) {
    final stages = List<ResultStage>.of(value.stages);
    stages[index] = stage;
    onChanged(value.copyWith(stages: stages));
  }

  Widget _field({
    required String hint,
    required Key key,
    String? initialValue,
    TextEditingController? controller,
    ValueChanged<String>? onChanged,
    bool number = false,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: TextFormField(
      key: key,
      initialValue: controller == null ? initialValue : null,
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: number ? TextInputType.number : null,
      style: StairTypography.role(StairTextRole.input),
      decoration: InputDecoration(
        hintText: hint,
        suffixText: number ? '位' : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
      ),
      validator: number
          ? (text) {
              if (text == null || text.trim().isEmpty) return null;
              final rank = int.tryParse(text.trim());
              return rank == null || rank < 1 ? '1以上の整数を入力してください' : null;
            }
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StairFormSection(
        title: '大会の結果',
        icon: CupertinoIcons.rosette,
        accent: StairColors.result,
        children: [
          StairMenuRow<TournamentOutcome>(
            key: const ValueKey('event-final-outcome'),
            label: '最終結果',
            accent: StairColors.result,
            value: value.outcome,
            items: {
              for (final outcome in TournamentOutcome.values)
                outcome: tournamentOutcomeLabel(outcome),
            },
            onChanged: enabled
                ? (outcome) {
                    if (outcome == TournamentOutcome.champion) {
                      placement.text = '1';
                    } else if (outcome == TournamentOutcome.runnerUp) {
                      placement.text = '2';
                    } else if (outcome != TournamentOutcome.placed) {
                      placement.clear();
                    }
                    onChanged(value.copyWith(outcome: outcome));
                  }
                : null,
          ),
          if (value.outcome == TournamentOutcome.placed ||
              (value.outcome == TournamentOutcome.unrecorded &&
                  placement.text.isNotEmpty))
            _field(
              key: const ValueKey('event-placement'),
              hint: '最終順位（任意）',
              controller: placement,
              number: true,
            ),
          _field(
            key: const ValueKey('event-result'),
            hint: '結果メモ',
            controller: memo,
            maxLines: 4,
          ),
        ],
      ),
      if (showStages)
      for (var index = 0; index < value.stages.length; index++)
        StairFormSection(
          key: ValueKey('event-result-stage-${value.stages[index].id}'),
          title: value.stages[index].name,
          icon: CupertinoIcons.list_number,
          accent: StairColors.result,
          trailing: CupertinoButton(
            key: ValueKey(
              'event-result-stage-remove-${value.stages[index].id}',
            ),
            minimumSize: const Size(32, 32),
            padding: EdgeInsets.zero,
            onPressed: enabled
                ? () => onChanged(
                    value.copyWith(
                      stages: List.of(value.stages)..removeAt(index),
                    ),
                  )
                : null,
            child: const Icon(CupertinoIcons.minus_circle, size: 20),
          ),
          children: [
            ResultStageEditor(
              value: value.stages[index],
              enabled: enabled,
              team: value.format != TournamentFormat.individual,
              onChanged: (stage) => _stage(index, stage),
            ),
          ],
        ),
      if (showStages)
      CupertinoButton(
        key: const ValueKey('event-result-stage-add'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        onPressed: enabled
            ? () => onChanged(
                value.copyWith(
                  stages: [
                    ...value.stages,
                    ResultStage(
                      id: newId(),
                      name: '予選${value.stages.length + 1}回戦',
                    ),
                  ],
                ),
              )
            : null,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.plus_circle, size: 22),
            SizedBox(width: 8),
            Text('段階ごとの結果を追加'),
          ],
        ),
      ),
    ],
  );
}
