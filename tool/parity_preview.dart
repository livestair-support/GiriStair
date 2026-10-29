import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:giristair/app.dart';
import 'package:giristair/models.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';
import 'package:giristair/screens/event_list.dart';
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
    screen = options?['screen'] as String? ?? screen;
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
  const tab = int.fromEnvironment('PARITY_TAB', defaultValue: 0);
  final navigator = GlobalKey<NavigatorState>();
  runApp(GiriStairApp(store: store, initialTab:screen=='calendar'?1:screen=='thinking'?3:tab,navigatorKey:navigator));
  if(screen=='detail'||screen=='venue') {
    unawaited(()async{
      for(var attempt=0;attempt<100&&navigator.currentState==null;attempt++) {
        await Future<void>.delayed(const Duration(milliseconds:100));
      }
      await Future<void>.delayed(const Duration(seconds:2));
      navigator.currentState?.push<void>(CupertinoPageRoute(builder:(_)=>screen=='venue'?VenueDetailScreen(store:store,venueId:'preview-venue'):EventDetailScreen(store:store,eventId:'parity-preview-event')));
    }());
  }
}
