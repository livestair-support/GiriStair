import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_theme.dart';

void main() {
  testWidgets('44pt toolbar preserves the edit label height and tap target', (
    tester,
  ) async {
    var edits = 0;
    for (final scale in [1.0, 1.4]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: stairTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: Scaffold(
            appBar: StairNavigationBar(
              title: const Text('詳細'),
              actions: [
                StairBarButton(
                  onPressed: () => edits++,
                  child: const Text('編集'),
                ),
              ],
            ),
            body: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = find.text('編集');
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: label, matching: find.byType(RichText)),
      );
      final naturalHeight = paragraph.getMinIntrinsicHeight(
        paragraph.size.width,
      );
      expect(naturalHeight, greaterThan(12));
      expect(paragraph.size.height, greaterThanOrEqualTo(naturalHeight));
      final action = tester.getRect(find.byType(StairBarButton));
      final text = tester.getRect(label);
      expect(action.height, 44);
      expect(action.width, greaterThanOrEqualTo(44));
      expect(text.top, greaterThanOrEqualTo(action.top));
      expect(text.bottom, lessThanOrEqualTo(action.bottom));
      await tester.tap(find.byType(StairBarButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(edits, 2);
  });

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
