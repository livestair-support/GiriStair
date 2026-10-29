import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_controls.dart';
import 'package:giristair/ui/stair_theme.dart';

void main() {
  for (final timeOnly in [false, true]) {
    testWidgets(
      '${timeOnly ? 'time' : 'date and time'} uses five-minute wheels without rewriting canceled values',
      (tester) async {
        final original = DateTime(2026, 10, 28, 23, 47);
        DateTime? value = original;
        final changes = <DateTime?>[];
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ja'),
            supportedLocales: const [Locale('ja')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: stairTheme(Brightness.light),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  void changed(DateTime? next) => setState(() {
                    value = next;
                    changes.add(next);
                  });
                  return timeOnly
                      ? StairTimeButton(
                          label: '開始',
                          date: DateTime(2026, 10, 28),
                          value: value,
                          onChanged: changed,
                        )
                      : StairDateRow(
                          label: '投稿開始',
                          value: value,
                          onChanged: changed,
                        );
                },
              ),
            ),
          ),
        );
        final control = timeOnly
            ? find.byType(StairTimeButton)
            : find.byType(StairDateRow);
        await tester.tap(control);
        await tester.pumpAndSettle();
        var picker = tester.widget<CupertinoDatePicker>(
          find.byType(CupertinoDatePicker),
        );
        expect(picker.minuteInterval, 5);
        expect(picker.initialDateTime.minute % 5, 0);
        expect(value, original);
        expect(changes, isEmpty);
        await tester.tap(find.text('キャンセル'));
        await tester.pumpAndSettle();
        expect(value, original);
        expect(changes, isEmpty);

        await tester.tap(control);
        await tester.pumpAndSettle();
        picker = tester.widget<CupertinoDatePicker>(
          find.byType(CupertinoDatePicker),
        );
        final selected = DateTime(2026, 10, 28, 23, 50);
        picker.onDateTimeChanged(selected);
        await tester.tap(find.text('完了'));
        await tester.pumpAndSettle();
        expect(value, selected);
        expect(changes, [selected]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
