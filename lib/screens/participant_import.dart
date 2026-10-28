import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../participant_import.dart';
import '../ui/stair_theme.dart';

/// Recognition stays on the device. The result is always reviewed before it
/// changes a meeting; OCR headings and nicknames cannot be classified reliably.
Future<String?> readParticipantImages() async {
  final images = await ImagePicker().pickMultiImage();
  if (images.isEmpty) return null;
  final recognizer = TextRecognizer(script: TextRecognitionScript.japanese);
  try {
    final pages = <String>[];
    for (final image in images) {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      pages.add(result.text);
    }
    return pages.join('\n');
  } finally {
    await recognizer.close();
  }
}

class ParticipantImportScreen extends StatefulWidget {
  const ParticipantImportScreen({
    super.key,
    this.existingNames = const [],
    this.readImages = readParticipantImages,
  });

  final List<String> existingNames;
  final Future<String?> Function() readImages;

  @override
  State<ParticipantImportScreen> createState() =>
      _ParticipantImportScreenState();
}

class _ParticipantImportScreenState extends State<ParticipantImportScreen> {
  final _source = TextEditingController();
  final _names = <TextEditingController>[];
  final _selected = <bool>[];
  bool _reading = false;
  String? _message;

  @override
  void dispose() {
    _source.dispose();
    for (final name in _names) {
      name.dispose();
    }
    super.dispose();
  }

  List<String> get _selectedNames {
    final seen = widget.existingNames.map(playerSearchKey).toSet();
    final result = <String>[];
    for (var i = 0; i < _names.length; i++) {
      final name = _names[i].text.trim();
      if (_selected[i] && name.isNotEmpty && seen.add(playerSearchKey(name))) {
        result.add(name);
      }
    }
    return result;
  }

  void _preview() {
    FocusManager.instance.primaryFocus?.unfocus();
    final entered = widget.existingNames.map(playerSearchKey).toSet();
    final parsed = parseParticipantNames(_source.text);
    for (final name in _names) {
      name.dispose();
    }
    setState(() {
      _names
        ..clear()
        ..addAll(parsed.map((name) => TextEditingController(text: name)));
      _selected
        ..clear()
        ..addAll(
          parsed.map((name) => !entered.contains(playerSearchKey(name))),
        );
      _message = parsed.isEmpty ? '名前を読み取れませんでした。1行に1人ずつ入力してください。' : null;
    });
  }

  Future<void> _readImages() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _reading = true;
      _message = null;
    });
    try {
      final text = await widget.readImages();
      if (!mounted || text == null) return;
      if (text.trim().isEmpty) {
        setState(() => _message = '文字を読み取れませんでした。別の画像か、コピーした文章をお試しください。');
        return;
      }
      _source.text = [
        _source.text.trim(),
        text.trim(),
      ].where((part) => part.isNotEmpty).join('\n');
      _preview();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = '画像を読み取れませんでした。写真へのアクセス設定を確認するか、文章を貼り付けてください。',
        );
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _selectedNames.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('参加者を一括追加'),
        actions: [
          TextButton(
            key: const ValueKey('participant-import-apply'),
            onPressed: _reading || count == 0
                ? null
                : () => Navigator.pop(context, _selectedNames),
            child: Text(count == 0 ? '追加' : '$count人を追加'),
          ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          StairFormSection(
            title: '文章・画像から読み込む',
            icon: Icons.document_scanner_outlined,
            accent: StairColors.online,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('ツイプラ・noteなどの参加者一覧を貼り付けるか、スクリーンショットを選びます。'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const ValueKey('participant-import-source'),
                  controller: _source,
                  enabled: !_reading,
                  onChanged: (_) {
                    for (final name in _names) {
                      name.dispose();
                    }
                    setState(() {
                      _names.clear();
                      _selected.clear();
                      _message = null;
                    });
                  },
                  minLines: 5,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: '1行に1人ずつ、または「、」で区切った名前',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('participant-import-images'),
                      onPressed: _reading ? null : _readImages,
                      icon: const Icon(Icons.photo_library_outlined, size: 20),
                      label: Text(_reading ? '読み取り中…' : '画像から読み取る'),
                    ),
                    TextButton(
                      key: const ValueKey('participant-import-preview'),
                      onPressed: _reading ? null : _preview,
                      child: const Text('名前を確認'),
                    ),
                  ],
                ),
              ),
              if (_reading) const LinearProgressIndicator(minHeight: 2),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_names.isNotEmpty)
            StairFormSection(
              title: '追加する名前を確認',
              icon: Icons.people_outline,
              accent: StairColors.online,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Text(
                    '$count人を追加します。不要な文章はチェックを外し、読み間違いは名前をタップして直せます。入力済みの名前と重複する名前は追加しません。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (var i = 0; i < _names.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 16),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _selected[i],
                          activeColor: StairColors.action,
                          onChanged: _reading
                              ? null
                              : (value) =>
                                    setState(() => _selected[i] = value!),
                        ),
                        Expanded(
                          child: TextField(
                            key: ValueKey('participant-import-name-$i'),
                            controller: _names[i],
                            enabled: !_reading,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(fontSize: 17),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
