import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui/stair_theme.dart';
import 'event_editor.dart';
import 'event_list.dart';

enum _ResultFilter { all, recorded, unrecorded }

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({required this.store, super.key});

  final GiriStore store;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  EventKind? _kind;
  _ResultFilter _filter = _ResultFilter.all;

  bool _hasResult(GiriEvent event) =>
      event.resultText.trim().isNotEmpty || event.placement != null;

  DateTime _eventDate(GiriEvent event) =>
      event.startsAt ??
      (event.kind == EventKind.live ? event.eventDate : null) ??
      event.votingEnd ??
      event.submissionEnd ??
      event.createdAt;

  Widget _count(String label, int value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 5),
        Text('$value 件', style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const StairPageHeader(
      title: '戦績',
      icon: Icons.emoji_events_outlined,
      accent: StairColors.result,
    ),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final tournaments = widget.store.events
            .where(
              (event) =>
                  event.meetingType == MeetingType.tournament &&
                  event.status != EventStatus.canceled &&
                  (_kind == null || event.kind == _kind),
            )
            .toList();
        final recorded = tournaments.where(_hasResult).length;
        final events = tournaments.where((event) {
          return switch (_filter) {
            _ResultFilter.all => true,
            _ResultFilter.recorded => _hasResult(event),
            _ResultFilter.unrecorded => !_hasResult(event),
          };
        }).toList()..sort((a, b) => _eventDate(b).compareTo(_eventDate(a)));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
            Text(
              '大会の結果や順位を、記録から追記できます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            StairSection(
              title: '表示する大会',
              icon: Icons.tune,
              accent: StairColors.result,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        label: const Text('すべて'),
                        selected: _kind == null,
                        onSelected: (_) => setState(() => _kind = null),
                      ),
                      ChoiceChip(
                        label: const Text('生大喜利'),
                        selected: _kind == EventKind.live,
                        onSelected: (_) =>
                            setState(() => _kind = EventKind.live),
                      ),
                      ChoiceChip(
                        label: const Text('ネット大喜利'),
                        selected: _kind == EventKind.online,
                        onSelected: (_) =>
                            setState(() => _kind = EventKind.online),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final filter in _ResultFilter.values)
                        ChoiceChip(
                          label: Text(switch (filter) {
                            _ResultFilter.all => 'すべての結果',
                            _ResultFilter.recorded => '結果あり',
                            _ResultFilter.unrecorded => '未入力',
                          }),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            StairCard(
              accent: StairColors.result,
              child: Row(
                children: [
                  _count('結果入力済み', recorded),
                  const SizedBox(width: 16),
                  _count('結果未入力', tournaments.length - recorded),
                ],
              ),
            ),
            const SizedBox(height: 18),
            StairSectionTitle(
              title: '大会の記録',
              icon: Icons.emoji_events_outlined,
              accent: StairColors.result,
              trailing: Text(
                '${events.length}件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 6),
            if (events.isEmpty)
              StairCard(
                accent: StairColors.result,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const StairIconBadge(
                      icon: Icons.emoji_events_outlined,
                      accent: StairColors.result,
                      size: 38,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      tournaments.isEmpty ? '大会の記録はこれから' : '該当する結果がありません',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tournaments.isEmpty
                          ? '「登録」で大会を選ぶと、ここに参加予定や結果が並びます。'
                          : '結果の絞り込みを変えてみてください。',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            for (final event in events)
              StairCard(
                accent: StairColors.result,
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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            StairIconBadge(
                              icon: event.kind == EventKind.live
                                  ? Icons.groups_outlined
                                  : Icons.language,
                              accent: event.kind == EventKind.live
                                  ? StairColors.live
                                  : StairColors.online,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                event.kind == EventKind.live
                                    ? '生大喜利'
                                    : 'ネット大喜利',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                eventStatusLabel(event.status),
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          event.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          event.kind == EventKind.live
                              ? formatLiveEventDate(event)
                              : formatEventDate(
                                  event.startsAt ??
                                      event.votingEnd ??
                                      event.submissionEnd,
                                ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _hasResult(event)
                                    ? [
                                        if (event.placement != null)
                                          '${event.placement}位',
                                        if (event.resultText.trim().isNotEmpty)
                                          event.resultText,
                                      ].join(' · ')
                                    : '結果を入力する',
                                style: TextStyle(
                                  color: _hasResult(event)
                                      ? Theme.of(context).colorScheme.onSurface
                                      : StairColors.action,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
