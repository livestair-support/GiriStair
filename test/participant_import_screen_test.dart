import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/screens/participant_import.dart';
import 'package:giristair/ui/stair_theme.dart';

void main() {
  testWidgets('OCR is reviewed and corrected before names are returned', (
    tester,
  ) async {
    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: stairTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<List<String>>(
                  MaterialPageRoute(
                    builder: (_) => ParticipantImportScreen(
                      existingNames: const ['登録済み'],
                      readImages: () async =>
                          '参加者一覧\n1. 登録済み\n2. 読み間違い\n3. 新しい人',
                    ),
                  ),
                );
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('participant-import-images')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('2人を追加'), findsOneWidget);
    final correction = find.byKey(const ValueKey('participant-import-name-1'));
    await tester.ensureVisible(correction);
    await tester.enterText(correction, '正しい名前');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('participant-import-apply')));
    await tester.pumpAndSettle();
    expect(result, ['正しい名前', '新しい人']);
  });

  testWidgets('OCR failure leaves the text editable for copy and paste', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: stairTheme(Brightness.light),
        home: ParticipantImportScreen(
          readImages: () async => throw StateError('Image unavailable'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('participant-import-images')));
    await tester.pumpAndSettle();
    expect(find.textContaining('画像を読み取れませんでした'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('participant-import-source')),
      '手入力の人',
    );
    await tester.tap(find.byKey(const ValueKey('participant-import-preview')));
    await tester.pumpAndSettle();
    expect(find.text('1人を追加'), findsOneWidget);
  });
}
