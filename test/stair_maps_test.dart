import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/ui/stair_maps.dart';

void main() {
  const channel = MethodChannel('giristair/native-maps');

  tearDown(() {
    StairMaps.available = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'native place selection preserves names and coordinates; cancel is null',
    (tester) async {
      Map<String, Object>? response;
      Map<Object?, Object?>? arguments;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'initialize') return {'available': true};
        arguments = call.arguments as Map<Object?, Object?>;
        return response;
      });
      expect(await StairMaps.pickPlace(initialQuery: '  会場名  '), isNull);
      expect(arguments, {'initialQuery': '会場名'});
      response = {
        'name': '大喜利会場',
        'address': '東京都',
        'latitude': 35.68,
        'longitude': 139.76,
      };
      final selected = await StairMaps.pickPlace(initialQuery: '会場名');
      expect(selected!.name, '大喜利会場');
      expect(selected.address, '東京都');
      expect(selected.latitude, 35.68);
      expect(selected.longitude, 139.76);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android leaves native map registration unused',
    (tester) async {
      var calls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls++;
        return {'available': true};
      });
      await StairMaps.initialize();
      expect(StairMaps.available, isFalse);
      expect(await StairMaps.pickPlace(initialQuery: '会場'), isNull);
      expect(calls, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test('malformed or out-of-range coordinates never enter a venue record', () {
    for (final latitude in [double.nan, double.infinity, 91.0]) {
      expect(
        () => StairPlace.fromMap({
          'name': '会場',
          'address': '住所',
          'latitude': latitude,
          'longitude': 139.0,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => StairPlace.fromMap({
        'name': '会場',
        'address': '住所',
        'latitude': 35.0,
        'longitude': -181.0,
      }),
      throwsFormatException,
    );
  });
}
