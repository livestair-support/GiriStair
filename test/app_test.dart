import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/app.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';

void main() {
  testWidgets('five requested tabs, with aggregation inside settings', (
    tester,
  ) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await tester.pumpWidget(GiriStairApp(store: store));
    await tester.pumpAndSettle();

    final navigation = find.byType(CupertinoTabBar);
    for (final title in ['登録', '一覧', '戦績', '思考', '設定']) {
      expect(
        find.descendant(of: navigation, matching: find.text(title)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: navigation, matching: find.text('集計')),
      findsNothing,
    );
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('設定')),
    );
    await tester.pumpAndSettle();
    expect(find.text('集計'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('failed load protects records and can be retried', (
    tester,
  ) async {
    final storage = MemoryGiriStorage('invalid data');
    final store = GiriStore(storage: storage);
    await tester.pumpWidget(GiriStairApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('記録を読み込めませんでした'), findsOneWidget);
    expect(find.byType(CupertinoTabBar), findsNothing);
    expect(storage.contents, 'invalid data');

    storage.contents = null;
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoTabBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
