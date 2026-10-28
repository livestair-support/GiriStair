import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_symbols.dart';

void main() {
  const channel = MethodChannel('giristair/native-symbols');
  const tint = Color(0xFFF0456E);

  Widget icon(IconData data) => CupertinoApp(
    home: Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: StairSymbolIcon(
          icon: data,
          size: 14,
          weight: FontWeight.w600,
          color: tint,
        ),
      ),
    ),
  );

  testWidgets(
    'native glyphs retain their natural bounds and receive tint',
    (tester) async {
      MethodCall? request;
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        request = call;
        return {
          'slider.horizontal.3/14/600': {
            'bytes': base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
            ),
            'width': 16.0,
            'height': 12.0,
          },
        };
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await StairSymbols.initialize(scale: 3);
      expect(request!.method, 'rasterize');
      final arguments = request!.arguments as Map;
      expect(arguments['scale'], 3);
      expect(arguments['symbols'], contains('slider.horizontal.3'));
      await tester.pumpWidget(icon(CupertinoIcons.slider_horizontal_3));
      await tester.pumpAndSettle();
      expect(find.byType(Icon), findsNothing);
      expect(tester.getSize(find.byType(Image)), const Size(16, 12));
      expect(tester.widget<Image>(find.byType(Image)).color, tint);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'older iOS runner and unsupported glyphs keep fallback icons',
    (tester) async {
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        throw MissingPluginException();
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await StairSymbols.initialize();
      await tester.pumpWidget(icon(CupertinoIcons.slider_horizontal_3));
      expect(find.byType(Icon), findsOneWidget);
      expect(tester.widget<Icon>(find.byType(Icon)).color, tint);
      expect(StairSymbols.nameFor(CupertinoIcons.wifi), isNull);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android draws without invoking the iOS symbol channel',
    (tester) async {
      var calls = 0;
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        calls++;
        return null;
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await StairSymbols.initialize();
      await tester.pumpWidget(icon(CupertinoIcons.person_2));
      expect(calls, 0);
      expect(find.byType(Icon), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
