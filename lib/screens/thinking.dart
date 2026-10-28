import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';

/// Topics and their answer candidates remain available after a deadline passes.
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
  int _usedFilter = -1;

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

  void _create(NoteKind kind) => _openEditor(context, widget.store, kind: kind);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairPageHeader(
      title: '思考',
      icon: CupertinoIcons.lightbulb,
      accent: StairColors.memo,
      trailing: CupertinoButton(
        onPressed: () => _create(NoteKind.free),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.add, size: 18),
            SizedBox(width: 6),
            Text('メモ'),
          ],
        ),
      ),
    ),
    body: AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final now = DateTime.now();
        final active = <(GiriEvent, EventRound)>[
          for (final event in widget.store.events)
            if (event.kind == EventKind.online &&
                event.status != EventStatus.canceled)
              for (final round in event.effectiveRounds)
                if (round.isSubmissionOpen(now)) (event, round),
        ]..sort((a, b) => a.$2.submissionEnd!.compareTo(b.$2.submissionEnd!));
        final notes = widget.store.notes.where((note) {
          if (_filter != null && note.kind != _filter) return false;
          if (_usedFilter >= 0) {
            return note.kind == NoteKind.prompts &&
                note.used == (_usedFilter == 1);
          }
          return true;
        }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
          children: [
            StairFormSection(
              title: '作成',
              icon: CupertinoIcons.pencil,
              accent: StairColors.memo,
              children: [
                _NavigationRow(
                  icon: CupertinoIcons.pencil,
                  title: '回答メモ',
                  onTap: () => _create(NoteKind.answers),
                ),
                _NavigationRow(
                  icon: CupertinoIcons.lightbulb,
                  title: 'お題を作る',
                  onTap: () => _create(NoteKind.prompts),
                ),
              ],
            ),
            const SizedBox(height: 18),
            StairSectionTitle(
              title: '投稿期間中',
              icon: CupertinoIcons.globe,
              accent: StairColors.online,
              trailing: Text(
                '${active.length}件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            if (active.isEmpty)
              const _EmptyCard(
                message: '投稿期間中のネット大喜利はありません',
                accent: StairColors.online,
              ),
            for (final (event, round) in active)
              StairCard(
                key: ValueKey('active-round-${event.id}-${round.id}'),
                accent: StairColors.online,
                padding: EdgeInsets.zero,
                child: ListTile(
                  title: Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${round.name} · 締切 ${_dateTime(round.submissionEnd!)}\n'
                    'お題 ${widget.store.notes.where((note) => _inRound(note, event.id, round.id) && note.kind == NoteKind.answers).length}件',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 18,
                  ),
                  onTap: () => Navigator.of(context).push<void>(
                    CupertinoPageRoute(
                      builder: (_) => _RoundThoughtsScreen(
                        store: widget.store,
                        eventId: event.id,
                        roundId: round.id,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            StairSectionTitle(
              title: 'お題・メモ',
              icon: CupertinoIcons.square_list,
              accent: StairColors.memo,
              trailing: Text(
                '${widget.store.notes.length}件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            StairFormSection(
              title: '表示条件',
              icon: CupertinoIcons.slider_horizontal_3,
              accent: StairColors.memo,
              children: [
                StairMenuRow<int>(
                  key: const ValueKey('thinking-note-filter'),
                  label: '種類',
                  accent: StairColors.memo,
                  value: _filter?.index ?? -1,
                  items: {
                    -1: 'すべて',
                    for (final kind in NoteKind.values)
                      kind.index: _kindLabel(kind),
                  },
                  onChanged: (value) => setState(() {
                    _filter = value < 0 ? null : NoteKind.values[value];
                    if (_filter != NoteKind.prompts) _usedFilter = -1;
                  }),
                ),
                StairMenuRow<int>(
                  key: const ValueKey('thinking-used-filter'),
                  label: 'お題の使用状況',
                  accent: StairColors.memo,
                  value: _usedFilter,
                  items: const {-1: 'すべて', 0: '未使用', 1: '使用済み'},
                  onChanged: (value) => setState(() {
                    _usedFilter = value;
                    if (value >= 0) _filter = NoteKind.prompts;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (notes.isEmpty) const _EmptyCard(message: 'お題・メモがありません'),
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

class _RoundThoughtsScreen extends StatelessWidget {
  const _RoundThoughtsScreen({
    required this.store,
    required this.eventId,
    required this.roundId,
  });

  final GiriStore store;
  final String eventId;
  final String roundId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final event = _eventById(store, eventId);
      final round = _roundById(event, roundId);
      final notes =
          store.notes.where((note) => _inRound(note, eventId, roundId)).toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return Scaffold(
        appBar: AppBar(
          title: Text(
            round?.name ?? 'お題',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (event != null && round != null)
              CupertinoButton(
                key: const ValueKey('round-add-topic'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onPressed: () => _openEditor(
                  context,
                  store,
                  kind: NoteKind.answers,
                  eventId: eventId,
                  roundId: roundId,
                ),
                child: const Icon(CupertinoIcons.add),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
          children: [
            if (event != null)
              StairSection(
                title: event.title,
                icon: CupertinoIcons.globe,
                accent: StairColors.online,
                child: Text(round == null ? '削除された日程' : _periodLabel(round)),
              ),
            const SizedBox(height: 12),
            if (notes.isEmpty) const _EmptyCard(message: 'お題がありません'),
            for (final note in notes)
              _NoteCard(key: ValueKey(note.id), store: store, note: note),
          ],
        ),
      );
    },
  );
}

class _NavigationRow extends StatelessWidget {
  const _NavigationRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: StairIconBadge(icon: icon, accent: StairColors.memo),
    title: Text(title),
    trailing: const Icon(CupertinoIcons.chevron_forward, size: 18),
    onTap: onTap,
  );
}

class _NoteCard extends StatefulWidget {
  const _NoteCard({super.key, required this.store, required this.note});

  final GiriStore store;
  final ThoughtNote note;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _busy = false;

  Future<void> _actions() async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          if (widget.note.kind == NoteKind.prompts)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'used'),
              child: Text(widget.note.used ? '未使用に戻す' : '使用済みにする'),
            ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('編集'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('削除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      _openEditor(context, widget.store, note: widget.note);
      return;
    }
    if (action == 'delete') {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => StairCupertinoAlertDialog(
          title: const Text('メモを削除しますか？'),
          content: Text('「${_noteTitle(widget.note)}」を削除します。'),
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
    }
    setState(() => _busy = true);
    try {
      if (action == 'delete') {
        await widget.store.deleteNote(widget.note.id);
      } else {
        await widget.store.saveNote(
          widget.note.copyWith(
            used: !widget.note.used,
            updatedAt: DateTime.now(),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (context) => StairCupertinoAlertDialog(
            title: const Text('変更を保存できませんでした'),
            actions: [
              StairCupertinoDialogAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final event = _eventById(widget.store, note.eventId);
    final round = _roundById(event, note.roundId ?? 'legacy');
    final answerCount = note.answers.isNotEmpty
        ? note.answers.length
        : note.body.split('\n').where((line) => line.trim().isNotEmpty).length;
    final secondary = <String>[
      if (note.kind == NoteKind.prompts)
        note.used ? '使用済み' : '未使用'
      else if (note.kind == NoteKind.answers)
        '回答 $answerCount案'
      else
        'メモ',
      if (event != null) event.title,
      if (round != null)
        round.name
      else if (note.roundId != null && event != null)
        '削除された日程'
      else if (event?.kind == EventKind.online)
        '日程未選択',
    ].join(' · ');
    return StairCard(
      accent: StairColors.memo,
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        leading: StairIconBadge(
          icon: note.kind == NoteKind.prompts
              ? (note.used
                    ? CupertinoIcons.check_mark_circled
                    : CupertinoIcons.lightbulb)
              : CupertinoIcons.pencil,
          accent: StairColors.memo,
        ),
        title: Text(
          _noteTitle(note),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(secondary, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        onTap: _busy
            ? null
            : () => _openEditor(context, widget.store, note: note),
        trailing: _busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CupertinoActivityIndicator(),
              )
            : CupertinoButton(
                key: ValueKey('note-actions-${note.id}'),
                padding: const EdgeInsets.all(12),
                onPressed: _actions,
                child: Icon(
                  CupertinoIcons.ellipsis,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

void _openEditor(
  BuildContext context,
  GiriStore store, {
  ThoughtNote? note,
  NoteKind kind = NoteKind.free,
  String? eventId,
  String? roundId,
}) {
  Navigator.of(context).push<bool>(
    CupertinoPageRoute(
      builder: (_) => _ThoughtEditor(
        store: store,
        note: note,
        initialKind: kind,
        initialEventId: eventId,
        initialRoundId: roundId,
      ),
    ),
  );
}

class _ThoughtEditor extends StatefulWidget {
  const _ThoughtEditor({
    required this.store,
    this.note,
    this.initialKind = NoteKind.free,
    this.initialEventId,
    this.initialRoundId,
  });

  final GiriStore store;
  final ThoughtNote? note;
  final NoteKind initialKind;
  final String? initialEventId;
  final String? initialRoundId;

  @override
  State<_ThoughtEditor> createState() => _ThoughtEditorState();
}

class _ThoughtEditorState extends State<_ThoughtEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late NoteKind _kind;
  String? _eventId;
  String? _roundId;
  late bool _used;
  bool _saving = false;
  bool _allowExit = false;
  bool _leaving = false;
  String? _error;
  late final String _initialTitle;
  late final String _initialBody;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _kind = note?.kind ?? widget.initialKind;
    _initialTitle = note == null
        ? ''
        : note.prompt.isNotEmpty
        ? note.prompt
        : note.title;
    _initialBody =
        note != null && note.kind == NoteKind.answers && note.answers.isNotEmpty
        ? note.answers.join('\n')
        : note?.body ?? '';
    _title = TextEditingController(text: _initialTitle)..addListener(_changed);
    _body = TextEditingController(text: _initialBody)..addListener(_changed);
    _eventId = note?.eventId ?? widget.initialEventId;
    _roundId = note?.roundId ?? widget.initialRoundId;
    _used = note?.used ?? false;
  }

  void _changed() => setState(() => _error = null);

  bool get _dirty =>
      _title.text != _initialTitle ||
      _body.text != _initialBody ||
      _kind != (widget.note?.kind ?? widget.initialKind) ||
      _eventId != (widget.note?.eventId ?? widget.initialEventId) ||
      _roundId != (widget.note?.roundId ?? widget.initialRoundId) ||
      _used != (widget.note?.used ?? false);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _tryLeave() async {
    if (_leaving || _saving) return;
    if (!_dirty) {
      Navigator.of(context).pop(false);
      return;
    }
    _leaving = true;
    final discard = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StairCupertinoAlertDialog(
        title: const Text('変更を保存せずに戻りますか？'),
        content: const Text('書きかけの内容は保存されません。'),
        actions: [
          StairCupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('編集を続ける'),
          ),
          StairCupertinoDialogAction(
            isDestructiveAction: true,
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

  Future<void> _save() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final body = _body.text.trim();
    final primary = _title.text.trim();
    if ((_kind != NoteKind.free && primary.isEmpty) ||
        (primary.isEmpty && body.isEmpty)) {
      setState(
        () => _error = _kind == NoteKind.free
            ? 'タイトルか本文を入力してください。'
            : 'お題を入力してください。',
      );
      return;
    }
    final title = (primary.isNotEmpty ? primary : body.split('\n').first)
        .characters
        .take(120)
        .toString();
    final event = _eventById(widget.store, _eventId);
    // Preserve an old deleted stage link so that editing a note cannot silently
    // reassign its contents to a different round.
    final roundId = event == null ? null : _roundId;
    setState(() {
      _saving = true;
      _error = null;
    });
    final now = DateTime.now();
    final note = ThoughtNote(
      id: widget.note?.id ?? widget.store.newId(),
      title: title,
      body: body,
      kind: _kind,
      prompt: _kind == NoteKind.free ? '' : primary,
      answers: _kind == NoteKind.answers
          ? body
                .split('\n')
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty)
                .toList()
          : const [],
      used: _kind == NoteKind.prompts && _used,
      eventId: event?.id,
      roundId: roundId,
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
        setState(() {
          _saving = false;
          _error = '保存できませんでした。内容を残したまま再試行できます。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = _eventById(widget.store, _eventId);
    final rounds = event?.effectiveRounds ?? const <EventRound>[];
    final roundItems = <String, String>{
      '': '関連づけなし',
      for (final round in rounds) round.id: round.name,
      if (_roundId != null && !rounds.any((round) => round.id == _roundId))
        _roundId!: '削除された日程',
    };
    return PopScope<bool>(
      canPop: _allowExit || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _tryLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _saving ? null : _tryLeave,
            child: const Icon(CupertinoIcons.back),
          ),
          title: Text(
            _kind == NoteKind.prompts
                ? 'お題'
                : _kind == NoteKind.answers
                ? 'お題と回答'
                : 'メモ',
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              StairFormSection(
                title: '基本情報',
                icon: CupertinoIcons.link,
                accent: StairColors.memo,
                children: [
                  StairMenuRow<NoteKind>(
                    key: const ValueKey('thought-editor-kind'),
                    label: '種類',
                    accent: StairColors.memo,
                    value: _kind,
                    items: {
                      for (final kind in NoteKind.values)
                        kind: _kindLabel(kind),
                    },
                    onChanged: (value) => setState(() => _kind = value),
                  ),
                  StairMenuRow<String>(
                    key: const ValueKey('thought-editor-event'),
                    label: '関連する会',
                    accent: StairColors.memo,
                    value: event?.id ?? '',
                    items: {
                      '': '関連づけなし',
                      for (final item in widget.store.events)
                        item.id: item.title,
                    },
                    onChanged: (value) => setState(() {
                      _eventId = value.isEmpty ? null : value;
                      _roundId = null;
                    }),
                  ),
                  if (event?.kind == EventKind.online)
                    StairMenuRow<String>(
                      key: const ValueKey('thought-editor-round'),
                      label: '日程',
                      accent: StairColors.online,
                      value: _roundId ?? '',
                      items: roundItems,
                      onChanged: (value) => setState(
                        () => _roundId = value.isEmpty ? null : value,
                      ),
                    ),
                  if (_kind == NoteKind.prompts)
                    StairFormRow(
                      label: '使用済み',
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: CupertinoSwitch(
                          key: const ValueKey('thought-editor-used'),
                          value: _used,
                          onChanged: (value) => setState(() => _used = value),
                        ),
                      ),
                    ),
                ],
              ),
              StairSection(
                title: _kind == NoteKind.free ? 'タイトル' : 'お題',
                icon: _kind == NoteKind.free
                    ? CupertinoIcons.pencil
                    : CupertinoIcons.lightbulb,
                accent: StairColors.memo,
                child: TextField(
                  key: const ValueKey('thought-editor-prompt'),
                  controller: _title,
                  minLines: _kind == NoteKind.free ? 1 : 2,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: _kind == NoteKind.free ? 'タイトル（任意）' : 'お題を入力',
                  ),
                ),
              ),
              StairSection(
                title: _kind == NoteKind.answers ? '回答案' : 'メモ',
                icon: CupertinoIcons.pencil,
                accent: StairColors.memo,
                child: TextField(
                  key: const ValueKey('thought-editor-body'),
                  controller: _body,
                  minLines: _kind == NoteKind.answers ? 8 : 4,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: _kind == NoteKind.answers
                        ? '回答案を1行ずつ入力'
                        : 'メモ（任意）',
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message, this.accent = StairColors.memo});

  final String message;
  final Color accent;

  @override
  Widget build(BuildContext context) => StairCard(
    accent: accent,
    child: SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ),
  );
}

String _noteTitle(ThoughtNote note) =>
    note.prompt.isNotEmpty ? note.prompt : note.title;

bool _inRound(ThoughtNote note, String eventId, String roundId) =>
    note.eventId == eventId &&
    (note.roundId == roundId || (roundId == 'legacy' && note.roundId == null));

GiriEvent? _eventById(GiriStore store, String? id) => id == null
    ? null
    : store.events.where((event) => event.id == id).firstOrNull;

EventRound? _roundById(GiriEvent? event, String? id) => id == null
    ? null
    : event?.effectiveRounds.where((round) => round.id == id).firstOrNull;

String _periodLabel(EventRound round) => [
  if (round.submissionStart != null && round.submissionEnd != null)
    '投稿 ${_dateTime(round.submissionStart!)} 〜 ${_dateTime(round.submissionEnd!)}',
  if (round.votingStart != null && round.votingEnd != null)
    '投票 ${_dateTime(round.votingStart!)} 〜 ${_dateTime(round.votingEnd!)}',
].join('\n');

String _kindLabel(NoteKind kind) => switch (kind) {
  NoteKind.answers => '回答',
  NoteKind.prompts => 'お題',
  NoteKind.free => '自由',
};

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
