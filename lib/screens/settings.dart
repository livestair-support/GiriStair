import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui/stair_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.store, super.key});

  final GiriStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const StairPageHeader(
      title: '設定',
      icon: Icons.settings_outlined,
      accent: StairColors.settings,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        StairSection(
          title: '記録を振り返る',
          icon: Icons.insights_outlined,
          accent: StairColors.result,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('集計'),
            subtitle: const Text('参加回数・会場・一緒に参加した人'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => AggregateScreen(store: store)),
            ),
          ),
        ),
        StairSection(
          title: '保存について',
          icon: Icons.folder_outlined,
          accent: StairColors.memo,
          child: Text(
            '参加記録と思考メモは、この端末に保存されます。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const StairSection(
          title: 'GiriStair',
          icon: Icons.layers_outlined,
          accent: StairColors.settings,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('大喜利をする人の、予定と記録と思考。'),
              Divider(height: 24),
              StairFieldRow(
                label: 'バージョン',
                child: Text('0.1.0', textAlign: TextAlign.end),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AggregateScreen extends StatelessWidget {
  const AggregateScreen({required this.store, super.key});

  final GiriStore store;

  List<MapEntry<String, int>> _sortedCounts(Iterable<String> values) {
    final counts = <String, int>{};
    for (final value in values) {
      final key = value.trim();
      if (key.isNotEmpty) {
        counts.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return counts.entries.toList()..sort((a, b) {
      final order = b.value.compareTo(a.value);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
  }

  Widget _countRow(
    BuildContext context,
    String label,
    int count,
    IconData icon,
    Color accent,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(icon, color: accent, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        const SizedBox(width: 10),
        Text(
          '$count 回',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _ranking(
    BuildContext context,
    String title,
    String description,
    List<MapEntry<String, int>> entries,
    IconData icon,
    Color accent,
  ) => StairSection(
    title: title,
    icon: icon,
    accent: accent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(description, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '参加済みの記録に入力すると表示されます。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (var index = 0; index < entries.take(5).length; index++) ...[
          if (index != 0) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(child: Text(entries[index].key)),
                const SizedBox(width: 12),
                Text('${entries[index].value} 回'),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('集計')),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final attended = store.events
            .where((event) => event.status == EventStatus.attended)
            .toList();
        final live = attended
            .where((event) => event.kind == EventKind.live)
            .toList();
        final onlineCount = attended.length - live.length;
        final venues = _sortedCounts(live.map((event) => event.venue));
        final participants = _sortedCounts(
          live.expand(
            (event) => event.participants
                .map((name) => name.trim())
                .where((name) => name.isNotEmpty)
                .toSet(),
          ),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            StairSection(
              title: '参加の記録',
              icon: Icons.event_available_outlined,
              accent: StairColors.live,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '「参加済み」にした記録を集計しています。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _countRow(
                    context,
                    '参加回数',
                    attended.length,
                    Icons.event_available_outlined,
                    StairColors.live,
                  ),
                  const Divider(height: 1),
                  _countRow(
                    context,
                    '生大喜利',
                    live.length,
                    Icons.groups_outlined,
                    StairColors.live,
                  ),
                  const Divider(height: 1),
                  _countRow(
                    context,
                    'ネット大喜利',
                    onlineCount,
                    Icons.language,
                    StairColors.online,
                  ),
                ],
              ),
            ),
            _ranking(
              context,
              'よく行く会場',
              '生大喜利の参加回数・上位5件',
              venues,
              Icons.place_outlined,
              StairColors.venue,
            ),
            _ranking(
              context,
              '一緒に参加した人',
              '参加者として登録した人との同席回数・上位5件',
              participants,
              Icons.people_outline,
              StairColors.online,
            ),
          ],
        );
      },
    ),
  );
}
