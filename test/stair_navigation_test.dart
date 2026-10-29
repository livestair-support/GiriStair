import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_theme.dart';

void main() {
  testWidgets(
    'secondary pages use a chevron and return through the route stack',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: stairTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: CupertinoButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const Scaffold(
                      appBar: StairNavigationBar(title: Text('詳細')),
                      body: Text('詳細の内容'),
                    ),
                  ),
                ),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.byType(StairBackButton), findsOneWidget);
      expect(find.text('詳細の内容'), findsOneWidget);
      await tester.tap(find.byType(StairBackButton));
      await tester.pumpAndSettle();
      expect(find.text('開く'), findsOneWidget);
      expect(find.text('詳細の内容'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled back keeps the page and its unsaved content', (
    tester,
  ) async {
    var invoked = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: stairTheme(Brightness.light),
        home: Scaffold(
          appBar: StairNavigationBar(
            title: const Text('編集中'),
            leading: StairBackButton(
              enabled: false,
              onPressed: () => invoked = true,
            ),
          ),
          body: const Text('未保存の内容'),
        ),
      ),
    );
    await tester.tap(find.byType(StairBackButton));
    await tester.pump();
    expect(invoked, isFalse);
    expect(find.text('未保存の内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
