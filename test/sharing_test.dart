import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/sharing.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_theme.dart';

void main() {
  Future<GiriStore> makeStore({int count = 1}) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    for (var index = 0; index < count; index++) {
      await store.saveEvent(
        GiriEvent(
          id: '$index',
          title: '会$index',
          kind: EventKind.live,
          meetingType: MeetingType.tournament,
          createdAt: DateTime(2026),
          eventDate: DateTime(2026, 1, index + 1),
          status: EventStatus.attended,
          venue: '公開を選べる会場',
          participants: const ['公開を選べる参加者'],
          placement: 1,
        ),
      );
    }
    return store;
  }

  Future<void> showScreen(
    WidgetTester tester,
    GiriStore store, {
    bool list = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: stairTheme(Brightness.dark),
        home: ShareRecordsScreen(store: store, initialList: list),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'list previews all records over explicit pages on narrow iPhone',
    (tester) async {
      final store = await makeStore(count: 16);
      await showScreen(tester, store, list: true);
      expect(find.text('会0'), findsOneWidget);
      expect(find.text('会14'), findsOneWidget);
      expect(find.text('会15'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(find.byTooltip('次のページ'), 500);
      await tester.tap(find.byTooltip('次のページ'));
      await tester.pumpAndSettle();
      expect(find.text('会15'), findsOneWidget);
      expect(find.text('会0'), findsNothing);
      expect(find.text('2 / 2 ページ'), findsOneWidget);
      expect(find.text('GiriStair  ·  2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('前のページ'));
      await tester.pumpAndSettle();
      expect(find.text('会0'), findsOneWidget);
      expect(find.text('会15'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'summary respects venue and participant visibility before sharing',
    (tester) async {
      final store = await makeStore();
      await showScreen(tester, store);
      // Building the complete preview still shows no participant name by default.
      expect(find.text('公開を選べる会場'), findsOneWidget);
      expect(find.text('公開を選べる参加者'), findsNothing);
      await tester.tap(find.byType(CupertinoSwitch).at(0));
      await tester.pumpAndSettle();
      expect(find.text('公開を選べる会場'), findsNothing);

      await tester.tap(find.byType(CupertinoSwitch).at(2));
      await tester.pumpAndSettle();
      expect(find.text('公開を選べる参加者'), findsOneWidget);
      await tester.tap(find.byType(CupertinoSwitch).at(2));
      await tester.pumpAndSettle();
      expect(find.text('公開を選べる参加者'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  testWidgets('image kind menu switches previews and resets the list page', (tester) async {
    final store = await makeStore(count: 16);
    await showScreen(tester, store, list: true);
    expect(find.byType(CupertinoSlidingSegmentedControl<bool>), findsNothing);
    await tester.scrollUntilVisible(find.byTooltip('次のページ'), 500);
    await tester.tap(find.byTooltip('次のページ'));
    await tester.pumpAndSettle();
    expect(find.text('会15'), findsOneWidget);

    Future<void> chooseImage(String kind) async {
      final menu = find.byKey(const ValueKey('share-image-kind'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(kind).last);
      await tester.pumpAndSettle();
    }

    await chooseImage('Summary');
    expect(find.text('大喜利 Summary'), findsOneWidget);
    expect(find.byTooltip('次のページ'), findsNothing);
    await chooseImage('List');
    expect(find.text('大喜利 List'), findsOneWidget);
    expect(find.text('会0'), findsOneWidget);
    expect(find.text('会15'), findsNothing);
    expect(find.text('1 / 2 ページ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

}
