import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_theme.dart';

void main() {
  testWidgets('dark body and editable text retain a visible foreground', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: stairTheme(Brightness.dark),
        home: const Scaffold(body: Column(children: [Text('本文'), TextField()])),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text('本文'), matching: find.byType(RichText)),
    );
    expect(paragraph.text.style!.color, Colors.white);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).style.color,
      Colors.white,
    );
    expect(tester.takeException(), isNull);
  });

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
    expect(
      StairTypography.usesRoundedDesign(StairTextRole.sectionTitle),
      isTrue,
    );
  });

  test('device families preserve rounded design and Japanese weights', () {
    StairTypography.configureNativeFonts({
      'sectionTitle': {
        'latinFamilyName': 'Device Rounded',
        'japaneseFamilyName': 'Device Japanese Rounded',
        'latinPostscriptName': 'DeviceRounded-Bold',
        'japanesePostscriptName': 'DeviceJapaneseRounded-Bold',
      },
      'input': {
        'latinFamilyName': 'Device System',
        'japaneseFamilyName': 'Device Japanese',
        'japanesePostscriptName': 'DeviceJapanese-Regular',
      },
      'saveButton': {
        'latinFamilyName': 'Device System',
        'japaneseFamilyName': 'Device Japanese',
        'japanesePostscriptName': 'DeviceJapanese-Bold',
      },
      'pageTitle': {
        'latinFamilyName': 'Device System',
        'japaneseFamilyName': 'Device Japanese',
      },
    });
    final section = StairTypography.role(
      StairTextRole.sectionTitle,
      platform: TargetPlatform.iOS,
    );
    expect(section.fontFamily, 'Device Rounded');
    expect(section.fontFamilyFallback, ['Device Japanese Rounded']);
    final input = StairTypography.role(
      StairTextRole.input,
      platform: TargetPlatform.iOS,
    );
    expect(input.fontFamily, 'Device System');
    expect(input.fontFamilyFallback, ['Device Japanese']);
    expect(input.fontWeight, FontWeight.w400);
    final bold = StairTypography.style(
      const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      platform: TargetPlatform.iOS,
    );
    expect(bold.fontFamily, 'Device System');
    expect(bold.fontFamilyFallback, ['Device Japanese']);
    expect(bold.fontWeight, FontWeight.w700);
    final page = StairTypography.role(
      StairTextRole.pageTitle,
      platform: TargetPlatform.iOS,
    );
    expect(page.fontFamily, 'CupertinoSystemDisplay');
    expect(page.fontFamilyFallback, ['Device Japanese']);
  });

  test('PostScript-only metadata does not masquerade as a font family', () {
    StairTypography.configureNativeFonts({
      'input': {
        'latinPostscriptName': 'DeviceSystem-Regular',
        'japanesePostscriptName': 'DeviceJapanese-Regular',
      },
    });
    final input = StairTypography.role(
      StairTextRole.input,
      platform: TargetPlatform.iOS,
    );
    expect(input.fontFamily, 'CupertinoSystemText');
    expect(input.fontFamilyFallback, [
      'Hiragino Sans',
      'Hiragino Kaku Gothic ProN',
    ]);
  });

  test('iOS font metadata never imposes Apple fonts on Android', () {
    StairTypography.configureNativeFonts({
      'sectionTitle': {
        'latinFamilyName': 'Device Rounded',
        'japaneseFamilyName': 'Device Japanese Rounded',
        'latinPostscriptName': 'DeviceRoundedBold',
        'japanesePostscriptName': 'DeviceJapaneseRoundedBold',
      },
    });
    for (final role in StairTextRole.values) {
      final style = StairTypography.role(
        role,
        platform: TargetPlatform.android,
      );
      expect(style.fontFamily, isNull);
      expect(style.fontFamilyFallback, isNull);
      expect(style.locale, const Locale('ja', 'JP'));
    }
    final theme = StairTypography.theme(
      ThemeData(platform: TargetPlatform.android),
    );
    expect(theme.textTheme.bodyLarge!.fontFamily, isNot(contains('Cupertino')));
    expect(
      theme.textTheme.bodyLarge!.fontFamilyFallback,
      isNot(contains('Hiragino Sans')),
    );
  });
}
