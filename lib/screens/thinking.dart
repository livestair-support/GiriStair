import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui/stair_theme.dart';

/// The writing desk: current online submissions and an enduring note library.
class ThinkingScreen extends StatefulWidget {
  const ThinkingScreen({super.key, required this.store});

  final GiriStore store;

  @override
  State<ThinkingScreen> createState() => _ThinkingScreenState();
}

class _ThinkingScreenState extends State<ThinkingScreen>
    with WidgetsBindingObserver {
  Timer? _clock;
  NoteKind? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  void _create(NoteKind kind, {String? eventId}) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ThoughtEditor(
          store: widget.store,
          initialKind: kind,
          initialEventId: eventId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StairPageHeader(
        title: '思考',
        icon: Icons.lightbulb_outline,
        accent: StairColors.memo,
        trailing: OutlinedButton.icon(
          onPressed: () => _create(NoteKind.free),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('メモ'),
        ),
      ),
      body: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final now = DateTime.now();
          final activeEvents =
              widget.store.events
                  .where((event) => event.isSubmissionOpen(now))
                  .toList()
                ..sort((a, b) => a.submissionEnd!.compareTo(b.submissionEnd!));
          final notes =
              widget.store.notes
                  .where((note) => _filter == null || note.kind == _filter)
                  .toList()
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
            children: [
              StairCard(
                accent: StairColors.memo,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '回答やお題の下書きを残せます。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _create(NoteKind.answers),
                          icon: const Icon(Icons.edit_note_outlined, size: 18),
                          label: const Text('回答メモ'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _create(NoteKind.prompts),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: StairColors.memo,
                            side: BorderSide(
                              color: StairColors.memo.withValues(alpha: 0.4),
                            ),
                          ),
                          icon: const Icon(Icons.lightbulb_outline, size: 18),
                          label: const Text('お題を作る'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              StairSectionTitle(
                title: '投稿期間中',
                icon: Icons.language_outlined,
                accent: StairColors.online,
                trailing: Text(
                  '${activeEvents.length}件',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              if (activeEvents.isEmpty)
                const _EmptyCard(
                  icon: Icons.event_note_outlined,
                  accent: StairColors.online,
                  message: '投稿期間中のネット大喜利はありません',
                  detail: '登録で投稿の開始・締切を設定すると、ここに表示されます。',
                ),
              for (final event in activeEvents)
                StairCard(
                  accent: StairColors.online,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: const StairIconBadge(
                      icon: Icons.language_outlined,
                      accent: StairColors.online,
                    ),
                    title: Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '締切 ${_dateTime(event.submissionEnd!)}\n'
                      'メモ ${widget.store.notes.where((note) => note.eventId == event.id).length}件',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => _EventThoughtsScreen(
                            store: widget.store,
                            eventId: event.id,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              StairSectionTitle(
                title: 'メモ',
                icon: Icons.edit_note_outlined,
                accent: StairColors.memo,
                trailing: Text(
                  '${widget.store.notes.length}件',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('すべて'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final kind in NoteKind.values)
                    ChoiceChip(
                      label: Text(_kindLabel(kind)),
                      selected: _filter == kind,
                      onSelected: (_) => setState(() => _filter = kind),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (notes.isEmpty)
                _EmptyCard(
                  icon: Icons.edit_note_outlined,
                  message: _filter == null
                      ? 'まだメモがありません'
                      : '${_kindLabel(_filter!)}はまだありません',
                  detail: '思いついた回答やお題を、1行ずつ書き留めてみましょう。',
                ),
              for (final note in notes)
                _NoteCard(
                  key: ValueKey(note.id),
                  store: widget.store,
                  note: note,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _EventThoughtsScreen extends StatelessWidget {
  const _EventThoughtsScreen({required this.store, required this.eventId});

  final GiriStore store;
  final String eventId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final event = _eventById(store, eventId);
        final notes =
            store.notes.where((note) => note.eventId == eventId).toList()
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return Scaffold(
          appBar: AppBar(
            title: Text(
              event?.title ?? '会のメモ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          floatingActionButton: event == null
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: const Text('回答メモ'),
                  onPressed: () {
                    Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => _ThoughtEditor(
                          store: store,
                          initialKind: NoteKind.answers,
                          initialEventId: eventId,
                        ),
                      ),
                    );
                  },
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 104),
            children: [
              if (event == null)
                const _EmptyCard(
                  icon: Icons.event_busy_outlined,
                  message: 'この会は削除されています',
                  detail: '保存したメモは「思考」のメモ一覧から開けます。',
                )
              else ...[
                if (event.submissionStart != null &&
                    event.submissionEnd != null)
                  StairSection(
                    title: '投稿期間',
                    icon: Icons.date_range_outlined,
                    accent: StairColors.online,
                    child: Text(
                      '${_dateTime(event.submissionStart!)} 〜\n'
                      '${_dateTime(event.submissionEnd!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 12),
                StairSectionTitle(
                  title: '回答メモ',
                  icon: Icons.edit_note_outlined,
                  accent: StairColors.memo,
                  trailing: Text(
                    '${notes.length}件',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                if (notes.isEmpty)
                  const _EmptyCard(
                    icon: Icons.edit_note_outlined,
                    message: 'この会のメモはまだありません',
                    detail: '「回答メモ」から、回答の候補を書き始められます。',
                  ),
                for (final note in notes)
                  _NoteCard(key: ValueKey(note.id), store: store, note: note),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NoteCard extends StatefulWidget {
  const _NoteCard({super.key, required this.store, required this.note});

  final GiriStore store;
  final ThoughtNote note;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('メモを削除しますか？'),
        content: Text('「${widget.note.title}」を削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.store.deleteNote(widget.note.id);
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

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final event = _eventById(widget.store, note.eventId);
    final lines = note.body.split('\n').where((line) => line.trim().isNotEmpty);
    return StairCard(
      accent: StairColors.memo,
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
        leading: StairIconBadge(
          icon: _kindIcon(note.kind),
          accent: StairColors.memo,
        ),
        title: Text(note.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_kindLabel(note.kind)}${event == null ? '' : ' · ${event.title}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: StairColors.memo),
            ),
            if (lines.isNotEmpty)
              Text(
                lines.first.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(
              '${lines.length}行 · ${_dateTime(note.updatedAt)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        onTap: _deleting
            ? null
            : () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      _ThoughtEditor(store: widget.store, note: note),
                ),
              ),
        trailing: _deleting
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : PopupMenuButton<String>(
                tooltip: 'メモの操作',
                onSelected: (_) => _delete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('削除')),
                ],
              ),
      ),
    );
  }
}

class _ThoughtEditor extends StatefulWidget {
  const _ThoughtEditor({
    required this.store,
    this.note,
    this.initialKind = NoteKind.free,
    this.initialEventId,
  });

  final GiriStore store;
  final ThoughtNote? note;
  final NoteKind initialKind;
  final String? initialEventId;

  @override
  State<_ThoughtEditor> createState() => _ThoughtEditorState();
}

class _ThoughtEditorState extends State<_ThoughtEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late NoteKind _kind;
  String? _eventId;
  bool _saving = false;
  bool _allowExit = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note?.title ?? '');
    _body = TextEditingController(text: widget.note?.body ?? '');
    _kind = widget.note?.kind ?? widget.initialKind;
    _eventId = widget.note?.eventId ?? widget.initialEventId;
    _title.addListener(_changed);
    _body.addListener(_changed);
  }

  void _changed() => setState(() {});

  bool get _dirty =>
      _title.text != (widget.note?.title ?? '') ||
      _body.text != (widget.note?.body ?? '') ||
      _kind != (widget.note?.kind ?? widget.initialKind) ||
      _eventId != (widget.note?.eventId ?? widget.initialEventId);

  @override
  void dispose() {
    _title.removeListener(_changed);
    _body.removeListener(_changed);
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _tryLeave() async {
    if (_leaving || _saving) return;
    _leaving = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('変更を保存せずに戻りますか？'),
        content: const Text('書きかけの内容は保存されません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('編集を続ける'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存せずに戻る'),
          ),
        ],
      ),
    );
    _leaving = false;
    if (discard == true && mounted) {
      setState(() => _allowExit = true);
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _chooseEvent() async {
    final events = widget.store.events.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            children: [
              const StairSectionTitle(
                title: '関連する会',
                icon: Icons.link,
                accent: StairColors.memo,
              ),
              const SizedBox(height: 8),
              StairCard(
                accent: StairColors.memo,
                padding: EdgeInsets.zero,
                child: ListTile(
                  title: const Text('関連づけなし'),
                  leading: const StairIconBadge(
                    icon: Icons.link_off,
                    accent: StairColors.memo,
                  ),
                  onTap: () => Navigator.pop(context, ''),
                ),
              ),
              for (final event in events)
                StairCard(
                  accent: event.kind == EventKind.online
                      ? StairColors.online
                      : StairColors.live,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(event.title),
                    subtitle: Text(
                      event.kind == EventKind.online ? 'ネット大喜利' : '生大喜利',
                    ),
                    leading: StairIconBadge(
                      icon: event.kind == EventKind.online
                          ? Icons.language_outlined
                          : Icons.groups_outlined,
                      accent: event.kind == EventKind.online
                          ? StairColors.online
                          : StairColors.live,
                    ),
                    selected: event.id == _eventId,
                    onTap: () => Navigator.pop(context, event.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _eventId = selected.isEmpty ? null : selected);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final body = _body.text.trim();
    var title = _title.text.trim();
    if (title.isEmpty && body.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('タイトルか本文を入力してください。')));
      return;
    }
    if (title.isEmpty) {
      final firstLine = body.split('\n').first.trim();
      title = firstLine.characters.take(40).toString();
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final note = ThoughtNote(
      id: widget.note?.id ?? widget.store.newId(),
      title: title,
      body: body,
      kind: _kind,
      eventId: _eventById(widget.store, _eventId)?.id,
      createdAt: widget.note?.createdAt ?? now,
      updatedAt: now,
    );
    try {
      await widget.store.saveNote(note);
      if (mounted) {
        setState(() {
          _saving = false;
          _allowExit = true;
        });
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存できませんでした。内容を残したまま再試行できます。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = _eventById(widget.store, _eventId);
    return PopScope<bool>(
      canPop: _allowExit || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _tryLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.note == null ? 'メモを作る' : 'メモを編集',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: StairSaveButton(onPressed: _save, saving: _saving),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
            children: [
              StairSection(
                title: 'メモの種類',
                icon: Icons.category_outlined,
                accent: StairColors.memo,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final kind in NoteKind.values)
                      ChoiceChip(
                        label: Text(_kindLabel(kind)),
                        avatar: Icon(_kindIcon(kind), size: 18),
                        selected: _kind == kind,
                        onSelected: (_) => setState(() => _kind = kind),
                      ),
                  ],
                ),
              ),
              StairSection(
                title: '基本情報',
                icon: Icons.notes_outlined,
                accent: StairColors.memo,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StairFieldRow(
                      label: 'タイトル',
                      multiline: true,
                      child: Semantics(
                        label: 'タイトル',
                        child: TextField(
                          controller: _title,
                          maxLength: 120,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: '省略すると本文の1行目を使います',
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    StairFieldRow(
                      label: '関連する会',
                      multiline: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _chooseEvent,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Expanded(child: Text(event?.title ?? '関連づけなし')),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.expand_more,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              StairSection(
                title: _kind == NoteKind.prompts ? 'お題の候補' : 'メモ',
                icon: _kindIcon(_kind),
                accent: StairColors.memo,
                child: Semantics(
                  label: _kind == NoteKind.prompts ? 'お題の候補' : 'メモ',
                  child: TextField(
                    controller: _body,
                    minLines: 12,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: switch (_kind) {
                        NoteKind.answers => '回答の候補を1行ずつ。\n思いつくままに書いてみましょう。',
                        NoteKind.prompts => '主催会で使いたいお題や、そのアイデアを1行ずつ。',
                        NoteKind.free => '気づきや振り返り、あとで考えたいこと。',
                      },
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_saving ? '保存中…' : '保存する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.message,
    required this.detail,
    this.accent = StairColors.memo,
  });

  final IconData icon;
  final String message;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return StairCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StairSectionTitle(title: message, icon: icon, accent: accent),
          const SizedBox(height: 10),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

GiriEvent? _eventById(GiriStore store, String? id) {
  if (id == null) return null;
  for (final event in store.events) {
    if (event.id == id) return event;
  }
  return null;
}

String _kindLabel(NoteKind kind) => switch (kind) {
  NoteKind.answers => '回答',
  NoteKind.prompts => 'お題',
  NoteKind.free => '自由',
};

IconData _kindIcon(NoteKind kind) => switch (kind) {
  NoteKind.answers => Icons.edit_note_outlined,
  NoteKind.prompts => Icons.lightbulb_outline,
  NoteKind.free => Icons.notes_outlined,
};

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${local.month}/${local.day} '
      '${two(local.hour)}:${two(local.minute)}';
}
