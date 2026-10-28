import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/event_editor.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_controls.dart';
import 'package:giristair/ui/stair_theme.dart';

void main() {
  testWidgets(
    'registration follows LiveStair row and section geometry on iPhone',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 1400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final store = GiriStore(storage: MemoryGiriStorage());
      await store.load();
      await tester.pumpWidget(
        MaterialApp(
          locale: StairTypography.locale,
          supportedLocales: const [StairTypography.locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: stairTheme(Brightness.light),
          home: EventEditor(store: store),
        ),
      );
      await tester.pumpAndSettle();

      final header = tester.getRect(find.byType(StairPageHeader));
      final save = tester.getRect(find.byType(OutlinedButton).first);
      final firstRow = tester.getRect(find.byType(StairMenuRow<EventKind>));
      final basic = find.byType(StairFormSection).first;
      final participants = find.byType(StairFormSection).at(1);
      Finder surface(Finder section) => find.descendant(
        of: section,
        matching: find.byWidgetPredicate(
          (widget) => widget is Material &&
              widget.shape is RoundedSuperellipseBorder,
        ),
      ).first;
      final basicSurface = tester.getRect(surface(basic));
      final participantSurface = tester.getRect(surface(participants));
      expect(header.height, 66);
      expect(save.height, 44);
      expect(basicSurface.left, 16);
      expect(basicSurface.top - header.bottom, 8);
      expect(firstRow.height, 48);
      expect(participantSurface.top - basicSurface.bottom, 14);
      expect(
        tester.getSize(find.byKey(const ValueKey('event-participant-0'))).height,
        44,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('keyboard resizing retains the draft and exposes the focused row', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: stairTheme(Brightness.light),
        home: EventEditor(store: store),
      ),
    );
    final title = find.byKey(const ValueKey('event-title'));
    await tester.enterText(title, '編集中の会');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    final participant = find.byKey(const ValueKey('event-participant-0'));
    await tester.ensureVisible(participant);
    await tester.enterText(participant, '参加者');
    await tester.pumpAndSettle();
    expect(tester.getRect(participant).bottom, lessThanOrEqualTo(852 - 320));
    expect(tester.widget<TextFormField>(title).controller!.text, '編集中の会');
    tester.view.viewInsets = const FakeViewPadding();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(participant).controller!.text, '参加者');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
