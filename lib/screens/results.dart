import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
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
      event.votingEnd ??
      event.submissionEnd ??
      event.createdAt;

  Widget _count(String label, int value) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('戦績')),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              '一戦ずつ、残していく。',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('大会の結果を振り返る場所。記録を開いて、結果や順位を追記できます。'),
            const SizedBox(height: 16),
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
                  onSelected: (_) => setState(() => _kind = EventKind.live),
                ),
                ChoiceChip(
                  label: const Text('ネット大喜利'),
                  selected: _kind == EventKind.online,
                  onSelected: (_) => setState(() => _kind = EventKind.online),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _count('結果入力済み', recorded),
                const SizedBox(width: 10),
                _count('結果未入力', tournaments.length - recorded),
              ],
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 12),
            if (events.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      const Icon(Icons.emoji_events_outlined, size: 40),
                      const SizedBox(height: 14),
                      Text(
                        tournaments.isEmpty ? '大会の記録はこれから' : '該当する結果がありません',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tournaments.isEmpty
                            ? '「登録」で大会を選ぶと、ここに参加予定や結果が並びます。'
                            : '結果の絞り込みを変えてみてください。',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            for (final event in events)
              Card(
                clipBehavior: Clip.antiAlias,
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
                        Row(
                          children: [
                            Icon(
                              event.kind == EventKind.live
                                  ? Icons.groups_outlined
                                  : Icons.language,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                event.kind == EventKind.live
                                    ? '生大喜利'
                                    : 'ネット大喜利',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                            Text(
                              eventStatusLabel(event.status),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          event.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatEventDate(
                            event.startsAt ??
                                event.votingEnd ??
                                event.submissionEnd,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _hasResult(event)
                              ? [
                                  if (event.placement != null)
                                    '${event.placement}位',
                                  if (event.resultText.trim().isNotEmpty)
                                    event.resultText,
                                ].join(' · ')
                              : '結果を入力する',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
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
