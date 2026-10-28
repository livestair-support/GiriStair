import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/event_editor.dart';
import 'package:giristair/screens/players.dart';
import 'package:giristair/screens/sharing.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_controls.dart';
import 'package:giristair/ui/stair_theme.dart';

// Linux cannot prove which iOS glyphs CoreText selects. These tests inspect the
// final render styles instead of only checking ThemeData, because component
// themes and Cupertino overlays can replace the app's inherited font stack.
void expectJapaneseStyle(TextStyle? style, {bool display = false}) {
  expect(style, isNotNull);
  expect(
    style!.fontFamily,
    display ? 'CupertinoSystemDisplay' : 'CupertinoSystemText',
  );
  expect(
    style.fontFamilyFallback,
    containsAllInOrder(['Hiragino Sans', 'Hiragino Kaku Gothic ProN']),
  );
  expect(style.locale, const Locale('ja', 'JP'));
}

RenderParagraph paragraph(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );

void expectJapaneseText(
  WidgetTester tester,
  Finder text, {
  bool display = false,
}) {
  final render = paragraph(tester, text);
  expectJapaneseStyle(render.text.style, display: display);
  expect(render.locale, const Locale('ja', 'JP'));
}

void expectJapaneseInput(WidgetTester tester, Finder field) {
  final state = tester.state<EditableTextState>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  expectJapaneseStyle(state.renderEditable.text!.style);
  expect(state.renderEditable.locale, const Locale('ja', 'JP'));
}

void configureIPhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget japaneseApp(Widget screen) => MaterialApp(
  locale: const Locale('ja', 'JP'),
  supportedLocales: const [Locale('ja', 'JP')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: stairTheme(Brightness.light),
  home: screen,
);

void main() {
  testWidgets(
    'registration input, menu and Cupertino help keep Japanese fonts',
    (tester) async {
      configureIPhone(tester);
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await tester.pumpWidget(japaneseApp(EventEditor(store: store)));
      await tester.pumpAndSettle();

      expectJapaneseText(tester, find.text('登録'), display: true);
      expectJapaneseText(tester, find.text('基本情報'));
      expectJapaneseText(tester, find.text('会の種類'));
      expectJapaneseText(tester, find.text('会・大会名 *'));
      expectJapaneseInput(tester, find.byKey(const ValueKey('event-title')));
      // Family aliases alone did not change the thin body weight on-device.
      // Inspect rendered controls, including inherited TextFormField styles.
      expect(
        paragraph(tester, find.text('会の種類')).text.style!.fontWeight,
        FontWeight.w500,
      );
      expect(
        paragraph(tester, find.text('通常会')).text.style!.fontWeight,
        FontWeight.w500,
      );
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const ValueKey('event-title')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.renderEditable.text!.style!.fontWeight, FontWeight.w500);
      expect(
        paragraph(tester, find.text('会・大会名 *')).text.style!.fontWeight,
        FontWeight.w500,
      );

      await tester.tap(find.byType(StairMenuRow<MeetingType>));
      await tester.pumpAndSettle();
      expectJapaneseText(tester, find.text('大会'));
      await tester.tap(find.text('大会'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('形式の説明'));
      await tester.pumpAndSettle();
      final dialog = find.byWidgetPredicate(
        (widget) => widget is CupertinoAlertDialog,
      );
      expect(dialog, findsOneWidget);
      final textWidgets = find.descendant(
        of: dialog,
        matching: find.byType(Text),
      );
      expect(textWidgets, findsAtLeastNWidgets(3));
      for (final element in textWidgets.evaluate()) {
        expectJapaneseText(tester, find.byWidget(element.widget));
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'player navigation, search and save use the Japanese font stack',
    (tester) async {
      configureIPhone(tester);
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await store.savePlayer(
        const GiriPlayer(id: 'player', name: '参加者の名前', furigana: 'さんかしゃ'),
      );
      await tester.pumpWidget(japaneseApp(PlayerDirectoryScreen(store: store)));
      await tester.pumpAndSettle();

      expectJapaneseText(tester, find.text('大喜利プレイヤー一覧'));
      expectJapaneseText(tester, find.text('参加者の名前'));
      expectJapaneseText(tester, find.text('さんかしゃ'));
      expectJapaneseText(tester, find.text('名前・フリガナで検索'));
      expectJapaneseInput(tester, find.byType(TextField));

      await tester.tap(find.byTooltip('プレイヤーを追加'));
      await tester.pumpAndSettle();
      expectJapaneseText(tester, find.text('プレイヤーを追加'));
      expectJapaneseText(tester, find.text('プレイヤー名 *'));
      expectJapaneseText(tester, find.text('保存'));
      expectJapaneseInput(tester, find.byType(TextField).first);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'shared-image preview and its controls retain Japanese fonts',
    (tester) async {
      configureIPhone(tester);
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await store.saveEvent(
        GiriEvent(
          id: 'event',
          title: '日本語の大喜利会',
          kind: EventKind.live,
          meetingType: MeetingType.casual,
          createdAt: DateTime(2026, 10, 28),
          eventDate: DateTime(2026, 10, 28),
          status: EventStatus.attended,
          venue: '日本語の会場',
        ),
      );
      await tester.pumpWidget(japaneseApp(ShareRecordsScreen(store: store)));
      await tester.pumpAndSettle();

      expectJapaneseText(tester, find.text('共有ページ'));
      expectJapaneseText(tester, find.text('期間'));
      expectJapaneseText(tester, find.text('参加の記録'));
      expectJapaneseText(tester, find.text('日本語の会場'));
      expectJapaneseText(tester, find.text('画像を共有'));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
