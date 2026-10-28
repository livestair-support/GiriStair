import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_tab_bar.dart';
import 'package:giristair/ui/stair_theme.dart';

void main() {
  testWidgets('fallback keeps five tabs, selection and no invented capsule', (
    tester,
  ) async {
    var selected = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: stairTheme(Brightness.light),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: StairTabBar(
              currentIndex: selected,
              onTap: (index) => setState(() => selected = index),
            ),
          ),
        ),
      ),
    );
    for (final title in ['登録', '一覧', '戦績', '思考', '設定']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(AnimatedContainer), findsNothing);
    await tester.tap(find.text('思考'));
    await tester.pumpAndSettle();
    expect(selected, 3);
    expect(tester.widget<CupertinoTabBar>(find.byType(CupertinoTabBar)).currentIndex, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native tab view forwards selection and measured height without recreation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final messenger = tester.binding.defaultBinaryMessenger;
      final configurations = <Map<Object?, Object?>>[];
      MethodChannel? nativeChannel;
      var creations = 0;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
        if (call.method == 'create') {
          creations++;
          final arguments = call.arguments as Map<Object?, Object?>;
          expect(arguments['viewType'], 'giristair/native-tab-bar');
          nativeChannel = MethodChannel('giristair/native-tab-bar/${arguments['id']}');
          messenger.setMockMethodCallHandler(nativeChannel!, (call) async {
            if (call.method == 'configure') {
              configurations.add(call.arguments as Map<Object?, Object?>);
            }
            return null;
          });
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (nativeChannel != null) messenger.setMockMethodCallHandler(nativeChannel!, null);
      });
      var selected = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: stairTheme(Brightness.light),
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: StairTabBar(
                nativeAvailable: true,
                currentIndex: selected,
                onTap: (index) => setState(() => selected = index),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsOneWidget);
      expect(creations, 1);
      expect(configurations.last['selectedIndex'], 1);
      Future<void> send(String method, Object arguments) async {
        await messenger.handlePlatformMessage(
          nativeChannel!.name,
          nativeChannel!.codec.encodeMethodCall(MethodCall(method, arguments)),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      await send('heightChanged', 96.0);
      expect(tester.getSize(find.byType(UiKitView)).height, 96);
      await send('select', 4);
      expect(selected, 4);
      expect(configurations.last['selectedIndex'], 4);
      expect(creations, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
