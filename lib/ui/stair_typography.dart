import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// SF covers Latin characters; CJK glyphs need an explicit Japanese font.
/// Use Flutter's documented Apple font proxies, never private '.SF ...' names.
abstract final class StairTypography {
  static const locale = Locale('ja', 'JP');
  static const _japaneseGothic = ['Hiragino Sans', 'Hiragino Kaku Gothic ProN'];

  static bool _apple(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  static String? bodyFamily(TargetPlatform platform) =>
      _apple(platform) ? 'CupertinoSystemText' : null;

  static String? displayFamily(TargetPlatform platform) =>
      _apple(platform) ? 'CupertinoSystemDisplay' : null;

  static List<String>? fallback(TargetPlatform platform) =>
      _apple(platform) ? _japaneseGothic : null;

  static TextStyle style(
    TextStyle original, {
    TargetPlatform? platform,
    bool display = false,
  }) {
    final target = platform ?? TargetPlatform.iOS;
    return original.copyWith(
      fontFamily: display || (original.fontSize ?? 0) >= 20
          ? displayFamily(target)
          : bodyFamily(target),
      fontFamilyFallback: fallback(target),
      locale: locale,
    );
  }

  static TextTheme _textTheme(TextTheme theme) => TextTheme(
    displayLarge: style(theme.displayLarge!),
    displayMedium: style(theme.displayMedium!),
    displaySmall: style(theme.displaySmall!),
    headlineLarge: style(theme.headlineLarge!),
    headlineMedium: style(theme.headlineMedium!),
    headlineSmall: style(theme.headlineSmall!),
    titleLarge: style(theme.titleLarge!),
    titleMedium: style(theme.titleMedium!),
    titleSmall: style(theme.titleSmall!),
    bodyLarge: style(theme.bodyLarge!),
    bodyMedium: style(theme.bodyMedium!),
    bodySmall: style(theme.bodySmall!),
    labelLarge: style(theme.labelLarge!),
    labelMedium: style(theme.labelMedium!),
    labelSmall: style(theme.labelSmall!),
  );

  static ButtonStyle _button(ButtonStyle? original) =>
      (original ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStateProperty.resolveWith(
          (states) =>
              style(original?.textStyle?.resolve(states) ?? const TextStyle()),
        ),
      );

  /// Component themes can replace inherited TextStyles. Apply the same stack
  /// to those styles as well as the body, including Cupertino's inherit:false
  /// picker and navigation styles.
  static ThemeData theme(ThemeData original) {
    final cupertino = MaterialBasedCupertinoThemeData(materialTheme: original);
    final text = cupertino.textTheme;
    final input = original.inputDecorationTheme;
    return original.copyWith(
      textTheme: _textTheme(original.textTheme),
      primaryTextTheme: _textTheme(original.primaryTextTheme),
      cupertinoOverrideTheme: cupertino.copyWith(
        textTheme: text.copyWith(
          textStyle: style(text.textStyle),
          actionTextStyle: style(text.actionTextStyle),
          actionSmallTextStyle: style(text.actionSmallTextStyle),
          tabLabelTextStyle: style(text.tabLabelTextStyle),
          navTitleTextStyle: style(text.navTitleTextStyle),
          navLargeTitleTextStyle: style(text.navLargeTitleTextStyle),
          navActionTextStyle: style(text.navActionTextStyle),
          pickerTextStyle: style(text.pickerTextStyle),
          dateTimePickerTextStyle: style(text.dateTimePickerTextStyle),
        ),
      ),
      appBarTheme: original.appBarTheme.copyWith(
        titleTextStyle: style(
          original.appBarTheme.titleTextStyle ?? original.textTheme.titleLarge!,
        ),
        toolbarTextStyle: style(
          original.appBarTheme.toolbarTextStyle ??
              original.textTheme.bodyMedium!,
        ),
      ),
      inputDecorationTheme: input.copyWith(
        labelStyle: style(input.labelStyle ?? const TextStyle()),
        floatingLabelStyle: style(
          input.floatingLabelStyle ?? const TextStyle(),
        ),
        hintStyle: style(input.hintStyle ?? const TextStyle()),
        helperStyle: style(input.helperStyle ?? const TextStyle()),
        errorStyle: style(input.errorStyle ?? const TextStyle()),
        prefixStyle: style(input.prefixStyle ?? const TextStyle()),
        suffixStyle: style(input.suffixStyle ?? const TextStyle()),
        counterStyle: style(input.counterStyle ?? const TextStyle()),
      ),
      listTileTheme: original.listTileTheme.copyWith(
        titleTextStyle: style(
          original.listTileTheme.titleTextStyle ??
              original.textTheme.bodyLarge!,
        ),
        subtitleTextStyle: style(
          original.listTileTheme.subtitleTextStyle ??
              original.textTheme.bodySmall!,
        ),
        leadingAndTrailingTextStyle: style(
          original.listTileTheme.leadingAndTrailingTextStyle ??
              original.textTheme.bodySmall!,
        ),
      ),
      chipTheme: original.chipTheme.copyWith(
        labelStyle: style(
          original.chipTheme.labelStyle ?? original.textTheme.labelLarge!,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _button(original.textButtonTheme.style),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _button(original.filledButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _button(original.outlinedButtonTheme.style),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _button(original.elevatedButtonTheme.style),
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
    style: StairTypography.style(const TextStyle()),
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
