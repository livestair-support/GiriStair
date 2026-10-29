import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/players.dart';
import 'package:giristair/screens/profile_setup.dart';
import 'package:giristair/screens/venues.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/player_widgets.dart';
import 'package:giristair/ui/stair_maps.dart';
import 'package:giristair/ui/stair_theme.dart';

GiriEvent historicalEvent() => GiriEvent(
  id: 'history-event',
  title: '過去の会',
  kind: EventKind.live,
  meetingType: MeetingType.casual,
  status: EventStatus.attended,
  createdAt: DateTime(2026, 10, 28),
  venue: '以前の会場',
  participants: const ['以前の名前'],
);

Future<GiriStore> historicalStore() async {
  final store = GiriStore(
    storage: MemoryGiriStorage(jsonEncode({
      'schemaVersion': 1,
      'events': [historicalEvent().toJson()],
      'notes': [],
    })),
  );
  await store.load();
  return store;
}

Future<void> showScreen(WidgetTester tester, Widget screen) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 1500);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    theme: stairTheme(Brightness.light),
    home: screen,
  ));
  await tester.pumpAndSettle();
}

Finder fieldWithHint(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);

void main() {
  testWidgets('initial name setup waits for a nonempty saved profile', (tester) async {
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await store.load();
    var completed = false;
    await showScreen(tester, SelfProfileScreen(
      store: store,
      initialSetup: true,
      onCompleted: () => completed = true,
    ));
    expect(tester.widget<CupertinoButton>(find.byKey(const ValueKey('self-name-save'))).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('self-name')), '  自分の名前  ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('self-name-save')));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(store.preferences.selfName, '自分の名前');
    expect(store.preferences.onboardingCompleted, isTrue);
    expect(store.playerByName('自分の名前'), isNotNull);
    final reopened = GiriStore(storage: storage);
    await reopened.load();
    expect(reopened.preferences.selfName, '自分の名前');
    expect(reopened.preferences.onboardingCompleted, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    reopened.dispose();
  });

  testWidgets('historical player remains open after profile registration and rename', (tester) async {
    final store = await historicalStore();
    final player = store.playerDirectory.single;
    expect(player.id.startsWith('history:'), isTrue);
    await showScreen(tester, PlayerDetailScreen(store: store, playerId: player.id));
    await tester.tap(find.text('編集'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint('プレイヤー名 *'), '新しい名前');
    await tester.enterText(fieldWithHint('地域・都道府県'), '大阪府');
    await tester.enterText(fieldWithHint('X（Twitter）のユーザー名・URL'), '@player_name');
    await tester.enterText(fieldWithHint('プレイヤーについてのメモ'), '地域のプレイヤー');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-detail-name')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('player-detail-name'))).data, '新しい名前');
    expect(find.text('登録情報がありません'), findsNothing);
    final saved = store.players.single;
    expect(saved.id.startsWith('history:'), isFalse);
    expect(saved.region, '大阪府');
    expect(saved.twitterUrl, '@player_name');
    expect(saved.memo, '地域のプレイヤー');
    expect(store.events.single.participants, ['新しい名前']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('icon auto mode reacts to profiles and explicit visibility', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.savePlayer(const GiriPlayer(id: 'a', name: 'A'));
    await showScreen(tester, Scaffold(body: PlayerAvatar(store: store, name: 'A')));
    expect(find.byType(ClipOval), findsNothing);
    await store.savePlayer(const GiriPlayer(
      id: 'b',
      name: 'B',
      iconDataBase64: 'not-base64',
    ));
    await tester.pump();
    expect(find.byType(ClipOval), findsOneWidget);
    await store.savePreferences(store.preferences.copyWith(playerIconMode: 'hide'));
    await tester.pump();
    expect(find.byType(ClipOval), findsNothing);
    await store.savePreferences(store.preferences.copyWith(playerIconMode: 'show'));
    await tester.pump();
    expect(find.byType(ClipOval), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('historical venue detail follows its durable edited profile', (tester) async {
    final store = await historicalStore();
    final venue = store.venueDirectory.single;
    expect(venue.id.startsWith('history:'), isTrue);
    await showScreen(tester, VenueDetailScreen(store: store, venueId: venue.id));
    await tester.tap(find.text('編集'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('venue-name')), '新しい会場');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('venue-detail-name'))).data, '新しい会場');
    expect(store.venues.single.id.startsWith('history:'), isFalse);
    expect(store.events.single.venue, '新しい会場');
    expect(store.events.single.venueId, store.venues.single.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('venue detail saves a map directly and keeps it when selection is canceled', (tester) async {
    const channel = MethodChannel('giristair/native-maps');
    var selections = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pickPlace') {
        if (selections++ > 0) return null;
        return {
          'name': '地図から選んだ会場',
          'address': '東京都中野区',
          'latitude': 35.7,
          'longitude': 139.6,
        };
      }
      return {'available': true};
    });
    StairMaps.available = true;
    addTearDown(() {
      StairMaps.available = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final store = await historicalStore();
    await showScreen(tester, VenueDetailScreen(
      store: store,
      venueId: store.venueDirectory.single.id,
    ));
    await tester.tap(find.byKey(const ValueKey('venue-detail-map-select')));
    await tester.pumpAndSettle();
    expect(find.byType(StairMapPreview), findsOneWidget);
    expect(find.text('会場を編集'), findsNothing);
    final venue = store.venues.single;
    expect(venue.name, '以前の会場');
    expect(venue.prefecture, '東京都');
    expect(venue.mapAddress, '東京都中野区');
    expect(venue.latitude, 35.7);
    expect(venue.longitude, 139.6);
    final before = store.exportBackup();
    await tester.tap(find.byKey(const ValueKey('venue-detail-map-select')));
    await tester.pumpAndSettle();
    expect(store.exportBackup(), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('organizer completion prioritizes frequent hosts and selects the name', (tester) async {
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    for (var index = 0; index < 4; index++) {
      await store.saveEvent(GiriEvent(
        id: 'host-$index',
        title: '主催した会',
        kind: EventKind.live,
        meetingType: MeetingType.casual,
        createdAt: DateTime(2026),
        organizer: index < 3 ? '主催A' : '主催B',
      ));
    }
    final controller = TextEditingController();
    String? selected;
    String? changed;
    await showScreen(tester, Scaffold(
      body: PlayerSuggestionField(
        store: store,
        controller: controller,
        fieldKey: const ValueKey('host-completion'),
        organizer: true,
        onChanged: (value) => changed = value,
        onSelected: (value) => selected = value,
      ),
    ));
    await tester.enterText(find.byKey(const ValueKey('host-completion')), '主');
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('主催A')).dy,
      lessThan(tester.getTopLeft(find.text('主催B')).dy),
    );
    await tester.tap(find.text('主催A'));
    await tester.pumpAndSettle();
    expect(controller.text, '主催A');
    expect(changed, '主催A');
    expect(selected, '主催A');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    store.dispose();
  });
}
