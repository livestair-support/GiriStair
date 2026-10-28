import 'models.dart';

String tournamentOutcomeLabel(TournamentOutcome value) => switch (value) {
  TournamentOutcome.unrecorded => '未入力',
  TournamentOutcome.champion => '優勝',
  TournamentOutcome.runnerUp => '準優勝',
  TournamentOutcome.placed => '入賞',
  TournamentOutcome.eliminated => '敗退',
  TournamentOutcome.advanced => '通過',
  TournamentOutcome.other => 'その他',
};

String tournamentFormatLabel(TournamentFormat value) => switch (value) {
  TournamentFormat.individual => '個人戦',
  TournamentFormat.pair => 'タッグ戦',
  TournamentFormat.team => 'チーム戦',
};

/// Display the explicitly entered result, without interpreting free-form prose.
String tournamentResultSummary(GiriEvent event) {
  final result = event.tournamentResult;
  final parts = <String>[];
  if (result != null && result.outcome != TournamentOutcome.unrecorded) {
    parts.add(tournamentOutcomeLabel(result.outcome));
  }
  final placement = event.effectivePlacement;
  if (placement != null &&
      result?.outcome != TournamentOutcome.champion &&
      result?.outcome != TournamentOutcome.runnerUp) {
    parts.add('$placement位');
  }
  if (event.resultText.trim().isNotEmpty) parts.add(event.resultText.trim());
  if (parts.isEmpty && result != null) {
    if (result.stages.isNotEmpty) {
      parts.add('${result.stages.length}段階の記録');
    } else if (result.memo.trim().isNotEmpty) {
      parts.add(result.memo.trim());
    }
  }
  return parts.join(' · ');
}

String resultStageSummary(ResultStage stage) => [
  if (stage.outcome != TournamentOutcome.unrecorded)
    tournamentOutcomeLabel(stage.outcome),
  if (stage.placement != null) '${stage.placement}位',
  if (stage.memo.trim().isNotEmpty) stage.memo.trim(),
].join(' · ');
