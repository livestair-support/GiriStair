import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Typography roles transcribed from LiveStair's SwiftUI declarations.
/// Rounded is a design choice on the section title, not a global font setting.
enum StairTextRole {
  pageTitle,
  sectionTitle,
  formLabel,
  input,
  value,
  dateValue,
  button,
  saveButton,
  caption,
  footnote,
  tabLabel,
  dialogTitle,
  dialogBody,
  menuItem,
}

/// SF covers Latin characters. Native UIFont/CoreText metadata supplies the
/// matching Japanese family and rounded design when running on an iPhone.
abstract final class StairTypography {
  static const locale = Locale('ja', 'JP');
  static const _japaneseGothic = ['Hiragino Sans', 'Hiragino Kaku Gothic ProN'];
  static Map<String, Map<String, String>> _nativeFonts = const {};

  static bool _apple(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  /// The iOS adapter resolves these families from the device's actual UIFont
  /// descriptors. No private font name is guessed or bundled in Dart.
  /// Missing metadata keeps the documented Flutter Apple font cascade.
  static void configureNativeFonts(Map<String, dynamic> fonts) {
    _nativeFonts = {
      for (final entry in fonts.entries)
        if (entry.value is Map)
          entry.key: {
            for (final item in (entry.value as Map).entries)
              if (item.key is String && item.value is String)
                item.key as String: item.value as String,
          },
    };
  }

  static String? bodyFamily(TargetPlatform platform) =>
      _apple(platform) ? 'CupertinoSystemText' : null;

  static String? displayFamily(TargetPlatform platform) =>
      _apple(platform) ? 'CupertinoSystemDisplay' : null;

  static List<String>? fallback(TargetPlatform platform) =>
      _apple(platform) ? _japaneseGothic : null;

  static bool usesRoundedDesign(StairTextRole role) =>
      role == StairTextRole.sectionTitle;

  /// Sizes/weights are explicit in CommonUI.swift (1176/1195/2908) and
  /// EventBasicEditor.swift (364/2998/3062/3147/3204). Tracking for standard
  /// Apple text roles comes from Flutter's CupertinoTextThemeData. Height is
  /// deliberately natural: a fixed Material line-height changes baselines.
  static TextStyle role(
    StairTextRole role, {
    TargetPlatform? platform,
    Color? color,
  }) {
    const cupertino = CupertinoTextThemeData();
    final base = switch (role) {
      StairTextRole.pageTitle => TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: cupertino.navLargeTitleTextStyle.letterSpacing,
      ),
      StairTextRole.sectionTitle => const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      StairTextRole.formLabel => TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: cupertino.actionSmallTextStyle.letterSpacing,
      ),
      StairTextRole.saveButton => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: cupertino.navTitleTextStyle.letterSpacing,
      ),
      StairTextRole.caption => const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      StairTextRole.dateValue || StairTextRole.dialogTitle => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: cupertino.navTitleTextStyle.letterSpacing,
      ),
      StairTextRole.tabLabel => TextStyle(
        fontSize: cupertino.tabLabelTextStyle.fontSize,
        fontWeight: cupertino.tabLabelTextStyle.fontWeight,
        letterSpacing: cupertino.tabLabelTextStyle.letterSpacing,
      ),
      StairTextRole.dialogBody || StairTextRole.footnote => const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.08,
      ),
      _ => TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w400,
        letterSpacing: cupertino.textStyle.letterSpacing,
      ),
    };
    return style(
      base.copyWith(color: color),
      platform: platform,
      role: role,
    );
  }

  static StairTextRole _roleFor(TextStyle original) {
    final size = original.fontSize ?? 17;
    final weight = original.fontWeight ?? FontWeight.w400;
    if (size >= 29 && weight.value >= FontWeight.w700.value) {
      return StairTextRole.pageTitle;
    }
    if (size == 18 && weight.value >= FontWeight.w700.value) {
      return StairTextRole.sectionTitle;
    }
    if (size == 15 && weight == FontWeight.w500) {
      return StairTextRole.formLabel;
    }
    if (weight.value >= FontWeight.w700.value) {
      return StairTextRole.saveButton;
    }
    if (weight.value >= FontWeight.w600.value) {
      return StairTextRole.dateValue;
    }
    if (weight == FontWeight.w500 && size != 10) {
      return StairTextRole.formLabel;
    }
    if (size == 10) return StairTextRole.tabLabel;
    if (size == 13) return StairTextRole.footnote;
    if (size == 12) return StairTextRole.caption;
    return StairTextRole.value;
  }

  static TextStyle style(
    TextStyle original, {
    TargetPlatform? platform,
    bool display = false,
    StairTextRole? role,
  }) {
    final target = platform ?? defaultTargetPlatform;
    final selectedRole = role ?? _roleFor(original);
    final metadata = _apple(target) ? _nativeFonts[selectedRole.name] : null;
    final latinFamily = metadata?['latinFamilyName'];
    final japaneseFamily = metadata?['japaneseFamilyName'];
    final hasLatinFamily = latinFamily != null && latinFamily.isNotEmpty;
    String? family;
    if (usesRoundedDesign(selectedRole) && hasLatinFamily) {
      family = latinFamily;
    } else if (display || (original.fontSize ?? 0) >= 20) {
      family = displayFamily(target);
    } else {
      family = hasLatinFamily ? latinFamily : bodyFamily(target);
    }
    // Skia's CoreText manager matches kCTFontFamilyNameAttribute, not a
    // PostScript face name. Keep the role's requested weight for that family.
    // Retaining the Latin system family first also prevents a Japanese
    // fallback family from becoming the font for Latin text.
    return original.copyWith(
      fontFamily: family,
      fontFamilyFallback: japaneseFamily != null && japaneseFamily.isNotEmpty
          ? [japaneseFamily]
          : fallback(target),
      locale: locale,
    );
  }

  static TextTheme _textTheme(TextTheme theme, TargetPlatform platform) =>
      TextTheme(
        displayLarge: style(theme.displayLarge!, platform: platform),
        displayMedium: style(theme.displayMedium!, platform: platform),
        displaySmall: style(theme.displaySmall!, platform: platform),
        headlineLarge: style(theme.headlineLarge!, platform: platform),
        headlineMedium: style(theme.headlineMedium!, platform: platform),
        headlineSmall: style(theme.headlineSmall!, platform: platform),
        titleLarge: style(theme.titleLarge!, platform: platform),
        titleMedium: style(theme.titleMedium!, platform: platform),
        titleSmall: style(theme.titleSmall!, platform: platform),
        bodyLarge: style(theme.bodyLarge!, platform: platform),
        bodyMedium: style(theme.bodyMedium!, platform: platform),
        bodySmall: style(theme.bodySmall!, platform: platform),
        labelLarge: style(theme.labelLarge!, platform: platform),
        labelMedium: style(theme.labelMedium!, platform: platform),
        labelSmall: style(theme.labelSmall!, platform: platform),
      );

  static ButtonStyle _button(ButtonStyle? original, TargetPlatform platform) =>
      (original ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStateProperty.resolveWith(
          (states) => style(
            original?.textStyle?.resolve(states) ?? const TextStyle(),
            platform: platform,
          ),
        ),
      );

  /// Component themes can replace inherited TextStyles. Apply the same stack
  /// to those styles as well as the body, including Cupertino's inherit:false
  /// picker and navigation styles.
  static ThemeData theme(ThemeData original) {
    final platform = original.platform;
    final cupertino = MaterialBasedCupertinoThemeData(materialTheme: original);
    final text = cupertino.textTheme;
    final input = original.inputDecorationTheme;
    return original.copyWith(
      textTheme: _textTheme(original.textTheme, platform),
      primaryTextTheme: _textTheme(original.primaryTextTheme, platform),
      cupertinoOverrideTheme: cupertino.copyWith(
        textTheme: text.copyWith(
          textStyle: style(text.textStyle, platform: platform),
          actionTextStyle: style(text.actionTextStyle, platform: platform),
          actionSmallTextStyle: style(
            text.actionSmallTextStyle,
            platform: platform,
          ),
          tabLabelTextStyle: style(text.tabLabelTextStyle, platform: platform),
          navTitleTextStyle: style(text.navTitleTextStyle, platform: platform),
          navLargeTitleTextStyle: style(
            text.navLargeTitleTextStyle,
            platform: platform,
          ),
          navActionTextStyle: style(
            text.navActionTextStyle,
            platform: platform,
          ),
          pickerTextStyle: style(text.pickerTextStyle, platform: platform),
          dateTimePickerTextStyle: style(
            text.dateTimePickerTextStyle,
            platform: platform,
          ),
        ),
      ),
      appBarTheme: original.appBarTheme.copyWith(
        titleTextStyle: style(
          original.appBarTheme.titleTextStyle ?? original.textTheme.titleLarge!,
          platform: platform,
        ),
        toolbarTextStyle: style(
          original.appBarTheme.toolbarTextStyle ??
              original.textTheme.bodyMedium!,
          platform: platform,
        ),
      ),
      inputDecorationTheme: input.copyWith(
        labelStyle: style(
          input.labelStyle ?? const TextStyle(),
          platform: platform,
        ),
        floatingLabelStyle: style(
          input.floatingLabelStyle ?? const TextStyle(),
          platform: platform,
        ),
        hintStyle: style(
          input.hintStyle ?? const TextStyle(),
          platform: platform,
        ),
        helperStyle: style(
          input.helperStyle ?? const TextStyle(),
          platform: platform,
        ),
        errorStyle: style(
          input.errorStyle ?? const TextStyle(),
          platform: platform,
        ),
        prefixStyle: style(
          input.prefixStyle ?? const TextStyle(),
          platform: platform,
        ),
        suffixStyle: style(
          input.suffixStyle ?? const TextStyle(),
          platform: platform,
        ),
        counterStyle: style(
          input.counterStyle ?? const TextStyle(),
          platform: platform,
        ),
      ),
      listTileTheme: original.listTileTheme.copyWith(
        titleTextStyle: style(
          original.listTileTheme.titleTextStyle ??
              original.textTheme.bodyLarge!,
          platform: platform,
        ),
        subtitleTextStyle: style(
          original.listTileTheme.subtitleTextStyle ??
              original.textTheme.bodySmall!,
          platform: platform,
        ),
        leadingAndTrailingTextStyle: style(
          original.listTileTheme.leadingAndTrailingTextStyle ??
              original.textTheme.bodySmall!,
          platform: platform,
        ),
      ),
      chipTheme: original.chipTheme.copyWith(
        labelStyle: style(
          original.chipTheme.labelStyle ?? original.textTheme.labelLarge!,
          platform: platform,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _button(original.textButtonTheme.style, platform),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _button(original.filledButtonTheme.style, platform),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _button(original.outlinedButtonTheme.style, platform),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _button(original.elevatedButtonTheme.style, platform),
      ),
    );
  }
}

/// CupertinoAlertDialog supplies private inherit:false styles for its title,
/// content and actions. Merge after those styles, retaining their size, color
/// and accessibility behavior while restoring the Japanese font cascade.
class _JapaneseDialogText extends StatelessWidget {
  const _JapaneseDialogText({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: StairTypography.style(
      DefaultTextStyle.of(context).style,
      platform: Theme.of(context).platform,
    ),
    child: child,
  );
}

class StairCupertinoAlertDialog extends CupertinoAlertDialog {
  StairCupertinoAlertDialog({
    super.key,
    Widget? title,
    Widget? content,
    super.actions = const [],
    super.scrollController,
    super.actionScrollController,
  }) : super(
         title: title == null ? null : _JapaneseDialogText(child: title),
         content: content == null ? null : _JapaneseDialogText(child: content),
       );
}

class StairCupertinoDialogAction extends CupertinoDialogAction {
  StairCupertinoDialogAction({
    super.key,
    super.onPressed,
    super.isDefaultAction,
    super.isDestructiveAction,
    required Widget child,
  }) : super(child: _JapaneseDialogText(child: child));
}
