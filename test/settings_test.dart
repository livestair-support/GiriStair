import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/screens/settings.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  Future<void> openSettings(WidgetTester tester, GiriStore store) async {
    tester.view.physicalSize = const Size(430, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PackageInfo.setMockInitialValues(
      appName: 'GiriStair',
      packageName: 'com.livestair.giristair',
      version: '0.2.0',
      buildNumber: '8',
      buildSignature: '',
    );
    await store.load();
    await tester.pumpWidget(MaterialApp(
      theme: stairTheme(Brightness.light),
      home: SettingsScreen(store: store),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('settings groups collapse and version belongs to support', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await openSettings(tester, store);

    for (final title in ['共有ページ', '集計', 'デフォルト設定', '通知', 'データ管理', 'サポート']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('保存について'), findsNothing);
    expect(find.text('大喜利をする人の、予定と記録と思考。'), findsNothing);
    expect(find.text('0.2.0'), findsOneWidget);
    expect(find.text('バックアップを保存'), findsNothing);
    expect(find.byType(CupertinoSwitch), findsNothing);

    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(find.text('予定・締切の通知'), findsOneWidget);
    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoSwitch), findsNothing);

    await tester.tap(find.text('データ管理'));
    await tester.pumpAndSettle();
    expect(find.text('バックアップを保存'), findsOneWidget);
    expect(find.text('バックアップから復元'), findsOneWidget);
    expect(tester.getTopLeft(find.text('バージョン')).dy,
        greaterThan(tester.getTopLeft(find.text('サポート・お問い合わせ')).dy));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('theme choice is saved and survives a reload', (tester) async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await openSettings(tester, store);
    await tester.tap(find.text('テーマ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ダーク'));
    await tester.pumpAndSettle();
    expect(store.preferences.theme, 'dark');
    final reloaded = GiriStore(storage: storage);
    await reloaded.load();
    expect(reloaded.preferences.theme, 'dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    reloaded.dispose();
  });
}
