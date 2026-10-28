import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'stair_theme.dart';

OverlayEntry? _messageEntry;

/// A short iPhone-style status message. Save flows use haptics and navigation;
/// this is for feedback that needs words, such as a copy result or a failure.
void showStairMessage(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  if (_messageEntry?.mounted == true) _messageEntry!.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _StairMessage(
      message: message,
      error: error,
      onDismiss: () {
        if (entry.mounted) entry.remove();
        if (identical(_messageEntry, entry)) _messageEntry = null;
      },
    ),
  );
  _messageEntry = entry;
  overlay.insert(entry);
}

class _StairMessage extends StatefulWidget {
  const _StairMessage({
    required this.message,
    required this.error,
    required this.onDismiss,
  });

  final String message;
  final bool error;
  final VoidCallback onDismiss;

  @override
  State<_StairMessage> createState() => _StairMessageState();
}

class _StairMessageState extends State<_StairMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _dismissTimer = Timer(Duration(seconds: widget.error ? 5 : 2), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _animation.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.paddingOf(context).bottom + 88,
      child: FadeTransition(
        opacity: _animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .12),
            end: Offset.zero,
          ).animate(_animation),
          child: Semantics(
            liveRegion: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  color: theme.colorScheme.surface.withValues(alpha: .96),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: theme.colorScheme.onSurface.withValues(alpha: .12),
                      width: .5,
                    ),
                  ),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    onPressed: _dismiss,
                    child: Row(
                      children: [
                        Icon(
                          widget.error
                              ? CupertinoIcons.exclamationmark_circle
                              : CupertinoIcons.check_mark_circled_solid,
                          color: widget.error
                              ? StairColors.action
                              : StairColors.memo,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
