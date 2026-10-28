import 'package:flutter/widgets.dart';
import 'package:giristair/app.dart';
import 'package:giristair/models.dart';
import 'package:giristair/storage.dart';
import 'package:giristair/store.dart';

/// Simulator-only entrypoint. It uses the real app, native controls and fonts,
/// with an in-memory document so previewing never reads or changes user data.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = GiriStore(storage: MemoryGiriStorage());
  await store.load();
  await store.saveEvent(
    GiriEvent(
      id: 'parity-preview-event',
      title: '日本語の大喜利会',
      kind: EventKind.live,
      meetingType: MeetingType.casual,
      createdAt: DateTime(2026, 10, 28),
      eventDate: DateTime(2026, 10, 28),
      venue: '日本語の会場',
      organizer: '主催者',
      participants: const ['参加者の名前', '大喜利プレイヤー'],
    ),
  );
  const tab = int.fromEnvironment('PARITY_TAB', defaultValue: 0);
  runApp(GiriStairApp(store: store, initialTab: tab));
}
