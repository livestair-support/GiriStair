import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_controls.dart';
import 'package:giristair/ui/stair_theme.dart';

Widget controlApp(Widget child) => MaterialApp(
  locale: const Locale('ja'),
  supportedLocales: const [Locale('ja')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: stairTheme(Brightness.light),
  home: Scaffold(body: child),
);

Future<void> openDatePicker(WidgetTester tester) async {
  await tester.tap(find.byType(StairDateRow));
  await tester.pumpAndSettle();
}

void selectPickerDate(WidgetTester tester, DateTime date) {
  if (find.byType(CalendarDatePicker).evaluate().isNotEmpty) {
    tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker)).onDateChanged(date);
    return;
  }
  // Simulate a wheel selection. The wheel itself is provided by Flutter;
  // these tests verify when GiriStair commits that draft to the form.
  tester
      .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
      .onDateTimeChanged(date);
}

void main() {
  testWidgets(
    'date changes stay draft until Done; cancel and dismissal discard them',
    (tester) async {
      final original = DateTime(2026, 10, 28);
      DateTime? value = original;
      final changes = <DateTime?>[];
      await tester.pumpWidget(
        controlApp(
          StatefulBuilder(
            builder: (context, setState) => StairDateRow(
              label: '日付',
              value: value,
              dateOnly: true,
              onChanged: (next) => setState(() {
                value = next;
                changes.add(next);
              }),
            ),
          ),
        ),
      );

      await openDatePicker(tester);
      selectPickerDate(tester, DateTime(2026, 11, 2));
      expect(value, original);
      expect(changes, isEmpty);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(value, original);
      expect(changes, isEmpty);

      await openDatePicker(tester);
      selectPickerDate(tester, DateTime(2026, 11, 3));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(value, original);
      expect(changes, isEmpty);

      await openDatePicker(tester);
      final confirmed = DateTime(2026, 11, 4);
      selectPickerDate(tester, confirmed);
      await tester.tap(find.text('完了'));
      await tester.pumpAndSettle();
      expect(value, confirmed);
      expect(changes, [confirmed]);
      expect(find.text('2026年11月4日(水)'), findsOneWidget);

      await openDatePicker(tester);
      await tester.tap(find.text('未定に戻す'));
      await tester.pumpAndSettle();
      expect(value, isNull);
      expect(changes, [confirmed, null]);
      expect(find.text('未設定'), findsOneWidget);
    },
  );

  testWidgets(
    'unknown time stays unset on cancel and saves on its meeting day',
    (tester) async {
      final meetingDay = DateTime(2026, 12, 7);
      DateTime? value;
      final changes = <DateTime?>[];
      await tester.pumpWidget(
        controlApp(
          StatefulBuilder(
            builder: (context, setState) => StairTimeButton(
              label: '開始',
              date: meetingDay,
              value: value,
              onChanged: (next) => setState(() {
                value = next;
                changes.add(next);
              }),
            ),
          ),
        ),
      );
      expect(find.text('--:--'), findsOneWidget);

      await tester.tap(find.text('--:--'));
      await tester.pumpAndSettle();
      selectPickerDate(tester, DateTime(2030, 1, 1, 19, 30));
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(value, isNull);
      expect(changes, isEmpty);

      await tester.tap(find.text('--:--'));
      await tester.pumpAndSettle();
      selectPickerDate(tester, DateTime(2030, 1, 1, 19, 30));
      await tester.tap(find.text('完了'));
      await tester.pumpAndSettle();
      expect(value, DateTime(2026, 12, 7, 19, 30));
      expect(changes, [DateTime(2026, 12, 7, 19, 30)]);
      expect(find.text('19:30'), findsOneWidget);

      await tester.tap(find.text('19:30'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('未定に戻す'));
      await tester.pumpAndSettle();
      expect(value, isNull);
      expect(changes.last, isNull);
      expect(find.text('--:--'), findsOneWidget);
    },
  );

  testWidgets('choice menu changes only when an option is selected', (
    tester,
  ) async {
    var value = 'live';
    final changes = <String>[];
    await tester.pumpWidget(
      controlApp(
        StatefulBuilder(
          builder: (context, setState) => StairMenuRow<String>(
            label: '形式',
            value: value,
            items: const {'live': '生大喜利', 'online': 'ネット大喜利'},
            onChanged: (next) => setState(() {
              value = next;
              changes.add(next);
            }),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(StairMenuRow<String>));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(value, 'live');
    expect(changes, isEmpty);

    await tester.tap(find.byType(StairMenuRow<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ネット大喜利'));
    await tester.pumpAndSettle();
    expect(value, 'online');
    expect(changes, ['online']);
    expect(find.text('ネット大喜利'), findsOneWidget);
  });
}
