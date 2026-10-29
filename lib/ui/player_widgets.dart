import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'stair_theme.dart';

const japanesePrefectures = <String>[
  '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県',
  '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県',
  '新潟県', '富山県', '石川県', '福井県', '山梨県', '長野県', '岐阜県',
  '静岡県', '愛知県', '三重県', '滋賀県', '京都府', '大阪府', '兵庫県',
  '奈良県', '和歌山県', '鳥取県', '島根県', '岡山県', '広島県', '山口県',
  '徳島県', '香川県', '愛媛県', '高知県', '福岡県', '佐賀県', '長崎県',
  '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県',
];

/// An unavailable backup image must not make its profile unusable.
Uint8List? playerIconBytes(String encoded) {
  if (encoded.isEmpty) return null;
  try {
    return base64Decode(encoded);
  } on FormatException {
    return null;
  }
}

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.store,
    required this.name,
    this.size = 28,
  });

  final GiriStore store;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (!store.showPlayerIcons) return const SizedBox.shrink();
      final bytes = playerIconBytes(store.playerByName(name)?.iconDataBase64 ?? '');
      Widget fallback() => Icon(
        CupertinoIcons.person_fill,
        size: size * .6,
        color: StairColors.online,
      );
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: ExcludeSemantics(
          child: ClipOval(
            child: ColoredBox(
              color: StairColors.online.withValues(alpha: .12),
              child: SizedBox(
                width: size,
                height: size,
                child: bytes == null
                    ? fallback()
                    : Image.memory(
                        bytes,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) => fallback(),
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Registered players and historical names share the completion list.
/// Hosting frequency is supplied by the store for organizer fields.
class PlayerSuggestionField extends StatefulWidget {
  const PlayerSuggestionField({
    super.key,
    required this.store,
    required this.controller,
    this.fieldKey,
    this.organizer = false,
    this.hint = '参加者名',
    this.enabled = true,
    this.onSelected,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.validator,
    this.compact = false,
  });

  final GiriStore store;
  final TextEditingController controller;
  final Key? fieldKey;
  final bool organizer;
  final String hint;
  final bool enabled;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final bool compact;

  @override
  State<PlayerSuggestionField> createState() => _PlayerSuggestionFieldState();
}

class _PlayerSuggestionFieldState extends State<PlayerSuggestionField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => RawAutocomplete<GiriPlayer>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (player) => player.name,
      optionsBuilder: (value) => widget.enabled
          ? widget.store.suggestPlayers(value.text, organizer: widget.organizer).take(8)
          : const Iterable<GiriPlayer>.empty(),
      onSelected: (player) {
        widget.onChanged?.call(player.name);
        widget.onSelected?.call(player.name);
        _focus.unfocus();
      },
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextFormField(
        key: widget.fieldKey,
        controller: controller,
        focusNode: focus,
        enabled: widget.enabled,
        validator: widget.validator,
        style: StairTypography.role(StairTextRole.input),
        maxLines: 1,
        textInputAction: widget.textInputAction,
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          border: InputBorder.none,
          constraints: BoxConstraints(minHeight: widget.compact ? 44 : 48),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: widget.onChanged,
        onFieldSubmitted: (value) {
          onSubmit();
          widget.onSubmitted?.call(controller.text);
        },
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth.isFinite ? constraints.maxWidth : 300,
              maxHeight: 240,
            ),
            child: StairCard(
              accent: StairColors.online,
              padding: EdgeInsets.zero,
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final player in options)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      onPressed: () => onSelected(player),
                      child: Row(
                        children: [
                          PlayerAvatar(store: widget.store, name: player.name),
                          Expanded(
                            child: Text(
                              player.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: StairTypography.role(
                                StairTextRole.value,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
