import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:giristair/app.dart';
import 'package:giristair/models.dart';
import 'package:giristair/screens/profile_setup.dart';
import 'package:giristair/screens/result_entry.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/ui/stair_tab_bar.dart';
import 'package:giristair/ui/stair_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _completed = AppPreferences(selfName: '本人', onboardingCompleted: true);

class _CycleStorage extends MemoryGiriStorage {
  bool failWrites = false;

  @override
  Future<void> write(String contents) async {
    if (failWrites) throw const FileSystemException('Cycle write failed');
    await super.write(contents);
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

GiriEvent _tournament(String id, {bool ended = true}) {
  final now = DateTime.now();
  final start = now.subtract(const Duration(days: 2));
  return GiriEvent(
    id: id,
    title: '結果確認$id',
    kind: EventKind.live,
    meetingType: MeetingType.tournament,
    createdAt: start,
    eventDate: DateTime(start.year, start.month, start.day),
    startsAt: start,
    endsAt: ended
        ? now.subtract(const Duration(days: 1))
        : now.add(const Duration(days: 1)),
    participants: const ['本人'],
  );
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'GiriStair',
      packageName: 'com.livestair.giristair',
      version: '0.3.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('first launch saves the self profile before exposing five tabs', (
    tester,
  ) async {
    _phone(tester);
    final storage = MemoryGiriStorage();
    final store = GiriStore(storage: storage);
    await tester.pumpWidget(GiriStairApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(SelfProfileScreen), findsOneWidget);
    expect(find.byType(StairTabBar), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('self-name')), '本人');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('self-name-save')));
    await tester.pumpAndSettle();
    expect(find.byType(SelfProfileScreen), findsNothing);
    expect(find.byType(StairTabBar), findsOneWidget);
    expect(store.preferences.onboardingCompleted, isTrue);
    expect(store.players.single.name, '本人');

    await tester.pumpWidget(const SizedBox());
    store.dispose();
    final reopened = GiriStore(storage: storage);
    await tester.pumpWidget(GiriStairApp(store: reopened));
    await tester.pumpAndSettle();
    expect(find.byType(SelfProfileScreen), findsNothing);
    expect(find.byType(StairTabBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    reopened.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs and resuming retain the registration draft', (
    tester,
  ) async {
    _phone(tester);
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.savePreferences(_completed);
    await tester.pumpWidget(GiriStairApp(store: store, initialTab: 0));
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('event-title'));
    await tester.enterText(title, '編集中の大会');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final navigation = find.byType(StairTabBar);
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('思考')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<StairTabBar>(navigation).currentIndex, 3);
    await _resume(tester);
    expect(tester.widget<StairTabBar>(navigation).currentIndex, 3);
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('登録')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(title).controller!.text, '編集中の大会');
    expect(store.events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning after a live tournament prompts once per session', (
    tester,
  ) async {
    _phone(tester);
    final store = GiriStore(storage: MemoryGiriStorage());
    await store.load();
    await store.savePreferences(_completed);
    final event = _tournament('after-return', ended: false);
    await store.saveEvent(event);
    await tester.pumpWidget(GiriStairApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('大会の結果を残しますか？'), findsNothing);
    await store.saveEvent(
      event.copyWith(endsAt: DateTime.now().subtract(const Duration(hours: 1))),
    );
    await tester.pumpAndSettle();
    expect(find.text('大会の結果を残しますか？'), findsNothing);
    await _resume(tester);
    expect(find.text('大会の結果を残しますか？'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StairCupertinoAlertDialog),
        matching: find.text(event.title),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('後で'));
    await tester.pumpAndSettle();
    await _resume(tester);
    await _resume(tester);
    expect(find.text('大会の結果を残しますか？'), findsNothing);
    expect(store.events.single.hasFinalResult, isFalse);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saving a final result suppresses the prompt on the next launch',
    (tester) async {
      _phone(tester);
      final storage = MemoryGiriStorage();
      final store = GiriStore(storage: storage);
      await store.load();
      await store.savePreferences(_completed);
      await store.saveEvent(_tournament('save-result'));
      await tester.pumpWidget(GiriStairApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('大会の結果を残しますか？'), findsOneWidget);
      await tester.tap(find.text('入力する'));
      await tester.pumpAndSettle();
      expect(find.byType(ResultEntryScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-final-outcome')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('優勝'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(ResultEntryScreen), findsNothing);
      expect(
        store.events.single.tournamentResult!.outcome,
        TournamentOutcome.champion,
      );
      expect(store.events.single.placement, 1);
      await _resume(tester);
      expect(find.text('大会の結果を残しますか？'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      store.dispose();
      final reopened = GiriStore(storage: storage);
      await tester.pumpWidget(GiriStairApp(store: reopened));
      await tester.pumpAndSettle();
      expect(find.text('大会の結果を残しますか？'), findsNothing);
      expect(reopened.events.single.hasFinalResult, isTrue);
      await tester.pumpWidget(const SizedBox());
      reopened.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'optional site-cycle write failure keeps readable saved records',
    (tester) async {
      _phone(tester);
      final storage = _CycleStorage();
      final store = GiriStore(storage: storage);
      await store.load();
      await store.savePreferences(_completed);
      await store.saveEvent(
        GiriEvent(
          id: 'readable',
          title: '読み出せる記録',
          kind: EventKind.live,
          meetingType: MeetingType.casual,
          createdAt: DateTime.now(),
          eventDate: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      await store.saveOnlineSite(
        const OnlineSite(
          id: 'site',
          name: '毎週のサイト',
          recurrence: SiteRecurrence.weekly,
        ),
      );
      final savedContents = storage.contents;
      storage.failWrites = true;
      await tester.pumpWidget(GiriStairApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byType(StairTabBar), findsOneWidget);
      expect(find.text('読み出せる記録'), findsAtLeastNWidgets(1));
      expect(find.text('記録を読み込めませんでした'), findsNothing);
      expect(find.text('周期を更新できませんでした。保存済みの記録は表示しています。'), findsOneWidget);
      expect(storage.contents, savedContents);
      expect(store.events.single.id, 'readable');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
