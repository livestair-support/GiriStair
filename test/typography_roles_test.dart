import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_typography.dart';

void main() {
  tearDown(() => StairTypography.configureNativeFonts({}));

  test('LiveStair roles keep regular inputs distinct from medium labels', () {
    for (final role in [
      StairTextRole.input,
      StairTextRole.value,
      StairTextRole.menuItem,
      StairTextRole.button,
    ]) {
      final style = StairTypography.role(role, platform: TargetPlatform.iOS);
      expect(style.fontSize, 17);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.height, isNull);
    }
    final label = StairTypography.role(StairTextRole.formLabel);
    expect(label.fontSize, 15);
    expect(label.fontWeight, FontWeight.w500);
    final date = StairTypography.role(StairTextRole.dateValue);
    expect(date.fontSize, 17);
    expect(date.fontWeight, FontWeight.w600);
    expect(StairTypography.role(StairTextRole.pageTitle).fontSize, 34);
    expect(StairTypography.role(StairTextRole.sectionTitle).fontSize, 18);
    expect(StairTypography.usesRoundedDesign(StairTextRole.pageTitle), isFalse);
    expect(StairTypography.usesRoundedDesign(StairTextRole.sectionTitle), isTrue);
  });

  test('device-resolved faces preserve rounded design and Japanese weight', () {
    StairTypography.configureNativeFonts({
      'sectionTitle': {
        'latinPostscriptName': 'DeviceRoundedBold',
        'japanesePostscriptName': 'DeviceJapaneseRoundedBold',
      },
      'input': {'japanesePostscriptName': 'DeviceJapaneseRegular'},
      'saveButton': {'japanesePostscriptName': 'DeviceJapaneseBold'},
    });
    final section = StairTypography.role(
      StairTextRole.sectionTitle,
      platform: TargetPlatform.iOS,
    );
    expect(section.fontFamily, 'DeviceRoundedBold');
    expect(section.fontFamilyFallback, ['DeviceJapaneseRoundedBold']);
    final input = StairTypography.role(
      StairTextRole.input,
      platform: TargetPlatform.iOS,
    );
    expect(input.fontFamily, 'CupertinoSystemText');
    expect(input.fontFamilyFallback, ['DeviceJapaneseRegular']);
    final bold = StairTypography.style(
      const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      platform: TargetPlatform.iOS,
    );
    expect(bold.fontFamilyFallback, ['DeviceJapaneseBold']);
    expect(bold.fontWeight, FontWeight.w700);
  });

  test('iOS font metadata never imposes Apple fonts on Android', () {
    StairTypography.configureNativeFonts({
      'sectionTitle': {
        'latinPostscriptName': 'DeviceRoundedBold',
        'japanesePostscriptName': 'DeviceJapaneseRoundedBold',
      },
    });
    for (final role in StairTextRole.values) {
      final style = StairTypography.role(role, platform: TargetPlatform.android);
      expect(style.fontFamily, isNull);
      expect(style.fontFamilyFallback, isNull);
      expect(style.locale, const Locale('ja', 'JP'));
    }
    final theme = StairTypography.theme(ThemeData(platform: TargetPlatform.android));
    expect(theme.textTheme.bodyLarge!.fontFamily, isNot(contains('Cupertino')));
    expect(theme.textTheme.bodyLarge!.fontFamilyFallback, isNot(contains('Hiragino Sans')));
  });
}
