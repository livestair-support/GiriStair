import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../analytics.dart';
import '../models.dart';
import '../participant_import.dart';
import '../store.dart';
import '../ui/player_widgets.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';
import 'event_list.dart';
import 'players.dart';
import 'venues.dart';

enum _RankingKind { venue, organizer, participant, site }

String _rankingTitle(_RankingKind kind) => switch (kind) {
  _RankingKind.venue => '会場別の参加回数',
  _RankingKind.organizer => '主催者別の参加回数',
  _RankingKind.participant => '一緒に参加した人',
  _RankingKind.site => 'サイト別の参加回数',
};

Color _rankingAccent(_RankingKind kind) => switch (kind) {
  _RankingKind.venue => StairColors.venue,
  _RankingKind.organizer => StairColors.memo,
  _RankingKind.participant || _RankingKind.site => StairColors.online,
};

IconData _rankingIcon(_RankingKind kind) => switch (kind) {
  _RankingKind.venue => CupertinoIcons.placemark,
  _RankingKind.organizer => CupertinoIcons.person_crop_circle,
  _RankingKind.participant => CupertinoIcons.person_2,
  _RankingKind.site => CupertinoIcons.globe,
};

class AggregateScreen extends StatefulWidget {
  const AggregateScreen({super.key, required this.store});
  final GiriStore store;

  @override
  State<AggregateScreen> createState() => _AggregateScreenState();
}

class _AggregateScreenState extends State<AggregateScreen> {
  int? _year;
  int? _month;
  EventKind? _kind;
  MeetingType? _meetingType;

  void _showEvents(String title, Iterable<GiriEvent> events) {
    Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => _AggregateEventListScreen(
          store: widget.store,
          title: title,
          eventIds: events.map((event) => event.id).toSet(),
        ),
      ),
    );
  }

  void _openEntry(_RankingKind kind, String name, GiriAnalytics stats) {
    final key = playerSearchKey(name);
    if (kind == _RankingKind.venue) {
      final venue = widget.store.venueDirectory.where(
        (venue) => playerSearchKey(venue.name) == key,
      ).firstOrNull;
      if (venue != null) {
        Navigator.of(context).push<void>(
          CupertinoPageRoute(
            builder: (_) => VenueDetailScreen(store: widget.store, venueId: venue.id),
          ),
        );
        return;
      }
      _showEvents(name, stats.live.where(
        (event) => playerSearchKey(event.venue) == key,
      ));
      return;
    }
    if (kind == _RankingKind.site) {
      _showEvents(name, stats.online.where(
        (event) => playerSearchKey(stats.siteLabel(event)) == key,
      ));
      return;
    }
    final player = widget.store.playerByName(name);
    if (player != null) {
      Navigator.of(context).push<void>(
        CupertinoPageRoute(
          builder: (_) => PlayerDetailScreen(store: widget.store, playerId: player.id),
        ),
      );
      return;
    }
    _showEvents(name, stats.attended.where((event) =>
        kind == _RankingKind.organizer
            ? playerSearchKey(event.organizer) == key
            : event.participants.any((name) => playerSearchKey(name) == key)));
  }

  Widget _ranking(
    _RankingKind kind,
    List<MapEntry<String, int>> counts,
    GiriAnalytics stats,
  ) => StairFormSection(
    title: _rankingTitle(kind),
    icon: _rankingIcon(kind),
    accent: _rankingAccent(kind),
    trailing: Text('${counts.length}件', style: Theme.of(context).textTheme.bodySmall),
    children: [
      if (counts.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('記録がありません'),
        ),
      for (var index = 0; index < counts.length && index < 10; index++)
        _RankingRow(
          store: widget.store,
          kind: kind,
          entry: counts[index],
          rank: index + 1,
          onTap: () => _openEntry(kind, counts[index].key, stats),
        ),
      if (counts.length > 10)
        CupertinoButton(
          onPressed: () => Navigator.of(context).push<void>(
            CupertinoPageRoute(
              builder: (_) => _FullRankingScreen(
                store: widget.store,
                kind: kind,
                counts: counts,
                onSelected: (name) => _openEntry(kind, name, stats),
              ),
            ),
          ),
          child: const Text('すべて表示'),
        ),
    ],
  );

  Widget _valueRow(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: StairFieldRow(
      label: label,
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          '$value回',
          style: StairTypography.role(StairTextRole.dateValue),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(title: const Text('集計')),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final years = GiriAnalytics.yearsOf(widget.store.events);
        final selectedYear = years.contains(_year) ? _year : null;
        final stats = GiriAnalytics(
          widget.store.events,
          year: selectedYear,
          month: _month,
          kind: _kind,
          meetingType: _meetingType,
          selfName: widget.store.preferences.selfName,
          siteNames: {for (final site in widget.store.onlineSites) site.id: site.name},
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            StairFormSection(
              title: '表示条件',
              icon: CupertinoIcons.slider_horizontal_3,
              accent: StairColors.result,
              children: [
                StairMenuRow<int>(
                  key: const ValueKey('aggregate-year'),
                  label: '年',
                  value: selectedYear ?? 0,
                  items: {0: 'すべての期間', for (final year in years) year: '$year年'},
                  onChanged: (value) => setState(() => _year = value == 0 ? null : value),
                ),
                StairMenuRow<int>(
                  key: const ValueKey('aggregate-month'),
                  label: '月',
                  value: _month ?? 0,
                  items: {0: 'すべての月', for (var month = 1; month <= 12; month++) month: '$month月'},
                  onChanged: (value) => setState(() => _month = value == 0 ? null : value),
                ),
                StairMenuRow<int>(
                  key: const ValueKey('aggregate-kind'),
                  label: '形式',
                  value: _kind?.index ?? -1,
                  items: const {-1: 'すべて', 0: '生大喜利', 1: 'ネット大喜利'},
                  onChanged: (value) => setState(() => _kind = value < 0 ? null : EventKind.values[value]),
                ),
                StairMenuRow<int>(
                  key: const ValueKey('aggregate-meeting-type'),
                  label: '会の種類',
                  value: _meetingType?.index ?? -1,
                  items: const {-1: 'すべて', 0: '大会', 1: '通常'},
                  onChanged: (value) => setState(() => _meetingType = value < 0 ? null : MeetingType.values[value]),
                ),
              ],
            ),
            StairFormSection(
              title: '参加の記録',
              icon: CupertinoIcons.chart_bar,
              accent: StairColors.result,
              trailing: Text('合計${stats.attended.length}回'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(child: _ParticipationMetric(
                        label: '生大喜利',
                        value: stats.live.length,
                        accent: StairColors.live,
                        valueKey: const ValueKey('aggregate-live-count'),
                      )),
                      const SizedBox(width: 16),
                      Expanded(child: _ParticipationMetric(
                        label: 'ネット大喜利',
                        value: stats.online.length,
                        accent: StairColors.online,
                        valueKey: const ValueKey('aggregate-online-count'),
                      )),
                    ],
                  ),
                ),
                _valueRow('通常', stats.casual.length),
                _valueRow('大会', stats.tournaments.length),
                if (stats.undatedCount > 0) _valueRow('日付未設定', stats.undatedCount),
              ],
            ),
            StairFormSection(
              title: '大会の結果',
              icon: CupertinoIcons.rosette,
              accent: StairColors.result,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      for (final item in [
                        ('優勝', stats.firstPlaceCount),
                        ('準優勝', stats.runnerUpCount),
                        ('入賞', stats.placedCount),
                      ])
                        Expanded(child: _ParticipationMetric(
                          label: item.$1,
                          value: item.$2,
                          accent: StairColors.result,
                        )),
                    ],
                  ),
                ),
              ],
            ),
            _MonthlyChart(
              periods: stats.monthly,
              showYear: selectedYear == null,
            ),
            if (_kind != EventKind.online)
              _ranking(_RankingKind.venue, stats.venues, stats),
            if (_kind != EventKind.live)
              _ranking(_RankingKind.site, stats.sites, stats),
            _ranking(_RankingKind.participant, stats.coParticipants, stats),
            _ranking(_RankingKind.organizer, stats.organizers, stats),
          ],
        );
      },
    ),
  );
}

class _ParticipationMetric extends StatelessWidget {
  const _ParticipationMetric({
    required this.label,
    required this.value,
    required this.accent,
    this.valueKey,
  });
  final String label;
  final int value;
  final Color accent;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, maxLines: 1, style: StairTypography.role(
        StairTextRole.formLabel,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      )),
      const SizedBox(height: 6),
      Text(
        '$value回',
        key: valueKey,
        style: StairTypography.style(TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: accent,
        )),
      ),
    ],
  );
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.periods, required this.showYear});
  final List<MonthlyParticipation> periods;
  final bool showYear;

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: const SizedBox(width: 7, height: 7),
      ),
      const SizedBox(width: 5),
      Text(label, style: StairTypography.role(StairTextRole.caption)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final visible = periods.length > 12 ? periods.skip(periods.length - 12).toList() : periods;
    final maximum = visible.fold<int>(1, (value, period) => period.total > value ? period.total : value);
    return StairFormSection(
      title: '月別の参加回数',
      icon: CupertinoIcons.chart_bar,
      accent: StairColors.result,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            children: [
              _legend('生大喜利', StairColors.live),
              _legend('ネット大喜利', StairColors.online),
            ],
          ),
        ),
        if (visible.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('日付のある参加記録がありません')),
        for (final period in visible)
          Semantics(
            label: '${period.month.year}年${period.month.month}月 生大喜利${period.live}回、ネット大喜利${period.online}回',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: showYear ? 64 : 40,
                    child: Text(
                      showYear ? '${period.month.year}/${period.month.month}' : '${period.month.month}月',
                      style: StairTypography.role(StairTextRole.caption),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: period.total / maximum,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: SizedBox(
                            height: 10,
                            child: Row(
                              children: [
                                if (period.live > 0)
                                  Expanded(flex: period.live, child: const ColoredBox(color: StairColors.live)),
                                if (period.online > 0)
                                  Expanded(flex: period.online, child: const ColoredBox(color: StairColors.online)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text('${period.total}回', maxLines: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.store,
    required this.kind,
    required this.entry,
    required this.rank,
    required this.onTap,
  });
  final GiriStore store;
  final _RankingKind kind;
  final MapEntry<String, int> entry;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    onPressed: onTap,
    child: Row(
      children: [
        SizedBox(width: 28, child: Text('$rank', style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(width: 6),
        if (kind == _RankingKind.participant || kind == _RankingKind.organizer)
          PlayerAvatar(store: store, name: entry.key),
        Expanded(
          child: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge),
        ),
        const SizedBox(width: 12),
        Text('${entry.value}回', style: StairTypography.role(StairTextRole.dateValue)),
        const SizedBox(width: 8),
        const Icon(CupertinoIcons.chevron_right, size: 14),
      ],
    ),
  );
}

class _FullRankingScreen extends StatelessWidget {
  const _FullRankingScreen({
    required this.store,
    required this.kind,
    required this.counts,
    required this.onSelected,
  });
  final GiriStore store;
  final _RankingKind kind;
  final List<MapEntry<String, int>> counts;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(title: Text(_rankingTitle(kind))),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        StairFormSection(
          title: _rankingTitle(kind),
          icon: _rankingIcon(kind),
          accent: _rankingAccent(kind),
          children: [
            for (var index = 0; index < counts.length; index++)
              _RankingRow(
                store: store,
                kind: kind,
                entry: counts[index],
                rank: index + 1,
                onTap: () => onSelected(counts[index].key),
              ),
          ],
        ),
      ],
    ),
  );
}

class _AggregateEventListScreen extends StatelessWidget {
  const _AggregateEventListScreen({
    required this.store,
    required this.title,
    required this.eventIds,
  });
  final GiriStore store;
  final String title;
  final Set<String> eventIds;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(title: Text(title)),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final events = store.events.where((event) => eventIds.contains(event.id)).toList()
          ..sort((a, b) => (GiriAnalytics.dateOf(b) ?? b.createdAt).compareTo(
            GiriAnalytics.dateOf(a) ?? a.createdAt,
          ));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (events.isEmpty)
              const StairCard(child: Text('参加記録がありません')),
            for (final event in events)
              EventListCard(
                store: store,
                event: event,
                onTap: () => Navigator.of(context).push<void>(
                  CupertinoPageRoute(
                    builder: (_) => EventDetailScreen(store: store, eventId: event.id),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
