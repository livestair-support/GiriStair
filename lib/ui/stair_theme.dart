import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'stair_symbols.dart';
import 'stair_typography.dart';
export 'stair_typography.dart';
export 'stair_feedback.dart';

/// Shared visual language, taken from LiveStair's default/system theme.
abstract final class StairColors {
  static const action = Color(0xFFFF2D55);
  static const live = Color(0xFFF0456E);
  static const online = Color(0xFF6980A8);
  static const venue = Color(0xFF40999C);
  static const result = Color(0xFFC28C47);
  static const memo = Color(0xFF6B9473);
  static const settings = Color(0xFF946BB8);
}

/// EventBasicEditor.swift: Form top margin, section spacing and row insets.
abstract final class StairFormMetrics {
  static const minimumRowHeight = 48.0;
  static const sectionSpacing = 14.0;
  static const horizontalInset = 16.0;
  static const topInset = 8.0;
  static const rowVerticalInset = 8.0;
}

ThemeData stairTheme(Brightness brightness, {bool warm = false}) {
  final dark = brightness == Brightness.dark;
  final background = dark
      ? Colors.black
      : warm
      ? const Color(0xFFFFF8F0)
      : const Color(0xFFF9F9FB);
  final surface = dark ? const Color(0xFF1B1B1F) : Colors.white;
  final text = dark ? Colors.white : Colors.black;
  final secondaryText = dark
      ? CupertinoColors.secondaryLabel.darkColor
      : CupertinoColors.secondaryLabel.color;
  // Use the same system typefaces as SwiftUI on iPhone. Android keeps its
  // platform font rather than downloading or bundling a different typeface.
  final platform = defaultTargetPlatform;
  final font = StairTypography.bodyFamily(platform);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: StairColors.action,
        brightness: brightness,
      ).copyWith(
        primary: StairColors.action,
        onPrimary: Colors.white,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: secondaryText,
        surfaceTint: Colors.transparent,
        outline: dark ? const Color(0xFF5A5A62) : const Color(0xFFD9D9E0),
        outlineVariant: dark
            ? const Color(0xFF323238)
            : const Color(0xFFE6E6EC),
      );
  final base = ThemeData(
    useMaterial3: true,
    platform: platform,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    visualDensity: VisualDensity.standard,
    fontFamily: font,
    fontFamilyFallback: StairTypography.fallback(platform),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: StairColors.action,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
  return StairTypography.theme(
    base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: StairTypography.role(StairTextRole.pageTitle),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: StairTypography.role(StairTextRole.sectionTitle),
        bodyLarge: StairTypography.role(StairTextRole.input),
        bodyMedium: StairTypography.role(StairTextRole.input),
        bodySmall: StairTypography.role(
          StairTextRole.footnote,
        ).copyWith(color: secondaryText),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 44,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: DividerThemeData(
        color: (dark ? Colors.white : Colors.black).withValues(
          alpha: dark ? 0.14 : 0.12,
        ),
        thickness: 0.5,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        labelStyle: StairTypography.role(
          StairTextRole.input,
        ).copyWith(color: secondaryText),
        hintStyle: StairTypography.role(
          StairTextRole.input,
        ).copyWith(
          color: dark
              ? CupertinoColors.placeholderText.darkColor
              : CupertinoColors.placeholderText.color,
        ),
        errorMaxLines: 3,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: StairColors.action.withValues(alpha: dark ? 0.22 : 0.10),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(color: text, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          visualDensity: VisualDensity.compact,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? StairColors.action.withValues(alpha: dark ? 0.20 : 0.10)
                : surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? StairColors.action
                : text;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(44, 44),
          textStyle: StairTypography.role(StairTextRole.button),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: StairColors.action,
          side: BorderSide(color: scheme.outlineVariant),
          minimumSize: const Size(44, 44),
          shape: const StadiumBorder(),
          textStyle: StairTypography.role(StairTextRole.button),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: StairTypography.role(StairTextRole.button),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        iconColor: secondaryText,
        titleTextStyle: StairTypography.role(
          StairTextRole.value,
        ).copyWith(color: text),
        subtitleTextStyle: StairTypography.role(
          StairTextRole.footnote,
        ).copyWith(color: secondaryText),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: surface,
        foregroundColor: StairColors.action,
        shape: const StadiumBorder(),
        elevation: 2,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: StairColors.action,
        selectionColor: StairColors.action.withValues(alpha: 0.22),
        selectionHandleColor: StairColors.action,
      ),
    ),
  );
}

class StairIconBadge extends StatelessWidget {
  const StairIconBadge({
    super.key,
    required this.icon,
    required this.accent,
    this.size = 28,
    this.backgroundOpacity,
  });

  final IconData icon;
  final Color accent;
  final double size;
  final double? backgroundOpacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: ShapeDecoration(
      color: accent.withValues(
        alpha: backgroundOpacity ??
            (size == 38 && Theme.of(context).brightness == Brightness.dark
                ? 0.20
                : 0.14),
      ),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(size == 28 ? 8 : 11),
      ),
    ),
    child: StairSymbolIcon(
      icon: icon,
      size: size == 28 ? 14 : 19,
      weight: size == 28 ? FontWeight.w600 : FontWeight.w700,
      color: accent,
    ),
  );
}

class StairPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const StairPageHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    this.trailing,
    this.leading,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget? trailing;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(66);

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: Row(
            children: [
              leading ?? StairIconBadge(icon: icon, accent: accent, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  header: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    ),
  );
}

class StairCard extends StatelessWidget {
  const StairCard({
    super.key,
    required this.child,
    this.accent = StairColors.live,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(vertical: 7),
  });

  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = Color.alphaBlend(
      accent.withValues(alpha: dark ? 0.08 : 0.075),
      Theme.of(context).colorScheme.surface,
    );
    return Padding(
      padding: margin,
      child: Material(
        color: tint,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: accent.withValues(alpha: dark ? 0.20 : 0.28),
            width: 0.65,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(color: accent),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class StairSectionTitle extends StatelessWidget {
  const StairSectionTitle({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    this.trailing,
    this.iconBackgroundOpacity,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget? trailing;
  final double? iconBackgroundOpacity;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      StairIconBadge(
        icon: icon,
        accent: accent,
        backgroundOpacity: iconBackgroundOpacity,
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ),
      ?trailing,
    ],
  );
}

class StairSection extends StatelessWidget {
  const StairSection({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) => StairCard(
    accent: accent,
    padding: EdgeInsets.zero,
    margin: const EdgeInsets.only(bottom: StairFormMetrics.sectionSpacing),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: StairSectionTitle(title: title, icon: icon, accent: accent),
        ),
        Divider(height: 0.5, color: Theme.of(context).dividerTheme.color),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ],
    ),
  );
}

/// A grouped form with the same continuous separators as LiveStair.
class StairFormSection extends StatelessWidget {
  const StairFormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
    this.trailing,
    this.editorStyle = false,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;
  final Widget? trailing;
  final bool editorStyle;

  @override
  Widget build(BuildContext context) => StairCard(
    accent: accent,
    padding: EdgeInsets.zero,
    margin: const EdgeInsets.only(bottom: StairFormMetrics.sectionSpacing),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: StairSectionTitle(
            title: title,
            icon: icon,
            accent: accent,
            trailing: trailing,
            iconBackgroundOpacity: editorStyle ? 0.12 : 0.14,
          ),
        ),
        for (var index = 0; index < children.length; index++) ...[
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: index == 0 ? 0 : StairFormMetrics.horizontalInset,
            endIndent: index == 0 ? 0 : StairFormMetrics.horizontalInset,
            color: Theme.of(context).dividerTheme.color,
          ),
          children[index],
        ],
      ],
    ),
  );
}

/// Native-size labels and values; larger accessibility text gets its own line.
class StairFormRow extends StatelessWidget {
  const StairFormRow({
    super.key,
    required this.label,
    required this.child,
    this.info,
  });

  final String label;
  final Widget child;
  final Widget? info;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: StairFormMetrics.horizontalInset,
      vertical: StairFormMetrics.rowVerticalInset,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: StairTypography.role(StairTextRole.formLabel).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ?info,
          ],
        );
        final stacked =
            constraints.maxWidth < 270 ||
            MediaQuery.textScalerOf(context).scale(17) > 22;
        return ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight:
                StairFormMetrics.minimumRowHeight -
                StairFormMetrics.rowVerticalInset * 2,
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [labelWidget, const SizedBox(height: 4), child],
                )
              : Row(
                  children: [
                    labelWidget,
                    const SizedBox(width: 12),
                    Expanded(child: child),
                  ],
                ),
        );
      },
    ),
  );
}

class StairFieldRow extends StatelessWidget {
  const StairFieldRow({
    super.key,
    required this.label,
    required this.child,
    this.multiline = false,
  });

  final String label;
  final Widget child;
  final bool multiline;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          multiline ||
          constraints.maxWidth < 260 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      final labelWidget = Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
      if (stacked) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [labelWidget, const SizedBox(height: 4), child],
          ),
        );
      }
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            SizedBox(width: 84, child: labelWidget),
            const SizedBox(width: 8),
            Expanded(child: child),
          ],
        ),
      );
    },
  );
}

class StairSaveButton extends StatelessWidget {
  const StairSaveButton({
    super.key,
    required this.onPressed,
    this.label = '保存',
    this.saving = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool saving;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null || saving ? 0.55 : 1,
    child: OutlinedButton(
      onPressed: saving ? null : onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surface,
        disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        side: BorderSide(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10),
          width: 1,
        ),
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: StairTypography.role(StairTextRole.saveButton),
      ),
      child: saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CupertinoActivityIndicator(radius: 9),
            )
          : Text(
              label,
              style: StairTypography.role(StairTextRole.saveButton).copyWith(
                color: onPressed == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : StairColors.action,
              ),
            ),
    ),
  );
}
