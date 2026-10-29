import 'package:flutter/material.dart';

import '../models.dart';
import '../tournament_presentation.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import 'stage_name_row.dart';

/// A stage advancement and a prompt's score are distinct records.
class ResultStageEditor extends StatelessWidget {
  const ResultStageEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.allowName = true,
    this.team = false,
  });
  final ResultStage value;
  final ValueChanged<ResultStage> onChanged;
  final bool enabled;
  final bool allowName;
  final bool team;

  Widget _number({
    required String field,
    required String label,
    required String? initialValue,
    required ValueChanged<String> onChanged,
    bool decimal = false,
    bool zero = false,
    String? suffix,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: TextFormField(
      key: ValueKey('result-${value.id}-$field'),
      initialValue: initialValue,
      enabled: enabled,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      style: StairTypography.role(StairTextRole.input),
      decoration: InputDecoration(hintText: label, suffixText: suffix),
      onChanged: onChanged,
      validator: (text) {
        if (text == null || text.trim().isEmpty) return null;
        final number = decimal
            ? double.tryParse(text.trim())
            : int.tryParse(text.trim());
        if (number == null || !number.isFinite || number < (zero ? 0 : 1)) {
          return zero ? '0以上の数値を入力してください' : '1以上の整数を入力してください';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (allowName)
        StageNameRow(
          label: '段階',
          value: value.name,
          accent: StairColors.result,
          onChanged: enabled
              ? (name) => onChanged(value.copyWith(name: name))
              : null,
        ),
      if (value.roundId == null)
        StairMenuRow<TournamentOutcome>(
          key: ValueKey('event-stage-outcome-${value.id}'),
          label: '結果',
          accent: StairColors.result,
          value: value.outcome,
          items: {
            for (final outcome in TournamentOutcome.values)
              outcome: tournamentOutcomeLabel(outcome),
          },
          onChanged: enabled
              ? (outcome) => onChanged(value.copyWith(outcome: outcome))
              : null,
        ),
      _number(
        field: 'placement',
        label: value.roundId == null ? 'この段階の順位（任意）' : 'このお題の順位（任意）',
        initialValue: value.placement?.toString(),
        suffix: '位',
        onChanged: (text) => onChanged(value.copyWith(placement: int.tryParse(text.trim()))),
      ),
      if (team) ...[
        _number(
          field: 'team-placement',
          label: 'チーム順位（任意）',
          initialValue: value.teamPlacement?.toString(),
          suffix: '位',
          onChanged: (text) => onChanged(value.copyWith(teamPlacement: int.tryParse(text.trim()))),
        ),
        _number(
          field: 'individual-placement',
          label: '個人順位（任意）',
          initialValue: value.individualPlacement?.toString(),
          suffix: '位',
          onChanged: (text) => onChanged(value.copyWith(individualPlacement: int.tryParse(text.trim()))),
        ),
      ],
      _number(
        field: 'voters',
        label: '投票人数（任意）',
        initialValue: value.voterCount?.toString(),
        suffix: '人',
        zero: true,
        onChanged: (text) => onChanged(value.copyWith(voterCount: int.tryParse(text.trim()))),
      ),
      _number(
        field: 'points',
        label: '得点（任意）',
        initialValue: value.points?.toString(),
        suffix: '点',
        zero: true,
        decimal: true,
        onChanged: (text) => onChanged(value.copyWith(points: double.tryParse(text.trim()))),
      ),
      StairMenuRow<int>(
        label: '1人あたりの満点',
        value: value.maxPointsPerVoter,
        info: '得点 ÷（投票人数 × 1人あたりの満点）で得票率を計算します。',
        items: {
          for (var points = 1; points <= 10; points++) points: '$points点',
          if (value.maxPointsPerVoter > 10)
            value.maxPointsPerVoter: '${value.maxPointsPerVoter}点',
        },
        onChanged: enabled
            ? (points) => onChanged(value.copyWith(maxPointsPerVoter: points))
            : null,
      ),
      StairFormRow(
        label: '得票率',
        child: Text(
          value.voteRate == null ? '—' : '${value.voteRate!.toStringAsFixed(2)}%',
          textAlign: TextAlign.right,
          style: StairTypography.role(StairTextRole.dateValue),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextFormField(
          key: ValueKey('event-stage-memo-${value.id}'),
          initialValue: value.memo,
          enabled: enabled,
          style: StairTypography.role(StairTextRole.input),
          decoration: const InputDecoration(hintText: '対戦・回答などのメモ'),
          minLines: 2,
          maxLines: 5,
          onChanged: (memo) => onChanged(value.copyWith(memo: memo)),
        ),
      ),
    ],
  );
}
