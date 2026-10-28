import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../ui/stair_controls.dart';
import '../ui/stair_theme.dart';

const stageNamePresets = [
  '予選1回戦',
  '予選2回戦',
  '予選3回戦',
  '本戦1回戦',
  '本戦2回戦',
  '準々決勝',
  '準決勝',
  '決勝',
  '敗者復活',
  '通常回',
];

class StageNameRow extends StatelessWidget {
  const StageNameRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'ラウンド',
    this.accent = StairColors.online,
  });

  final String value;
  final ValueChanged<String>? onChanged;
  final String label;
  final Color accent;

  Future<void> _change(BuildContext context, String name) async {
    if (name != '__custom__') {
      onChanged?.call(name);
      return;
    }
    final custom = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => _StageNameDialog(label: label, value: value),
    );
    if (context.mounted && custom != null) onChanged?.call(custom);
  }

  @override
  Widget build(BuildContext context) => StairMenuRow<String>(
    label: label,
    accent: accent,
    value: value,
    items: {
      for (final name in stageNamePresets) name: name,
      if (!stageNamePresets.contains(value)) value: value,
      '__custom__': '自由入力…',
    },
    onChanged: onChanged == null ? null : (name) => _change(context, name),
  );
}

class _StageNameDialog extends StatefulWidget {
  const _StageNameDialog({required this.label, required this.value});
  final String label;
  final String value;

  @override
  State<_StageNameDialog> createState() => _StageNameDialogState();
}

class _StageNameDialogState extends State<_StageNameDialog> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _accept() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => StairCupertinoAlertDialog(
    title: Text('${widget.label}名'),
    content: Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CupertinoTextField(
        controller: _controller,
        autofocus: true,
        placeholder: '名前を入力',
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _accept(),
      ),
    ),
    actions: [
      StairCupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      StairCupertinoDialogAction(
        onPressed: _accept,
        child: const Text('決定'),
      ),
    ],
  );
}
