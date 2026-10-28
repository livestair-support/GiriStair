import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
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
  bool _upcomingOnly = false;

  DateTime? _relevantDate(GiriEvent event, DateTime now) {
    if (event.kind == EventKind.live) {
      return event.endsAt ?? event.startsAt ?? event.eventDate;
    }
    final deadlines = [
      event.submissionEnd,
      event.votingEnd,
    ].whereType<DateTime>().toList()..sort();
    final upcoming = deadlines.where((date) => !date.isBefore(now));
    if (upcoming.isNotEmpty) return upcoming.first;
    return deadlines.isEmpty ? null : deadlines.last;
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
            if (_upcomingOnly) {
              if (event.status != EventStatus.planned) return false;
              final date = _relevantDate(event, now);
              final dateOnly =
                  event.kind == EventKind.live &&
                  event.startsAt == null &&
                  event.endsAt == null &&
                  event.eventDate != null;
              final cutoff = dateOnly
                  ? DateTime(now.year, now.month, now.day)
                  : now;
              if (date != null && date.isBefore(cutoff)) return false;
            }
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
            return _upcomingOnly
                ? aDate.compareTo(bDate)
                : bDate.compareTo(aDate);
          });
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          StairFormSection(
            title: '表示・検索',
            icon: CupertinoIcons.slider_horizontal_3,
            accent: StairColors.online,
            children: [
              StairMenuRow<bool>(
                key: const ValueKey('list-display-filter'),
                label: '表示',
                accent: StairColors.online,
                value: _upcomingOnly,
                items: const {false: 'すべての記録', true: '予定・締切'},
                onChanged: (value) => setState(() => _upcomingOnly = value),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
              child: Column(
                children: [
                  const StairIconBadge(
                    icon: Icons.event_note_outlined,
                    accent: StairColors.online,
                    size: 38,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.store.events.isEmpty
                        ? '記録がありません'
                        : '該当する記録がありません',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          for (final event in events)
            StairCard(
              accent: event.kind == EventKind.live
                  ? StairColors.live
                  : StairColors.online,
              padding: EdgeInsets.zero,
              child: InkWell(
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => EventDetailScreen(
                      store: widget.store,
                      eventId: event.id,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StairSectionTitle(
                        title: event.title,
                        icon: event.kind == EventKind.live
                            ? Icons.groups_outlined
                            : Icons.language,
                        accent: event.kind == EventKind.live
                            ? StairColors.live
                            : StairColors.online,
                        trailing: Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        if (event.submissionEnd != null)
                          Text('投稿締切 ${formatEventDate(event.submissionEnd)}'),
                        if (event.votingEnd != null)
                          Text('投票締切 ${formatEventDate(event.votingEnd)}'),
                        if (event.submissionEnd == null &&
                            event.votingEnd == null)
                          const Text('スケジュール未設定'),
                      ],
                      if (event.resultText.isNotEmpty ||
                          event.placement != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          [
                            if (event.placement != null) '${event.placement}位',
                            if (event.resultText.isNotEmpty) event.resultText,
                          ].join(' · '),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('この記録を削除しますか？'),
        content: const Text('参加記録は削除されます。ひもづいている思考メモは独立したメモとして残ります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除できませんでした。もう一度お試しください。')),
        );
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
                        MaterialPageRoute(
                          builder: (context) => EventEditor(
                            store: widget.store,
                            event: event,
                            onSaved: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                icon: const Icon(Icons.edit_outlined),
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
                        ? Icons.groups_outlined
                        : Icons.language,
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
                      icon: Icons.place_outlined,
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
                      icon: Icons.language,
                      accent: StairColors.online,
                      child: Column(
                        children: [
                          _line('サイトURL', event.siteUrl),
                          const Divider(height: 1),
                          _line('投稿開始', formatEventDate(event.submissionStart)),
                          const Divider(height: 1),
                          _line('投稿締切', formatEventDate(event.submissionEnd)),
                          const Divider(height: 1),
                          _line('投票開始', formatEventDate(event.votingStart)),
                          const Divider(height: 1),
                          _line('投票締切', formatEventDate(event.votingEnd)),
                        ],
                      ),
                    ),
                  if (event.meetingType == MeetingType.tournament)
                    StairSection(
                      title: '大会の結果',
                      icon: Icons.emoji_events_outlined,
                      accent: StairColors.result,
                      child: Column(
                        children: [
                          _line('結果', event.resultText),
                          const Divider(height: 1),
                          _line(
                            '順位',
                            event.placement == null
                                ? ''
                                : '${event.placement}位',
                          ),
                        ],
                      ),
                    ),
                  StairSection(
                    title: '振り返り',
                    icon: Icons.notes_outlined,
                    accent: StairColors.memo,
                    child: _line('メモ', event.memo, multiline: true),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _deleting ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_deleting ? '削除中…' : 'この記録を削除'),
                  ),
                ],
              ),
      );
    },
  );
}
