import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../store.dart';
import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';

class SelfProfileScreen extends StatefulWidget {
  const SelfProfileScreen({
    super.key,
    required this.store,
    this.initialSetup = false,
    this.onCompleted,
  });

  final GiriStore store;
  final bool initialSetup;
  final VoidCallback? onCompleted;

  @override
  State<SelfProfileScreen> createState() => _SelfProfileScreenState();
}

class _SelfProfileScreenState extends State<SelfProfileScreen> {
  late final _name = TextEditingController(text: widget.store.preferences.selfName);
  bool _saving = false;

  bool get _canSave => !_saving && _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      await widget.store.savePreferences(
        widget.store.preferences.copyWith(
          selfName: _name.text.trim(),
          onboardingCompleted: true,
        ),
      );
      if (!mounted) return;
      widget.onCompleted?.call();
      if (!widget.initialSetup) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        showStairMessage(
          context,
          error is FormatException ? error.message : '名前を保存できませんでした。',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.initialSetup
        ? const StairPageHeader(
            title: 'あなたの名前',
            icon: CupertinoIcons.person,
            accent: StairColors.online,
          )
        : StairNavigationBar(
            title: const Text('自分の名前'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: StairSaveButton(
                  key: const ValueKey('self-name-save'),
                  onPressed: _canSave ? _save : null,
                  saving: _saving,
                ),
              ),
            ],
          ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        StairFormSection(
          title: 'プロフィール',
          icon: CupertinoIcons.person,
          accent: StairColors.online,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                key: const ValueKey('self-name'),
                controller: _name,
                autofocus: widget.initialSetup,
                enabled: !_saving,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(hintText: '大喜利で使う名前'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
              ),
            ),
          ],
        ),
        if (widget.initialSetup) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
            child: Text(
              '自分が主催する会と、参加する会の記録に使います。設定から変更できます。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          CupertinoButton.filled(
            key: const ValueKey('self-name-save'),
            onPressed: _canSave ? _save : null,
            child: _saving
                ? const CupertinoActivityIndicator()
                : const Text('はじめる'),
          ),
        ],
      ],
    ),
  );
}
