import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../participant_import.dart';
import '../scheduling.dart';
import '../store.dart';
import '../tournament_presentation.dart';
import '../ui/player_widgets.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import 'current_calendar.dart';
import 'event_editor.dart';
import 'event_list.dart' show formatCalendarDate;
import 'event_round_editor.dart';
import 'online_site_editor.dart';
import 'players.dart';
import 'result_entry.dart';
import 'thinking.dart';
import 'venues.dart';

String _time(DateTime? value) => value == null ? '--:--' : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _roundLabel(GiriEvent event, EventRound round) => [event.meetingType == MeetingType.tournament ? round.name : '投稿・投票', if (event.meetingType == MeetingType.tournament || round.promptNumber > 1) 'お題${round.promptNumber}', if (round.block.isNotEmpty) round.block].join(' · ');

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({required this.store, required this.eventId, this.initialRoundId, super.key});
  final GiriStore store;
  final String eventId;
  final String? initialRoundId;
  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool _working = false;
  bool _scrolled = false;
  final Map<String, GlobalKey> _roundKeys = {};
  GiriEvent? get _event => widget.store.events.where((event) => event.id == widget.eventId).firstOrNull;

  Future<void> _save(GiriEvent event, {String message = '保存しました'}) async {
    if (_working) return;
    setState(() => _working = true);
    try { await widget.store.saveEvent(event); if (mounted) showStairMessage(context, message); }
    catch (_) { if (mounted) showStairMessage(context, '保存できませんでした。もう一度お試しください。', error: true); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _join(GiriEvent event) {
    final names = List<String>.of(event.participants);
    final self = widget.store.preferences.selfName.trim();
    if (self.isNotEmpty && !names.any((name) => playerSearchKey(name) == playerSearchKey(self))) names.add(self);
    return _save(event.copyWith(isParticipating: true, status: EventStatus.planned, participants: names), message: '参加を記録しました');
  }

  void _edit(GiriEvent event) => Navigator.push<void>(context, CupertinoPageRoute(builder: (_) => EventEditor(store: widget.store, event: event, onSaved: () => Navigator.pop(context))));
  void _result(GiriEvent event, {String? roundId}) => Navigator.push<void>(context, CupertinoPageRoute(builder: (_) => ResultEntryScreen(store: widget.store, eventId: event.id, initialRoundId: roundId)));

  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(context: context, builder: (_) => StairCupertinoAlertDialog(
      title: const Text('この記録を削除しますか？'), content: const Text('ひもづいているお題と回答メモは残ります。'),
      actions: [StairCupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')), StairCupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: const Text('削除'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try { await widget.store.deleteEvent(widget.eventId); if (mounted) Navigator.pop(context); }
    catch (_) { if (mounted) showStairMessage(context, '削除できませんでした。', error: true); }
    finally { if (mounted) setState(() => _working = false); }
  }

  Future<void> _more(GiriEvent event) async {
    final action = await showCupertinoModalPopup<String>(context: context, builder: (_) => CupertinoActionSheet(
      actions: [CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, 'delete'), child: const Text('削除'))],
      cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
    ));
    if (!mounted) return;
    if (action == 'delete') await _delete();
  }

  Future<void> _url(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !const ['http', 'https'].contains(uri.scheme)) return;
    try { if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) showStairMessage(context, 'リンクを開けませんでした。', error: true); }
    catch (_) { if (mounted) showStairMessage(context, 'リンクを開けませんでした。', error: true); }
  }

  Widget _value(String label, String value, {Color? color}) => StairLabeledRow(label: label,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: SelectableText(value.isEmpty ? '未入力' : value, textAlign: TextAlign.right,
      style: StairTypography.role(StairTextRole.value, color: color ?? (value.isEmpty ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface)))),
  );

  Widget _action(String label, VoidCallback? onTap, {IconData? icon}) => CupertinoButton(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11), onPressed: onTap,
    child: Row(children: [if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 9)], Expanded(child: Text(label)), const Icon(CupertinoIcons.chevron_right, size: 15)]),
  );

  Widget _person(String name) => CupertinoButton(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), onPressed: () {
    final player = widget.store.playerByName(name);
    if (player != null) Navigator.push<void>(context, CupertinoPageRoute(builder: (_) => PlayerDetailScreen(store: widget.store, playerId: player.id)));
  }, child: Row(children: [PlayerAvatar(store: widget.store, name: name), Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge)), const Icon(CupertinoIcons.chevron_right, size: 14)]));

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) {
    final event = _event;
    final grouped = {for (final team in event?.teams ?? <GiriTeam>[]) ...team.members};
    final participants = event?.participants.where((name) => !grouped.contains(name)).toList() ?? <String>[];
    if (!_scrolled && widget.initialRoundId != null && event != null) WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchor = _roundKeys[widget.initialRoundId]?.currentContext;
      if (anchor != null && mounted) { _scrolled = true; Scrollable.ensureVisible(anchor, duration: const Duration(milliseconds: 250), alignment: .1); }
    });
    final venue = event == null ? null : widget.store.venueById(event.venueId) ?? widget.store.venueDirectory.where((venue) => venue.name == event.venue).firstOrNull;
    return Scaffold(appBar: StairNavigationBar(title: const Text('大喜利詳細'), actions: [if (event != null) ...[
      CupertinoButton(padding: const EdgeInsets.symmetric(horizontal: 12), onPressed: _working ? null : () => _more(event), child: const Icon(CupertinoIcons.ellipsis, size: 22)),
      CupertinoButton(padding: const EdgeInsets.only(right: 16), onPressed: _working ? null : () => _edit(event), child: const Text('編集')),
    ]]), body: event == null ? const Center(child: Text('この記録は削除されています。')) : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StairFormSection(title: '基本情報', icon: CupertinoIcons.info, accent: event.kind == EventKind.live ? StairColors.live : StairColors.online, children: [
        Padding(padding: const EdgeInsets.all(16), child: Text(event.title, style: StairTypography.style(const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)))),
        _value('形式', event.kind == EventKind.live ? '生大喜利' : 'ネット大喜利'), _value('会の種類', event.meetingType == MeetingType.tournament ? '大会' : '通常'),
        if (event.organizer.isNotEmpty) _value('主催者', event.organizer),
        if (!event.isParticipating) _action('この回に参加する', _working ? null : () => _join(event), icon: CupertinoIcons.plus_circle),
        if (event.isParticipating) StairMenuRow<EventStatus>(label: '参加状況', value: event.status, items: {for (final status in EventStatus.values) status: eventStatusLabel(status)}, onChanged: _working ? null : (status) => _save(event.copyWith(status: status))),
        if (event.affiliation.isNotEmpty) _value('所属', event.affiliation), if (event.block.isNotEmpty) _value('ブロック・お題', event.block),
      ]),
      if (event.kind == EventKind.live) StairFormSection(title: '会場・日時', icon: CupertinoIcons.placemark, accent: StairColors.venue, children: [
        _value('日付', formatCalendarDate(event.eventDate ?? event.startsAt), color: event.eventDate == null && event.startsAt == null ? null : calendarDateColor(context, (event.eventDate ?? event.startsAt)!)),
        _value('開始', _time(event.startsAt)), _value('終了', _time(event.endsAt)),
        if (venue == null) _value('会場', event.venue) else _action([venue.prefecture, venue.name].where((part) => part.isNotEmpty).join(' · '), () => Navigator.push<void>(context, CupertinoPageRoute(builder: (_) => VenueDetailScreen(store: widget.store, venueId: venue.id))), icon: CupertinoIcons.placemark),
      ]),
      if (event.kind == EventKind.online && (event.siteUrl.isNotEmpty || event.onlineSiteId != null)) StairFormSection(title: 'サイト', icon: CupertinoIcons.globe, accent: StairColors.online, children: [
        if (event.siteUrl.isNotEmpty) _action(event.siteUrl, () => _url(event.siteUrl), icon: CupertinoIcons.link),
        if (widget.store.onlineSiteById(event.onlineSiteId) case final site?) _action('サイト設定', () => Navigator.push<void>(context, CupertinoPageRoute(builder: (_) => OnlineSiteEditor(store: widget.store, site: site)))),
      ]),
      if (participants.isNotEmpty) StairFormSection(title: event.teams.isEmpty ? '参加者' : 'チーム未設定の参加者', icon: CupertinoIcons.person_2, accent: StairColors.online, trailing: Text('${participants.length}人', style: Theme.of(context).textTheme.bodySmall), children: [for (final name in participants) _person(name)]),
      for (final team in event.teams) StairFormSection(title: team.name.isEmpty ? 'チーム名未設定' : team.name, icon: CupertinoIcons.person_3, accent: StairColors.online, trailing: team.isMine || team.id == event.myTeamId ? const Text('自分のチーム') : null, children: [for (final name in team.members) _person(name)]),
      if (event.kind == EventKind.online) ...[
        if (event.effectiveRounds.isEmpty) StairFormSection(title: '投稿・投票', icon: CupertinoIcons.calendar, accent: StairColors.online, children: [_action('日程を追加', () => _editSchedule(event), icon: CupertinoIcons.plus_circle)]),
        for (final round in event.effectiveRounds) ...[
          Container(key: _roundKeys.putIfAbsent(round.id, () => GlobalKey()), child: _round(event, round)),
          if (event.isParticipating) RoundThoughtWorkbench(store: widget.store, eventId: event.id, roundId: round.id, showHeader: false),
        ],
        _action('日程を追加・並べ替え', _working ? null : () => _editSchedule(event), icon: CupertinoIcons.calendar_badge_plus),
      ],
      if (event.meetingType == MeetingType.tournament) StairFormSection(title: '大会の結果', icon: CupertinoIcons.rosette, accent: StairColors.result, children: [
        if (event.hasFinalResult) _value('最終結果', tournamentResultSummary(event)),
        if (!event.hasFinalResult && event.hasRecordedResult) _value('最終結果', '未入力'),
        if (!event.hasRecordedResult) Padding(padding: const EdgeInsets.all(16), child: Text(eventNeedsResult(event, DateTime.now()) ? '開催が終了しました' : '結果は未入力です', style: Theme.of(context).textTheme.bodySmall)),
        for (final stage in event.tournamentResult?.stages ?? <ResultStage>[]) _value(stage.name, _stageText(stage)),
        if (event.teams.isEmpty) ...[
          if (event.tournamentResult case final result?) ...[
            if (result.teamName.isNotEmpty) _value('チーム名', result.teamName),
            for (final name in result.members) _person(name),
          ],
        ],
        _action(event.hasRecordedResult ? '結果を編集' : '結果を入力', _working ? null : () => _result(event), icon: CupertinoIcons.pencil),
      ]),
      if (event.standings.isNotEmpty) StairFormSection(title: '大会の上位成績', icon: CupertinoIcons.rosette, accent: StairColors.result, children: [for (final standing in event.standings) ...[
        _value(standing.placement == 1 ? '優勝' : standing.placement == 2 ? '準優勝' : '${standing.placement}位', standing.teamName.isEmpty ? '個人戦' : standing.teamName),
        for (final name in standing.playerNames) _person(name), if (standing.memo.isNotEmpty) _value('メモ', standing.memo),
      ]]),
      StairFormSection(title: '振り返り', icon: CupertinoIcons.text_alignleft, accent: StairColors.memo, children: [Padding(padding: const EdgeInsets.all(16), child: SelectableText(event.memo.isEmpty ? 'メモはありません' : event.memo))]),
    ])));
  });

  String _stageText(ResultStage stage) => [resultStageSummary(stage), if (stage.teamPlacement != null) 'チーム${stage.teamPlacement}位', if (stage.individualPlacement != null) '個人${stage.individualPlacement}位', if (stage.voterCount != null && stage.points != null) '${stage.voterCount}人投票・${stage.points}点', if (stage.voteRate != null) '得票率${stage.voteRate!.toStringAsFixed(1)}%'].where((part) => part.isNotEmpty).join(' · ');

  Widget _round(GiriEvent event, EventRound round) => StairFormSection(title: _roundLabel(event, round), icon: CupertinoIcons.calendar, accent: StairColors.online, children: [
    _value('投稿開始', formatEventDate(round.submissionStart)), _value('投稿締切', formatEventDate(round.submissionEnd)), _value('投票開始', formatEventDate(round.votingStart)), _value('投票締切', formatEventDate(round.votingEnd)),
    if (event.isParticipating) ...[
      StairLabeledRow(label: '投稿に参加', child: Align(alignment: Alignment.centerRight, child: CupertinoSwitch(value: round.submissionEnabled, onChanged: _working ? null : (value) => _saveRound(event, round.copyWith(submissionEnabled: value))))),
      StairLabeledRow(label: '投票を続ける', child: Align(alignment: Alignment.centerRight, child: CupertinoSwitch(value: round.votingRequired, onChanged: _working ? null : (value) => _saveRound(event, round.copyWith(votingRequired: value))))),
    ],
    _action('日程を変更', _working ? null : () => _editSchedule(event)),
    if (event.meetingType == MeetingType.tournament) _action('このお題・段階の結果', _working ? null : () => _result(event, roundId: round.id)),
    if (!event.isParticipating) _action('参加してお題・回答を書く', _working ? null : () => _join(event), icon: CupertinoIcons.plus_circle),
  ]);

  Future<void> _saveRound(GiriEvent event, EventRound round) => _save(event.copyWith(rounds: [for (final item in event.effectiveRounds) item.id == round.id ? round : item]));
  Future<void> _editSchedule(GiriEvent event) async => Navigator.push<void>(context, CupertinoPageRoute(builder: (_) => _ScheduleEditorScreen(store: widget.store, eventId: event.id)));
}

class _ScheduleEditorScreen extends StatefulWidget {
  const _ScheduleEditorScreen({required this.store, required this.eventId});
  final GiriStore store;
  final String eventId;
  @override
  State<_ScheduleEditorScreen> createState() => _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends State<_ScheduleEditorScreen> {
  late final GiriEvent _original = widget.store.events.firstWhere((event) => event.id == widget.eventId);
  late List<EventRound> _rounds = List.of(_original.effectiveRounds);
  bool _saving = false;
  Future<void> _save() async {
    if (_saving) return;
    for (final round in _rounds) {
      if ((round.submissionStart != null && round.submissionEnd != null && !round.submissionEnd!.isAfter(round.submissionStart!)) || (round.votingStart != null && round.votingEnd != null && !round.votingEnd!.isAfter(round.votingStart!))) {
        showStairMessage(context, '締切は開始より後にしてください。', error: true); return;
      }
    }
    setState(() => _saving = true);
    try {
      final latest = widget.store.events.where((event) => event.id == widget.eventId).firstOrNull;
      if (latest == null) return;
      await widget.store.saveEvent(latest.copyWith(rounds: _rounds, submissionStart: null, submissionEnd: null, votingStart: null, votingEnd: null));
      if (mounted) Navigator.pop(context);
    } catch (_) { if (mounted) showStairMessage(context, '日程を保存できませんでした。', error: true); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: StairNavigationBar(title: const Text('投稿・投票の日程'), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: StairSaveButton(onPressed: _saving ? null : _save, saving: _saving))]), body: ListView(padding: const EdgeInsets.all(16), children: [EventRoundEditor(rounds: _rounds, newId: widget.store.newId, onChanged: (rounds) => setState(() => _rounds = rounds), enabled: !_saving, tournament: _original.meetingType == MeetingType.tournament, preferences: widget.store.preferences.copyWith(submissionDays: widget.store.onlineSiteById(_original.onlineSiteId)?.submissionDays, votingDays: widget.store.onlineSiteById(_original.onlineSiteId)?.votingDays), initialDate: _original.eventDate)]));
}
