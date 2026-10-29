import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../store.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';

/// Topics and their answer candidates remain available after a deadline passes.
class ThinkingScreen extends StatefulWidget {
  const ThinkingScreen({super.key, required this.store, this.readImage = pickThoughtImage});

  final GiriStore store;
  final Future<String?> Function() readImage;

  @override
  State<ThinkingScreen> createState() => _ThinkingScreenState();
}

class _ThinkingScreenState extends State<ThinkingScreen>
    with WidgetsBindingObserver {
  Timer? _clock;
  int _mode = 0;
  NoteKind? _answerFilter;
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

  void _create(NoteKind kind) => _openEditor(context, widget.store, kind: kind, readImage: widget.readImage);

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
                event.isParticipating &&
                event.status != EventStatus.canceled)
              for (final round in event.effectiveRounds)
                if (round.submissionEnabled && round.isSubmissionOpen(now))
                  (event, round),
        ]..sort((a, b) => a.$2.submissionEnd!.compareTo(b.$2.submissionEnd!));
        final notes = widget.store.notes.where((note) {
          if (_mode == 1) {
            return note.kind == NoteKind.prompts &&
                (_usedFilter < 0 || note.used == (_usedFilter == 1));
          }
          final inActiveRound = active.any((entry) => _inRound(note, entry.$1.id, entry.$2.id));
          return note.kind != NoteKind.prompts && !inActiveRound &&
              (_answerFilter == null || note.kind == _answerFilter);
        }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return ListView(
          key: const ValueKey('thinking-list'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            CupertinoSlidingSegmentedControl<int>(
              key: const ValueKey('thinking-mode'),
              groupValue: _mode,
              children: const {
                0: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Text('回答作成'),
                ),
                1: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: Text('お題作成'),
                ),
              },
              onValueChanged: (value) {
                if (value != null) setState(() => _mode = value);
              },
            ),
            const SizedBox(height: 14),
            StairFormSection(
              title: _mode == 0 ? '回答を考える' : 'お題作成',
              icon: _mode == 0 ? CupertinoIcons.pencil : CupertinoIcons.lightbulb,
              accent: StairColors.memo,
              children: [
                _NavigationRow(
                  icon: _mode == 0 ? CupertinoIcons.pencil : CupertinoIcons.lightbulb,
                  title: _mode == 0 ? '回答メモ' : 'お題を作る',
                  onTap: () => _create(_mode == 0 ? NoteKind.answers : NoteKind.prompts),
                ),
              ],
            ),
            if (_mode == 0) ...[
              const SizedBox(height: 8),
              StairSectionTitle(
                title: '投稿期間中',
                icon: CupertinoIcons.globe,
                accent: StairColors.online,
                trailing: Text('${active.length}件', style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 8),
              if (active.isEmpty)
                const _EmptyCard(
                  message: '投稿期間中のネット大喜利はありません',
                  accent: StairColors.online,
                ),
              for (final (event, round) in active)
                RoundThoughtWorkbench(
                  key: ValueKey('active-round-${event.id}-${round.id}'),
                  store: widget.store,
                  eventId: event.id,
                  roundId: round.id,
                  readImage: widget.readImage,
                ),
            ],
            const SizedBox(height: 14),
            StairFormSection(
              title: _mode == 0 ? '回答・メモ' : '保存したお題',
              icon: _mode == 0 ? CupertinoIcons.pencil : CupertinoIcons.lightbulb,
              accent: StairColors.memo,
              children: [
                if (_mode == 0)
                  StairMenuRow<int>(
                    key: const ValueKey('thinking-note-filter'),
                    label: '種類',
                    accent: StairColors.memo,
                    value: _answerFilter?.index ?? -1,
                    items: const {-1: 'すべて', 0: '回答', 2: '自由'},
                    onChanged: (value) => setState(() {
                      _answerFilter = value < 0 ? null : NoteKind.values[value];
                    }),
                  )
                else
                  StairMenuRow<int>(
                    key: const ValueKey('thinking-used-filter'),
                    label: '使用状況',
                    accent: StairColors.memo,
                    value: _usedFilter,
                    items: const {-1: 'すべて', 0: '未使用', 1: '使用済み'},
                    onChanged: (value) => setState(() => _usedFilter = value),
                  ),
              ],
            ),
            if (notes.isEmpty)
              _EmptyCard(message: _mode == 0 ? '回答・メモがありません' : 'お題がありません'),
            for (final note in notes)
              _NoteCard(key: ValueKey(note.id), store: widget.store, note: note, readImage: widget.readImage),
          ],
        );
      },
    ),
  );
}

/// A shared detail page for a schedule's posting/voting windows and drafts.
/// The same workbench is embedded in event details and the thinking tab.
class RoundThoughtScreen extends StatelessWidget {
  const RoundThoughtScreen({super.key, required this.store, required this.eventId, required this.roundId});
  final GiriStore store;
  final String eventId;
  final String roundId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: StairNavigationBar(title: const Text('投稿・投票')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [RoundThoughtWorkbench(store: store, eventId: eventId, roundId: roundId)],
    ),
  );
}

class RoundThoughtWorkbench extends StatefulWidget {
  const RoundThoughtWorkbench({super.key, required this.store, required this.eventId, required this.roundId, this.showHeader = true, this.readImage = pickThoughtImage});
  final GiriStore store;
  final String eventId;
  final String roundId;
  final bool showHeader;
  final Future<String?> Function() readImage;

  @override
  State<RoundThoughtWorkbench> createState() => _RoundThoughtWorkbenchState();
}

class _RoundThoughtWorkbenchState extends State<RoundThoughtWorkbench> {
  String? _editingId;
  bool _creating = false;
  int _draftGeneration = 0;
  String? _error;

  Future<void> _delete(ThoughtNote note) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => StairCupertinoAlertDialog(
        title: const Text('お題と回答を削除しますか？'),
        content: Text('「${_noteTitle(note)}」を削除します。'),
        actions: [
          StairCupertinoDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          StairCupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try { await widget.store.deleteNote(note.id); }
    catch (_) { if (mounted) setState(() => _error = '削除できませんでした。もう一度お試しください。'); }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final event = _eventById(widget.store, widget.eventId);
      final round = _roundById(event, widget.roundId);
      final site = widget.store.onlineSiteById(event?.onlineSiteId);
      final siteUrl = site?.url ?? event?.siteUrl ?? '';
      final siteHost = Uri.tryParse(siteUrl)?.host ?? '';
      final siteIdentity = siteHost.isEmpty ? siteUrl : siteHost;
      final notes = widget.store.notes.where((note) =>
        note.kind == NoteKind.answers && _inRound(note, widget.eventId, widget.roundId),
      ).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final contextLabel = [
        if (event != null && event.meetingType == MeetingType.tournament)
          round?.name ?? '削除された日程'
        else if (round != null) '投稿・投票',
        if (round != null && (event?.meetingType == MeetingType.tournament || round.promptNumber > 1))
          'お題${round.promptNumber}',
        if (event?.affiliation.isNotEmpty == true) event!.affiliation,
        if (round?.block.isNotEmpty == true) round!.block
        else if (event?.block.isNotEmpty == true) event!.block,
      ].join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader) StairFormSection(
            title: site?.name ?? event?.title ?? '削除された会',
            icon: CupertinoIcons.globe,
            accent: StairColors.online,
            trailing: round == null ? null : CupertinoButton(
              key: ValueKey('round-add-topic-${widget.eventId}-${widget.roundId}'),
              padding: const EdgeInsets.all(4),
              minimumSize: const Size(32, 32),
              onPressed: () => setState(() { _creating = true; _editingId = null; }),
              child: const Icon(CupertinoIcons.plus_circle, size: 23),
            ),
            children: [
              if (siteIdentity.isNotEmpty)
                Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 2), child: Text(siteIdentity, style: Theme.of(context).textTheme.bodySmall)),
              if (contextLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(contextLabel, style: Theme.of(context).textTheme.bodyMedium),
                ),
              if (round != null) ...[
                _RoundPeriodRow(label: '投稿', start: round.submissionStart, end: round.submissionEnd,
                  enabled: round.submissionEnabled, accent: StairColors.online),
                _RoundPeriodRow(label: '投票', start: round.votingStart, end: round.votingEnd,
                  enabled: round.votingRequired, accent: StairColors.memo),
              ] else
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('日程は削除されています。保存したお題と回答は残っています。'),
                ),
            ],
          ),
          for (final note in notes)
            if (_editingId == note.id)
              _InlineThoughtEditor(
                key: ValueKey('inline-topic-${note.id}'),
                store: widget.store, eventId: widget.eventId, roundId: widget.roundId, note: note, readImage: widget.readImage,
                onSaved: () => setState(() => _editingId = null),
                onCancel: () => setState(() => _editingId = null),
              )
            else
              StairCard(
                accent: StairColors.memo,
                padding: EdgeInsets.zero,
                child: CupertinoButton(
                  key: ValueKey('round-topic-${note.id}'),
                  padding: const EdgeInsets.all(16),
                  onPressed: () => setState(() { _editingId = note.id; _creating = false; }),
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyLarge!,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_noteTitle(note), style: Theme.of(context).textTheme.titleMedium),
                        if (note.imageDataBase64.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _ThoughtImage(data: note.imageDataBase64),
                        ],
                        const SizedBox(height: 10),
                        if (note.answers.isNotEmpty)
                          for (var index = 0; index < note.answers.length; index++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text('${index + 1}. ${note.answers[index]}'),
                            )
                        else if (note.body.isNotEmpty) Text(note.body)
                        else const Text('回答案を追加', style: TextStyle(color: StairColors.action)),
                        Align(
                          alignment: Alignment.centerRight,
                          child: CupertinoButton(
                            key: ValueKey('round-delete-topic-${note.id}'),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            onPressed: () => _delete(note),
                            child: const Text('削除'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (!widget.showHeader && round != null && !_creating && notes.isNotEmpty)
            CupertinoButton(
              key: ValueKey('round-add-topic-${widget.eventId}-${widget.roundId}'),
              onPressed: () => setState(() { _creating = true; _editingId = null; }),
              child: const Text('お題を追加'),
            ),
          if (round != null && (_creating || notes.isEmpty))
            _InlineThoughtEditor(
              key: ValueKey('inline-topic-new-${widget.eventId}-${widget.roundId}-$_draftGeneration'),
              store: widget.store, eventId: widget.eventId, roundId: widget.roundId, readImage: widget.readImage,
              onSaved: () => setState(() { _creating = false; _draftGeneration++; }),
              onCancel: notes.isEmpty ? null : () => setState(() => _creating = false),
            ),
        ],
      );
    },
  );
}

class _RoundPeriodRow extends StatelessWidget {
  const _RoundPeriodRow({required this.label, required this.start, required this.end, required this.enabled, required this.accent});
  final String label;
  final DateTime? start;
  final DateTime? end;
  final bool enabled;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 3, height: 38, decoration: BoxDecoration(color: accent.withValues(alpha: enabled ? 1 : .3), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        SizedBox(width: 42, child: Text(label, style: StairTypography.role(StairTextRole.formLabel))),
        const SizedBox(width: 8),
        Expanded(child: Text([
          if (!enabled) label == '投稿' ? '投稿対象外' : '投票なし',
          '${start == null ? '開始未定' : _dateTime(start!)} 〜',
          end == null ? '締切未定' : _dateTime(end!),
        ].join('\n'), style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}

/// The picker resizes before reading bytes. A cancelled selection never clears
/// an existing image. Files stay in the document so backups retain the prompt.
Future<String?> pickThoughtImage() async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery, maxWidth: 1280, maxHeight: 1280, imageQuality: 75,
  );
  if (image == null) return null;
  final bytes = await image.readAsBytes();
  if (bytes.length > 1024 * 1024) {
    throw const FormatException('画像が大きすぎます。1MB以下の画像を選んでください。');
  }
  if (bytes.isEmpty) throw const FormatException('画像を読み込めませんでした。');
  return base64Encode(bytes);
}

class _ThoughtImage extends StatelessWidget {
  const _ThoughtImage({required this.data, this.thumbnail = false});
  final String data;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(data);
      return GestureDetector(
        onTap: () => Navigator.of(context).push<void>(CupertinoPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: Colors.black,
            appBar: StairNavigationBar(
              title: const Text('画像のお題'),
              foregroundColor: Colors.white,
              backgroundColor: Colors.black,
            ),
            body: InteractiveViewer(
              minScale: .5, maxScale: 5,
              child: Center(child: Image.memory(
                bytes, fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text('画像を表示できませんでした', style: TextStyle(color: Colors.white)),
              )),
            ),
          ),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(thumbnail ? 8 : 12),
          child: Image.memory(
            bytes, fit: BoxFit.contain, height: thumbnail ? 52 : 180,
            cacheWidth: thumbnail ? 160 : 1024,
            errorBuilder: (_, _, _) => const Text('画像を表示できませんでした'),
          ),
        ),
      );
    } catch (_) {
      return const Text('画像を表示できませんでした');
    }
  }
}

class _InlineThoughtEditor extends StatefulWidget {
  const _InlineThoughtEditor({super.key, required this.store, required this.eventId, required this.roundId, this.note, required this.onSaved, this.onCancel, this.readImage = pickThoughtImage});
  final GiriStore store;
  final String eventId;
  final String roundId;
  final ThoughtNote? note;
  final VoidCallback onSaved;
  final VoidCallback? onCancel;
  final Future<String?> Function() readImage;
  @override
  State<_InlineThoughtEditor> createState() => _InlineThoughtEditorState();
}

class _InlineThoughtEditorState extends State<_InlineThoughtEditor> {
  late final TextEditingController _prompt;
  late final TextEditingController _answers;
  late String _image;
  bool _saving = false;
  bool _reading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(text: widget.note?.prompt.isNotEmpty == true ? widget.note!.prompt : widget.note?.title ?? '');
    _answers = TextEditingController(text: widget.note?.answers.isNotEmpty == true ? widget.note!.answers.join('\n') : widget.note?.body ?? '');
    _image = widget.note?.imageDataBase64 ?? '';
  }
  @override
  void dispose() { _prompt.dispose(); _answers.dispose(); super.dispose(); }

  Future<void> _readImage() async {
    setState(() { _reading = true; _error = null; });
    try {
      final image = await widget.readImage();
      if (mounted && image != null) setState(() => _image = image);
    } catch (error) {
      if (mounted) setState(() => _error = error is FormatException ? error.message : '画像を読み込めませんでした。写真へのアクセス設定を確認してください。');
    } finally { if (mounted) setState(() => _reading = false); }
  }

  Future<void> _save() async {
    if (_saving || _reading) return;
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty && _image.isEmpty) { setState(() => _error = 'お題か画像を入力してください。'); return; }
    final body = _answers.text.trim();
    final now = DateTime.now();
    final draft = widget.note ?? ThoughtNote(id: widget.store.newId(), title: '', kind: NoteKind.answers, createdAt: now, updatedAt: now, eventId: widget.eventId, roundId: widget.roundId);
    final note = draft.copyWith(
      title: prompt.isEmpty ? '画像のお題' : prompt.characters.take(120).toString(),
      prompt: prompt, body: body, imageDataBase64: _image,
      answers: body.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList(),
      updatedAt: now,
    );
    setState(() { _saving = true; _error = null; });
    try {
      await widget.store.saveNote(note);
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) setState(() => _error = '保存できませんでした。内容を残したまま再試行できます。');
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => StairFormSection(
    title: widget.note == null ? 'お題と回答案を追加' : 'お題と回答案',
    icon: CupertinoIcons.pencil,
    accent: StairColors.memo,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          key: ValueKey('round-prompt-${widget.eventId}-${widget.roundId}'),
          controller: _prompt, enabled: !_saving, minLines: 1, maxLines: null,
          decoration: const InputDecoration(hintText: 'お題を入力'),
        ),
      ),
      if (_image.isNotEmpty)
        Padding(padding: const EdgeInsets.all(16), child: _ThoughtImage(data: _image)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Expanded(child: CupertinoButton(
            onPressed: _saving || _reading ? null : _readImage,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(CupertinoIcons.photo, size: 20), const SizedBox(width: 8),
              Flexible(child: Text(_reading ? '読み込み中' : '画像のお題', maxLines: 1)),
            ]),
          )),
          if (_image.isNotEmpty) CupertinoButton(onPressed: _saving || _reading ? null : () => setState(() => _image = ''), child: const Text('解除')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          key: ValueKey('round-answers-${widget.eventId}-${widget.roundId}'),
          controller: _answers, enabled: !_saving, minLines: 4, maxLines: null,
          decoration: const InputDecoration(hintText: '回答案を1行ずつ入力'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          if (_error != null) Expanded(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))
          else const Spacer(),
          if (widget.onCancel != null) CupertinoButton(onPressed: _saving ? null : widget.onCancel, child: const Text('キャンセル')),
          StairSaveButton(onPressed: _saving || _reading ? null : _save, saving: _saving),
        ]),
      ),
    ],
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
  const _NoteCard({super.key, required this.store, required this.note, this.readImage = pickThoughtImage});

  final GiriStore store;
  final ThoughtNote note;
  final Future<String?> Function() readImage;

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
      _openEditor(context, widget.store, note: widget.note, readImage: widget.readImage);
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
      if (event != null) widget.store.onlineSiteById(event.onlineSiteId)?.name ?? event.title,
      if (round != null)
        [event?.meetingType == MeetingType.tournament ? round.name : '投稿・投票', if (event?.meetingType == MeetingType.tournament || round.promptNumber > 1) 'お題${round.promptNumber}', if (round.block.isNotEmpty) round.block].join(' · ')
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
        leading: note.imageDataBase64.isNotEmpty
            ? SizedBox(width: 52, height: 52, child: _ThoughtImage(data: note.imageDataBase64, thumbnail: true))
            : StairIconBadge(
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
            : () => _openEditor(context, widget.store, note: note, readImage: widget.readImage),
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
  Future<String?> Function() readImage = pickThoughtImage,
}) {
  Navigator.of(context).push<bool>(
    CupertinoPageRoute(
      builder: (_) => _ThoughtEditor(
        store: store,
        note: note,
        initialKind: kind,
        initialEventId: eventId,
        initialRoundId: roundId,
        readImage: readImage,
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
    this.readImage = pickThoughtImage,
  });

  final GiriStore store;
  final ThoughtNote? note;
  final NoteKind initialKind;
  final String? initialEventId;
  final String? initialRoundId;
  final Future<String?> Function() readImage;

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
  late String _image;
  bool _readingImage = false;
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
    _image = note?.imageDataBase64 ?? '';
  }

  void _changed() => setState(() => _error = null);

  bool get _dirty =>
      _title.text != _initialTitle ||
      _body.text != _initialBody ||
      _kind != (widget.note?.kind ?? widget.initialKind) ||
      _eventId != (widget.note?.eventId ?? widget.initialEventId) ||
      _roundId != (widget.note?.roundId ?? widget.initialRoundId) ||
      _used != (widget.note?.used ?? false) ||
      _image != (widget.note?.imageDataBase64 ?? '');

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
    if (_saving || _readingImage) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final body = _body.text.trim();
    final primary = _title.text.trim();
    if ((_kind != NoteKind.free && primary.isEmpty && _image.isEmpty) ||
        (primary.isEmpty && body.isEmpty && _image.isEmpty)) {
      setState(
        () => _error = _kind == NoteKind.free
            ? 'タイトルか本文を入力してください。'
            : 'お題を入力してください。',
      );
      return;
    }
    final title = (primary.isNotEmpty ? primary : _image.isNotEmpty ? '画像のお題' : body.split('\n').first)
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
    final original = widget.note ?? ThoughtNote(
      id: widget.store.newId(), title: title, kind: _kind, createdAt: now, updatedAt: now,
    );
    final note = original.copyWith(
      title: title, body: body, kind: _kind,
      prompt: _kind == NoteKind.free ? '' : primary,
      answers: _kind == NoteKind.answers
          ? body.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList()
          : const [],
      used: _kind == NoteKind.prompts && _used,
      eventId: event?.id, roundId: roundId,
      imageDataBase64: _image, updatedAt: now,
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

  Future<void> _readImage() async {
    setState(() { _readingImage = true; _error = null; });
    try {
      final image = await widget.readImage();
      if (mounted && image != null) setState(() => _image = image);
    } catch (error) {
      if (mounted) setState(() => _error = error is FormatException ? error.message : '画像を読み込めませんでした。写真へのアクセス設定を確認してください。');
    } finally { if (mounted) setState(() => _readingImage = false); }
  }

  @override
  Widget build(BuildContext context) {
    final event = _eventById(widget.store, _eventId);
    final rounds = event?.effectiveRounds ?? const <EventRound>[];
    final roundItems = <String, String>{
      '': '関連づけなし',
      for (final round in rounds) round.id: '${event?.meetingType == MeetingType.tournament ? round.name : '投稿・投票'} · お題${round.promptNumber}',
      if (_roundId != null && !rounds.any((round) => round.id == _roundId))
        _roundId!: '削除された日程',
    };
    return PopScope<bool>(
      canPop: _allowExit || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _tryLeave();
      },
      child: Scaffold(
        appBar: StairNavigationBar(
          leading: StairBackButton(enabled: !_saving, onPressed: _tryLeave),
          title: Text(
            _kind == NoteKind.prompts
                ? 'お題'
                : _kind == NoteKind.answers
                ? '回答メモ'
                : 'メモ',
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: StairSaveButton(onPressed: _readingImage ? null : _save, saving: _saving),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (event?.kind == EventKind.online && _roundById(event, _roundId) != null)
                StairFormSection(
                  title: widget.store.onlineSiteById(event?.onlineSiteId)?.name ?? event!.title,
                  icon: CupertinoIcons.globe,
                  accent: StairColors.online,
                  children: [
                    _RoundPeriodRow(label: '投稿', start: _roundById(event, _roundId)!.submissionStart, end: _roundById(event, _roundId)!.submissionEnd, enabled: _roundById(event, _roundId)!.submissionEnabled, accent: StairColors.online),
                    _RoundPeriodRow(label: '投票', start: _roundById(event, _roundId)!.votingStart, end: _roundById(event, _roundId)!.votingEnd, enabled: _roundById(event, _roundId)!.votingRequired, accent: StairColors.memo),
                  ],
                ),
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
                  minLines: 1,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: _kind == NoteKind.free ? 'タイトル（任意）' : 'お題を入力',
                  ),
                ),
              ),
              if (_kind != NoteKind.free || _image.isNotEmpty)
                StairFormSection(
                  title: '画像のお題',
                  icon: CupertinoIcons.photo,
                  accent: StairColors.memo,
                  children: [
                    if (_image.isNotEmpty)
                      Padding(padding: const EdgeInsets.all(16), child: _ThoughtImage(data: _image)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Expanded(child: CupertinoButton(
                          key: const ValueKey('thought-editor-image'),
                          onPressed: _saving || _readingImage ? null : _readImage,
                          child: Text(_readingImage ? '読み込み中' : '画像を選ぶ', maxLines: 1),
                        )),
                        if (_image.isNotEmpty)
                          CupertinoButton(
                            key: const ValueKey('thought-editor-remove-image'),
                            onPressed: _saving || _readingImage ? null : () => setState(() => _image = ''),
                            child: const Text('解除'),
                          ),
                      ]),
                    ),
                  ],
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
