import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../tournament_presentation.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import 'event_editor.dart';

String formatCalendarDate(DateTime? value) {
  if (value == null) return '未設定';
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  return '${value.year}年${value.month}月${value.day}日'
      '(${weekdays[value.weekday - 1]})';
}

String formatLiveEventDate(GiriEvent event) => event.startsAt != null
    ? formatEventDate(event.startsAt)
    : event.eventDate != null
    ? '${formatCalendarDate(event.eventDate)} · 時刻未定'
    : '日付未設定';

class EventListScreen extends StatefulWidget {
  const EventListScreen({required this.store, super.key});

  final GiriStore store;

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  String _query = '';
  EventKind? _kind;
  EventStatus? _status;

  DateTime? _relevantDate(GiriEvent event, DateTime now) {
    if (event.kind == EventKind.live) {
      return event.endsAt ?? event.startsAt ?? event.eventDate;
    }
    final deadlines = [
      for (final round in event.effectiveRounds) ...[
        round.submissionEnd,
        round.votingEnd,
      ],
    ].whereType<DateTime>().toList()..sort();
    final upcoming = deadlines.where((date) => !date.isBefore(now));
    if (upcoming.isNotEmpty) return upcoming.first;
    return deadlines.isEmpty ? null : deadlines.last;
  }

  EventRound? _previewRound(GiriEvent event, DateTime now) {
    final date = _relevantDate(event, now);
    final rounds = event.effectiveRounds;
    final matching = rounds.where(
      (round) => round.submissionEnd == date || round.votingEnd == date,
    );
    return matching.firstOrNull ?? rounds.firstOrNull;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final now = DateTime.now();
      final events =
          widget.store.events.where((event) {
            if (_kind != null && event.kind != _kind) return false;
            if (_status != null && event.status != _status) return false;
            final searchable = [
              event.title,
              event.organizer,
              event.venue,
              ...event.participants,
            ].join(' ').toLowerCase();
            return searchable.contains(_query.toLowerCase());
          }).toList()..sort((a, b) {
            // Upcoming online deadlines and live dates are presented together.
            final aDate = _relevantDate(a, now);
            final bDate = _relevantDate(b, now);
            if (aDate == null && bDate == null) {
              return b.createdAt.compareTo(a.createdAt);
            }
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return bDate.compareTo(aDate);
          });
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          StairFormSection(
            title: '表示・検索',
            icon: CupertinoIcons.slider_horizontal_3,
            accent: StairColors.online,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: TextField(
                  key: const ValueKey('list-search'),
                  decoration: const InputDecoration(
                    hintText: 'タイトル・会場・主催者・参加者で検索',
                    prefixIcon: Icon(CupertinoIcons.search, size: 20),
                  ),
                  onChanged: (value) => setState(() => _query = value.trim()),
                ),
              ),
              StairMenuRow<int>(
                key: const ValueKey('list-kind-filter'),
                label: '形式',
                accent: StairColors.online,
                value: _kind?.index ?? -1,
                items: const {-1: 'すべて', 0: '生大喜利', 1: 'ネット大喜利'},
                onChanged: (value) => setState(() {
                  _kind = value == -1 ? null : EventKind.values[value];
                }),
              ),
              StairMenuRow<int>(
                key: const ValueKey('list-status-filter'),
                label: '参加状況',
                accent: StairColors.online,
                value: _status?.index ?? -1,
                items: {
                  -1: 'すべて',
                  for (final status in EventStatus.values)
                    status.index: eventStatusLabel(status),
                },
                onChanged: (value) => setState(() {
                  _status = value == -1 ? null : EventStatus.values[value];
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (events.isEmpty)
            StairCard(
              accent: StairColors.online,
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const StairIconBadge(
                      icon: CupertinoIcons.calendar,
                      accent: StairColors.online,
                      size: 38,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.store.events.isEmpty ? '記録がありません' : '該当する記録がありません',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          for (final event in events)
            StairCard(
              accent: event.kind == EventKind.live
                  ? StairColors.live
                  : StairColors.online,
              padding: EdgeInsets.zero,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).push<void>(
                  CupertinoPageRoute(
                    builder: (_) => EventDetailScreen(
                      store: widget.store,
                      eventId: event.id,
                    ),
                  ),
                ),
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyLarge!,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StairSectionTitle(
                          title: event.title,
                          icon: event.kind == EventKind.live
                              ? CupertinoIcons.person_2
                              : CupertinoIcons.globe,
                          accent: event.kind == EventKind.live
                              ? StairColors.live
                              : StairColors.online,
                          trailing: Icon(
                            CupertinoIcons.chevron_right,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${event.kind == EventKind.live ? '生大喜利' : 'ネット大喜利'}'
                          ' · ${event.meetingType == MeetingType.tournament ? '大会' : '通常会'}'
                          ' · ${eventStatusLabel(event.status)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Divider(height: 22),
                        if (event.kind == EventKind.live) ...[
                          Text(formatLiveEventDate(event)),
                          if (event.venue.isNotEmpty) Text(event.venue),
                        ] else ...[
                          if (event.effectiveRounds.isEmpty)
                            const Text('スケジュール未設定'),
                          if (event.effectiveRounds.length > 1)
                            Text('${event.effectiveRounds.length}日程'),
                          if (_previewRound(event, now) case final round?) ...[
                            if (round.name.isNotEmpty) Text(round.name),
                            if (round.submissionEnd != null)
                              Text(
                                '投稿締切 ${formatEventDate(round.submissionEnd)}',
                              ),
                            if (round.votingEnd != null)
                              Text('投票締切 ${formatEventDate(round.votingEnd)}'),
                          ],
                        ],
                        if (event.hasRecordedResult) ...[
                          const SizedBox(height: 12),
                          Text(
                            tournamentResultSummary(event),
                            style: TextStyle(
                              color: StairColors.result,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    required this.store,
    required this.eventId,
    super.key,
  });

  final GiriStore store;
  final String eventId;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool _deleting = false;

  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StairCupertinoAlertDialog(
        title: const Text('この記録を削除しますか？'),
        content: const Text('参加記録は削除されます。ひもづいている思考メモは独立したメモとして残ります。'),
        actions: [
          StairCupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          StairCupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.store.deleteEvent(widget.eventId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        showStairMessage(context, '削除できませんでした。もう一度お試しください。', error: true);
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _line(String label, String value, {bool multiline = false}) =>
      StairFieldRow(
        label: label,
        multiline: multiline,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: SelectableText(
            value.isEmpty ? '未入力' : value,
            textAlign: multiline ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              color: value.isEmpty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final matches = widget.store.events.where(
        (event) => event.id == widget.eventId,
      );
      final event = matches.isEmpty ? null : matches.first;
      return Scaffold(
        appBar: AppBar(
          title: const Text('参加記録'),
          actions: [
            if (event != null)
              IconButton(
                tooltip: '編集する',
                onPressed: _deleting
                    ? null
                    : () => Navigator.of(context).push<void>(
                        CupertinoPageRoute(
                          builder: (context) => EventEditor(
                            store: widget.store,
                            event: event,
                            onSaved: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                icon: const Icon(CupertinoIcons.pencil),
              ),
          ],
        ),
        body: event == null
            ? const Center(child: Text('この記録は削除されています。'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  StairSection(
                    title: event.title,
                    icon: event.kind == EventKind.live
                        ? CupertinoIcons.person_2
                        : CupertinoIcons.globe,
                    accent: event.kind == EventKind.live
                        ? StairColors.live
                        : StairColors.online,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${event.kind == EventKind.live ? '生大喜利' : 'ネット大喜利'} · '
                          '${event.meetingType == MeetingType.tournament ? '大会' : '通常会'} · '
                          '${eventStatusLabel(event.status)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Divider(height: 20),
                        _line('主催者', event.organizer),
                      ],
                    ),
                  ),
                  if (event.kind == EventKind.live)
                    StairSection(
                      title: '会場・日時',
                      icon: CupertinoIcons.placemark,
                      accent: StairColors.venue,
                      child: Column(
                        children: [
                          _line('会場', event.venue),
                          const Divider(height: 1),
                          if (event.eventDate != null) ...[
                            _line('日付', formatCalendarDate(event.eventDate)),
                            const Divider(height: 1),
                          ],
                          _line('開始', formatEventDate(event.startsAt)),
                          const Divider(height: 1),
                          _line('終了', formatEventDate(event.endsAt)),
                          const Divider(height: 1),
                          _line('参加者', event.participants.join('、')),
                        ],
                      ),
                    )
                  else
                    StairSection(
                      title: 'サイト・スケジュール',
                      icon: CupertinoIcons.globe,
                      accent: StairColors.online,
                      child: Column(
                        children: [
                          _line('サイトURL', event.siteUrl),
                          const Divider(height: 1),
                          for (final round in event.effectiveRounds) ...[
                            _line('段階', round.name),
                            const Divider(height: 1),
                            _line(
                              '投稿開始',
                              formatEventDate(round.submissionStart),
                            ),
                            const Divider(height: 1),
                            _line('投稿締切', formatEventDate(round.submissionEnd)),
                            const Divider(height: 1),
                            _line('投票開始', formatEventDate(round.votingStart)),
                            const Divider(height: 1),
                            _line('投票締切', formatEventDate(round.votingEnd)),
                            const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  if (event.meetingType == MeetingType.tournament)
                    StairSection(
                      title: '大会の結果',
                      icon: CupertinoIcons.rosette,
                      accent: StairColors.result,
                      child: Column(
                        children: [
                          _line('最終結果', tournamentResultSummary(event)),
                          if (event.tournamentResult case final result?) ...[
                            const Divider(height: 1),
                            _line('対戦形式', tournamentFormatLabel(result.format)),
                            if (result.teamName.isNotEmpty) ...[
                              const Divider(height: 1),
                              _line('チーム名', result.teamName),
                            ],
                            if (result.members.isNotEmpty) ...[
                              const Divider(height: 1),
                              _line(
                                'メンバー',
                                result.members.join('、'),
                                multiline: true,
                              ),
                            ],
                            for (final stage in result.stages) ...[
                              const Divider(height: 1),
                              _line(
                                stage.name,
                                resultStageSummary(stage),
                                multiline: true,
                              ),
                            ],
                            if (result.memo.isNotEmpty) ...[
                              const Divider(height: 1),
                              _line('結果メモ', result.memo, multiline: true),
                            ],
                          ],
                        ],
                      ),
                    ),
                  StairSection(
                    title: '振り返り',
                    icon: CupertinoIcons.text_alignleft,
                    accent: StairColors.memo,
                    child: _line('メモ', event.memo, multiline: true),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _deleting ? null : _delete,
                    icon: const Icon(CupertinoIcons.trash),
                    label: Text(_deleting ? '削除中…' : 'この記録を削除'),
                  ),
                ],
              ),
      );
    },
  );
}
