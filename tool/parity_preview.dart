import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:giristair/app.dart';
import 'package:giristair/models.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/screens/event_detail.dart';
import 'package:giristair/ui/stair_tab_bar.dart';
import 'package:giristair/screens/venues.dart';

/// Simulator-only entrypoint. It uses the real app, native controls and fonts,
/// with an in-memory document so previewing never reads or changes user data.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = GiriStore(storage: MemoryGiriStorage());
  await store.load();
  var screen = 'registration';
  try {
    final options = await const MethodChannel('giristair/native-controls').invokeMapMethod<String,dynamic>('previewOptions');
    final selected = options?['screen'];
    if (selected is! String || !const {
      'registration', 'calendar', 'thinking', 'detail', 'venue',
    }.contains(selected)) {
      throw StateError('The iPhone preview screen is missing or unsupported.');
    }
    screen = selected;
  } on MissingPluginException {
    throw StateError('The iPhone preview requires DEBUG in the Runner target.');
  }
  await store.savePreferences(AppPreferences(
    selfName: '確認用プレイヤー',
    onboardingCompleted: true,
    listCurrentMode: screen == 'calendar',
  ));
  final now = DateTime.now();
  await store.saveVenue(const GiriVenue(id:'preview-venue',name:'日本語の会場',prefecture:'東京都',latitude:35.6812,longitude:139.7671,mapAddress:'東京都千代田区丸の内'));
  await store.saveEvent(
    GiriEvent(
      id: 'parity-preview-event',
      title: '日本語の大喜利会',
      kind: EventKind.live,
      meetingType: MeetingType.casual,
      createdAt: DateTime(2026, 10, 28),
      eventDate: DateTime(now.year, now.month, now.day),
      venue: '日本語の会場',
      venueId: 'preview-venue',
      organizer: '主催者',
      participants: const ['参加者の名前', '大喜利プレイヤー'],
    ),
  );
  await store.saveOnlineSite(const OnlineSite(id:'preview-site',name:'日本語の大喜利サイト',url:'https://example.com',affiliation:'一部',block:'お題A'));
  final cycle = await store.createSiteCycle('preview-site',submissionStart:DateTime(now.year,now.month,now.day-1,22));
  await store.saveNote(ThoughtNote(id:'preview-prompt',title:'こんな図書館はいやだ',kind:NoteKind.answers,createdAt:now,updatedAt:now,eventId:cycle.id,roundId:cycle.rounds.first.id,prompt:'こんな図書館はいやだ',answers:const['本を返すと拍手が起きる','静かに笑うための席がある']));
  final expectedTab = screen == 'calendar' ? 1 : screen == 'thinking' ? 3 : 0;
  final navigator = GlobalKey<NavigatorState>();
  runApp(GiriStairApp(
    store: store,
    initialTab: expectedTab,
    navigatorKey: navigator,
  ));

  final elapsed = Stopwatch()..start();
  await _waitForUi(
    () => _homeIsMounted(expectedTab),
    elapsed,
    'the five-tab home at index $expectedTab',
  );
  await _renderFrame(elapsed);

  if (screen == 'detail' || screen == 'venue') {
    final state = navigator.currentState;
    if (state == null || !state.mounted) {
      throw StateError('The ready home has no mounted navigator.');
    }
    final route = CupertinoPageRoute<void>(
      builder: (_) => screen == 'venue'
          ? VenueDetailScreen(store: store, venueId: 'preview-venue')
          : EventDetailScreen(store: store, eventId: 'parity-preview-event'),
    );
    unawaited(state.push<void>(route));
    await _waitForUi(
      () => _elements().any((element) {
        final target = screen == 'venue'
            ? element.widget is VenueDetailScreen
            : element.widget is EventDetailScreen;
        return target && ModalRoute.of(element)?.isCurrent == true;
      }),
      elapsed,
      'the current $screen page',
    );
    await _waitForUi(
      () => route.isCurrent &&
          route.animation?.status == AnimationStatus.completed,
      elapsed,
      'the $screen route transition',
    );
  }

  await _renderFrame(elapsed);
  await Future<void>.delayed(const Duration(seconds: 2));
  await _renderFrame(elapsed);
  await const MethodChannel('giristair/native-controls').invokeMethod<void>(
    'previewReady',
    {'screen': screen},
  );
}

const _readinessTimeout = Duration(seconds: 120);

Iterable<Element> _elements() sync* {
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return;
  final pending = <Element>[root];
  while (pending.isNotEmpty) {
    final element = pending.removeLast();
    if (!element.mounted) continue;
    yield element;
    element.visitChildren(pending.add);
  }
}

bool _homeIsMounted(int expectedTab) {
  var tabBar = false;
  var selectedStack = false;
  for (final element in _elements()) {
    final widget = element.widget;
    if (widget is StairTabBar) tabBar = true;
    if (widget is IndexedStack &&
        widget.children.length == 5 &&
        widget.index == expectedTab) {
      selectedStack = true;
    }
  }
  return tabBar && selectedStack;
}

Duration _remaining(Stopwatch elapsed, String target) {
  final remaining = _readinessTimeout - elapsed.elapsed;
  if (remaining <= Duration.zero) {
    throw TimeoutException('iPhone preview did not render $target.',
        _readinessTimeout);
  }
  return remaining;
}

Future<void> _waitForUi(
  bool Function() ready,
  Stopwatch elapsed,
  String target,
) async {
  while (!ready()) {
    _remaining(elapsed, target);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> _renderFrame(Stopwatch elapsed) =>
    WidgetsBinding.instance.endOfFrame.timeout(
      _remaining(elapsed, 'a completed frame'),
    );
