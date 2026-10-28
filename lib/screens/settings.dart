import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.store, super.key});

  final GiriStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('設定')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            leading: const Icon(Icons.insights_outlined),
            title: const Text('集計'),
            subtitle: const Text('参加回数・会場・一緒に参加した人'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => AggregateScreen(store: store)),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('保存について', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                const Text('この端末に保存されます。'),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GiriStair',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('大喜利をする人の、予定と記録と思考。'),
                const SizedBox(height: 14),
                Text(
                  'バージョン 0.1.0',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
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

  Widget _countTile(
    BuildContext context,
    String label,
    int count,
    IconData icon,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(label)),
          Text('$count 回', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    ),
  );

  Widget _ranking(
    BuildContext context,
    String title,
    String description,
    List<MapEntry<String, int>> entries,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('参加済みの記録に入力すると表示されます。'),
            ),
          for (final entry in entries.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(entry.key)),
                  const SizedBox(width: 12),
                  Text('${entry.value} 回'),
                ],
              ),
            ),
        ],
      ),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text('積み重ねた大喜利', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('参加状態を「参加済み」にした記録を集計しています。'),
            const SizedBox(height: 16),
            _countTile(
              context,
              '参加回数',
              attended.length,
              Icons.event_available_outlined,
            ),
            _countTile(context, '生大喜利', live.length, Icons.groups_outlined),
            _countTile(context, 'ネット大喜利', onlineCount, Icons.language),
            const SizedBox(height: 16),
            _ranking(context, 'よく行く会場', '生大喜利の参加回数・上位5件', venues),
            _ranking(
              context,
              '一緒に参加した人',
              '参加者として登録した人との同席回数・上位5件',
              participants,
            ),
          ],
        );
      },
    ),
  );
}
