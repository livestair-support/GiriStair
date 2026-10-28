import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_native_controls.dart';
import 'package:giristair/ui/stair_typography.dart';

void main() {
  const channel = MethodChannel('giristair/native-controls');

  tearDown(() {
    StairNativeControls.available = false;
    StairTypography.configureNativeFonts({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'iOS bridge preserves local clock components and distinguishes cancel from clear',
    (tester) async {
      Map<String, Object?> response = {'committed': false};
      Map<Object?, Object?>? arguments;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'initialize') return {'available': true};
        arguments = call.arguments as Map<Object?, Object?>;
        return response;
      });
      await StairNativeControls.initialize();
      expect(StairNativeControls.available, isTrue);
      final local = DateTime(2026, 10, 28, 23, 45);
      Future<StairNativeDateSelection?> pick() => StairNativeControls.pickDate(
        label: '開始',
        initial: local,
        mode: 'time',
        dark: false,
      );
      expect(await pick(), isNull);
      expect(arguments!['components'], [2026, 10, 28, 23, 45]);
      response = {'committed': true};
      final cleared = await pick();
      expect(cleared, isNotNull);
      expect(cleared!.value, isNull);
      response = {
        'committed': true,
        'components': [2026, 10, 29, 0, 15],
      };
      expect((await pick())!.value, DateTime(2026, 10, 29, 0, 15));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'an older iOS runner without the channel retains the Flutter fallback',
    (tester) async {
      await StairNativeControls.initialize();
      expect(StairNativeControls.available, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android does not request iOS fonts or native view factories',
    (tester) async {
      var calls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls++;
        return {'available': true};
      });
      await StairNativeControls.initialize();
      expect(calls, 0);
      expect(StairNativeControls.available, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
