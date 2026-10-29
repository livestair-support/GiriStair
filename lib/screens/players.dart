import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../participant_import.dart';
import '../store.dart';
import '../ui/stair_theme.dart';
import '../ui/player_widgets.dart';
import 'event_list.dart';
import '../ui/stair_native_controls.dart';

class PlayerDirectoryScreen extends StatefulWidget {
  const PlayerDirectoryScreen({super.key, required this.store});

  final GiriStore store;

  @override
  State<PlayerDirectoryScreen> createState() => _PlayerDirectoryScreenState();
}

class _PlayerDirectoryScreenState extends State<PlayerDirectoryScreen> {
  String _query = '';

  void _edit([GiriPlayer? player]) {
    if (player == null) {
      Navigator.of(context).push<GiriPlayer>(
        CupertinoPageRoute(builder: (_) => _PlayerEditor(store: widget.store)),
      );
    } else {
      Navigator.of(context).push<void>(
        CupertinoPageRoute(
          builder: (_) => PlayerDetailScreen(store: widget.store, playerId: player.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(
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
                  playerSearchKey(player.furigana).contains(query) ||
                  playerSearchKey(player.region).contains(query),
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
                          PlayerAvatar(store:widget.store,name:player.name),
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
  late final _region = TextEditingController(text:widget.player?.region ?? '');
  late final _twitter = TextEditingController(text:widget.player?.twitterUrl ?? '');
  late final _memo = TextEditingController(text:widget.player?.memo ?? '');
  late String _icon = widget.player?.iconDataBase64 ?? '';
  bool _saving = false;
  bool _pickingIcon = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _furigana.dispose();
    _region.dispose(); _twitter.dispose(); _memo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _pickingIcon || _name.text.trim().isEmpty) return;
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
          region:_region.text, twitterUrl:_twitter.text, memo:_memo.text, iconDataBase64:_icon,
        ),
      );
      if (!mounted) return;
      StairNativeControls.saveFeedback();
      Navigator.of(context).pop(widget.store.playerByName(_name.text.trim()));
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

  Future<void> _pickIcon() async {
    if (_saving || _pickingIcon) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _pickingIcon = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('小さい画像を選んでください。');
      }
      if (mounted) setState(() => _icon = base64Encode(bytes));
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FormatException
            ? error.message
            : '画像を読み込めませんでした。');
      }
    } finally {
      if (mounted) setState(() => _pickingIcon = false);
    }
  }

  Widget _iconImage() {
    final bytes = playerIconBytes(_icon);
    if (bytes == null) return const Icon(CupertinoIcons.person_crop_circle, size: 72);
    return ClipOval(
      child: Image.memory(
        bytes,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) => const Icon(CupertinoIcons.person_crop_circle, size: 72),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(
      title: Text(widget.player == null ? 'プレイヤーを追加' : 'プレイヤーを編集'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ValueListenableBuilder(
            valueListenable: _name,
            builder: (context, value, _) => StairSaveButton(
              onPressed: _saving || _pickingIcon || value.text.trim().isEmpty ? null : _save,
              saving: _saving,
            ),
          ),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                textInputAction: TextInputAction.next,
              ),
            ),
            for (final entry in [(_region, '地域・都道府県'), (_twitter, 'X（Twitter）のユーザー名・URL')])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: entry.$1,
                  enabled: !_saving,
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(hintText: entry.$2),
                ),
              ),
          ],
        ),
        StairFormSection(
          title: 'アイコン',
          icon: CupertinoIcons.photo,
          accent: StairColors.settings,
          children: [
            CupertinoButton(
              key: const ValueKey('player-icon-select'),
              onPressed: _saving || _pickingIcon ? null : _pickIcon,
              child: SizedBox(
                width: double.infinity,
                height: 150,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_pickingIcon) const CupertinoActivityIndicator() else _iconImage(),
                    const SizedBox(height: 10),
                    Text(_icon.isEmpty ? '写真を選ぶ' : '写真を変更'),
                  ],
                ),
              ),
            ),
            if (_icon.isNotEmpty)
              CupertinoButton(
                onPressed: _saving || _pickingIcon ? null : () => setState(() => _icon = ''),
                child: const Text('アイコンを外す'),
              ),
          ],
        ),
        StairFormSection(
          title: 'メモ',
          icon: CupertinoIcons.pencil,
          accent: StairColors.memo,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _memo,
                enabled: !_saving,
                minLines: 3,
                maxLines: null,
                decoration: const InputDecoration(hintText: 'プレイヤーについてのメモ'),
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

class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({
    super.key,
    required this.store,
    required this.playerId,
  });

  final GiriStore store;
  final String playerId;

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  late String _playerId = widget.playerId;
  String? _lastName;

  Future<void> _edit(GiriPlayer player) async {
    final saved = await Navigator.of(context).push<GiriPlayer>(
      CupertinoPageRoute(
        builder: (_) => _PlayerEditor(store: widget.store, player: player),
      ),
    );
    if (saved != null && mounted) {
      setState(() {
        _playerId = saved.id;
        _lastName = saved.name;
      });
    }
  }

  Future<void> _openAccount(String text) async {
    var value = text.trim();
    if (RegExp(r'^@?[A-Za-z0-9_]{1,15}$').hasMatch(value)) {
      value = 'https://x.com/${value.replaceFirst('@', '')}';
    }
    final uri = Uri.tryParse(value);
    try {
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException('Invalid account URL.');
      }
    } catch (_) {
      if (mounted) showStairMessage(context, 'アカウントを開けませんでした。', error: true);
    }
  }

  void _openEvent(GiriEvent event) => Navigator.of(context).push<void>(
    CupertinoPageRoute(
      builder: (_) => EventDetailScreen(store: widget.store, eventId: event.id),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final player = store.playerDirectory
              .where((player) => player.id == _playerId)
              .firstOrNull ??
          (_lastName == null ? null : store.playerByName(_lastName!));
      if (player == null) {
        return Scaffold(
          appBar: StairNavigationBar(title: const Text('プレイヤー')),
          body: const Center(child: Text('登録情報がありません')),
        );
      }
      _lastName = player.name;
      final key = playerSearchKey(player.name);
      final joined = store.events.where(
        (event) => event.status == EventStatus.attended &&
            event.participants.any((name) => playerSearchKey(name) == key),
      ).toList();
      final hosted = store.events.where(
        (event) => playerSearchKey(event.organizer) == key,
      ).toList();
      final standings = [
        for (final event in store.events.where(
          (event) => event.meetingType == MeetingType.tournament &&
              event.status == EventStatus.attended,
        ))
          for (final standing in event.standings)
            if (standing.playerNames.any((name) => playerSearchKey(name) == key))
              (event, standing),
      ];
      return Scaffold(
        appBar: StairNavigationBar(
          title: const Text('プレイヤー'),
          actions: [
            CupertinoButton(
              onPressed: () => _edit(player),
              child: const Text('編集'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            StairCard(
              accent: StairColors.online,
              child: Row(
                children: [
                  PlayerAvatar(store: store, name: player.name, size: 56),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (player.furigana.isNotEmpty)
                          Text(player.furigana, style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          player.name,
                          key: const ValueKey('player-detail-name'),
                          style: StairTypography.role(StairTextRole.pageTitle),
                        ),
                        if (player.region.isNotEmpty) Text(player.region),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (player.twitterUrl.isNotEmpty)
              StairFormSection(
                title: 'X（Twitter）',
                icon: CupertinoIcons.link,
                accent: StairColors.online,
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.all(16),
                    onPressed: () => _openAccount(player.twitterUrl),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(player.twitterUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            if (player.memo.isNotEmpty)
              StairFormSection(
                title: 'メモ',
                icon: CupertinoIcons.pencil,
                accent: StairColors.memo,
                children: [
                  Padding(padding: const EdgeInsets.all(16), child: Text(player.memo)),
                ],
              ),
            StairFormSection(
              title: '参加と主催',
              icon: CupertinoIcons.chart_bar,
              accent: StairColors.result,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StairFieldRow(label: '同席した会', child: Text('${joined.length}回')),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StairFieldRow(label: '主催', child: Text('${hosted.length}回')),
                ),
              ],
            ),
            StairFormSection(
              title: '参加した大会の上位成績',
              icon: CupertinoIcons.rosette,
              accent: StairColors.result,
              children: [
                if (standings.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('上位成績の記録がありません'),
                  ),
                for (final item in standings)
                  CupertinoButton(
                    padding: const EdgeInsets.all(16),
                    onPressed: () => _openEvent(item.$1),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.$1.title, style: Theme.of(context).textTheme.bodyLarge)),
                        const SizedBox(width: 12),
                        Text(
                          item.$2.placement == 1 ? '優勝' :
                          item.$2.placement == 2 ? '準優勝' : '${item.$2.placement}位',
                        ),
                        const SizedBox(width: 8),
                        const Icon(CupertinoIcons.chevron_right, size: 15),
                      ],
                    ),
                  ),
              ],
            ),
            StairFormSection(
              title: '参加した会',
              icon: CupertinoIcons.calendar,
              accent: StairColors.online,
              children: [
                if (joined.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('参加した会の記録がありません'),
                  ),
                for (final event in joined)
                  CupertinoButton(
                    padding: const EdgeInsets.all(16),
                    onPressed: () => _openEvent(event),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(event.title, style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
