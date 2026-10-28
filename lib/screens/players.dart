import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../participant_import.dart';
import '../store.dart';
import '../ui/stair_theme.dart';
import '../ui/stair_native_controls.dart';

class PlayerDirectoryScreen extends StatefulWidget {
  const PlayerDirectoryScreen({super.key, required this.store});

  final GiriStore store;

  @override
  State<PlayerDirectoryScreen> createState() => _PlayerDirectoryScreenState();
}

class _PlayerDirectoryScreenState extends State<PlayerDirectoryScreen> {
  String _query = '';

  void _edit([GiriPlayer? player]) => Navigator.of(context).push<void>(
    CupertinoPageRoute(
      builder: (_) => _PlayerEditor(store: widget.store, player: player),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('大喜利プレイヤー一覧'),
      actions: [
        IconButton(
          tooltip: 'プレイヤーを追加',
          onPressed: _edit,
          icon: const Icon(CupertinoIcons.plus),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final query = playerSearchKey(_query);
        final players = widget.store.playerDirectory
            .where(
              (player) =>
                  playerSearchKey(player.name).contains(query) ||
                  playerSearchKey(player.furigana).contains(query),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            StairFormSection(
              title: '表示・検索',
              icon: CupertinoIcons.search,
              accent: StairColors.online,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: '名前・フリガナで検索',
                      prefixIcon: Icon(CupertinoIcons.search, size: 19),
                    ),
                  ),
                ),
              ],
            ),
            StairFormSection(
              title: 'プレイヤー（${players.length}人）',
              icon: CupertinoIcons.person_2,
              accent: StairColors.online,
              children: [
                if (players.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      query.isEmpty
                          ? '参加者を登録すると、ここに名前が並びます。右上の＋からも追加できます。'
                          : '一致するプレイヤーがいません。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                for (final player in players)
                  InkWell(
                    onTap: () => _edit(player),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(player.name),
                                if (player.furigana.isNotEmpty)
                                  Text(
                                    player.furigana,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            CupertinoIcons.chevron_right,
                            size: 15,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _PlayerEditor extends StatefulWidget {
  const _PlayerEditor({required this.store, this.player});

  final GiriStore store;
  final GiriPlayer? player;

  @override
  State<_PlayerEditor> createState() => _PlayerEditorState();
}

class _PlayerEditorState extends State<_PlayerEditor> {
  late final _name = TextEditingController(text: widget.player?.name ?? '');
  late final _furigana = TextEditingController(
    text: widget.player?.furigana ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _furigana.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.savePlayer(
        GiriPlayer(
          id: widget.player?.id ?? widget.store.newId(),
          name: _name.text,
          furigana: _furigana.text,
        ),
      );
      if (!mounted) return;
      StairNativeControls.saveFeedback();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is FormatException
            ? error.message
            : '保存できませんでした。もう一度お試しください。';
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StairCupertinoAlertDialog(
        title: const Text('プレイヤーの登録情報を削除しますか？'),
        content: const Text('過去の会に記録した名前は残ります。過去の参加者は一覧にも引き続き表示されます。'),
        actions: [
          StairCupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          StairCupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.store.deletePlayer(widget.player!.id);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '削除できませんでした。もう一度お試しください。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.player == null ? 'プレイヤーを追加' : 'プレイヤーを編集'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ValueListenableBuilder(
            valueListenable: _name,
            builder: (context, value, _) => StairSaveButton(
              onPressed: _saving || value.text.trim().isEmpty ? null : _save,
              saving: _saving,
            ),
          ),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        StairFormSection(
          title: '基本情報',
          icon: CupertinoIcons.person,
          accent: StairColors.online,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _name,
                enabled: !_saving,
                decoration: const InputDecoration(hintText: 'プレイヤー名 *'),
                textInputAction: TextInputAction.next,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _furigana,
                enabled: !_saving,
                decoration: const InputDecoration(hintText: 'フリガナ'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_saving && _name.text.trim().isNotEmpty) _save();
                },
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'フリガナ順に並び、名前とフリガナの両方で検索できます。名前の変更は過去の参加記録にも反映されます。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.player != null && !widget.player!.id.startsWith('history:'))
          TextButton(
            onPressed: _saving ? null : _delete,
            child: const Text(
              '登録情報を削除',
              style: TextStyle(color: StairColors.action),
            ),
          ),
      ],
    ),
  );
}
