import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'stair_theme.dart';

/// Inset translucent tabs, matching LiveStair's floating iPhone navigation.
class StairTabBar extends StatelessWidget {
  const StairTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _tabs = [
    (CupertinoIcons.add_circled_solid, '登録'),
    (CupertinoIcons.clock_fill, '一覧'),
    (Icons.emoji_events, '戦績'),
    (CupertinoIcons.text_badge_checkmark, '思考'),
    (CupertinoIcons.gear_solid, '設定'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.84),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                  width: 0.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    for (var index = 0; index < _tabs.length; index++)
                      Expanded(
                        child: Semantics(
                          label: _tabs[index].$2,
                          button: true,
                          selected: index == currentIndex,
                          onTap: () {
                            if (index != currentIndex) {
                              HapticFeedback.selectionClick();
                            }
                            onTap(index);
                          },
                          child: ExcludeSemantics(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(36),
                                onTap: () {
                                  if (index != currentIndex) {
                                    HapticFeedback.selectionClick();
                                  }
                                  onTap(index);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  constraints: const BoxConstraints(
                                    minHeight: 52,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(36),
                                    color: index == currentIndex
                                        ? theme.colorScheme.onSurface
                                              .withValues(
                                                alpha: dark ? 0.12 : 0.065,
                                              )
                                        : Colors.transparent,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _tabs[index].$1,
                                        size: 26,
                                        color: index == currentIndex
                                            ? StairColors.action
                                            : theme.colorScheme.onSurface,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _tabs[index].$2,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: index == currentIndex
                                              ? StairColors.action
                                              : theme.colorScheme.onSurface,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
