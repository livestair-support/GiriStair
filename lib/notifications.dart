import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'models.dart';
import 'store.dart';

/// One local reminder. Kept separate from the platform bridge so that date,
/// status, cancellation and the iOS pending-notification limit can be tested.
@immutable
class GiriReminder {
  const GiriReminder({
    required this.key,
    required this.eventId,
    required this.title,
    required this.body,
    required this.when,
  });

  final String key;
  final String eventId;
  final String title;
  final String body;
  final DateTime when;
}

/// Only explicitly planned meetings produce reminders. A participant list is
/// never treated as a result, and a calendar-only meeting is reminded at the
/// chosen local morning time rather than at midnight.
List<GiriReminder> planGiriReminders({
  required Iterable<GiriEvent> events,
  required AppPreferences preferences,
  required DateTime now,
  int limit = 64,
}) {
  if (!preferences.notificationsEnabled || limit <= 0) return const [];
  final reminders = <GiriReminder>[];
  final lead = Duration(minutes: preferences.reminderMinutes);
  void add(GiriEvent event, String kind, String body, DateTime when) {
    if (!when.isAfter(now)) return;
    reminders.add(
      GiriReminder(
        key: '${event.id}:$kind',
        eventId: event.id,
        title: event.title,
        body: body,
        when: when,
      ),
    );
  }

  for (final event in events) {
    if (event.status != EventStatus.planned) continue;
    if (event.kind == EventKind.live) {
      final start = event.startsAt;
      if (start != null) {
        add(
          event,
          'start',
          preferences.reminderMinutes == 0
              ? '開始時刻です${event.venue.isEmpty ? '' : '・${event.venue}'}'
              : '開始${preferences.reminderMinutes}分前です'
                    '${event.venue.isEmpty ? '' : '・${event.venue}'}',
          start.subtract(lead),
        );
      } else {
        final day = event.eventDate;
        if (day != null) {
          add(
            event,
            'day',
            '今日は参加予定の日です'
                '${event.venue.isEmpty ? '' : '・${event.venue}'}',
            DateTime(
              day.year,
              day.month,
              day.day,
              preferences.reminderHour,
              preferences.reminderMinute,
            ),
          );
        }
      }
    } else {
      for (final entry in [
        ('submission', '投稿', event.submissionEnd),
        ('voting', '投票', event.votingEnd),
      ]) {
        final deadline = entry.$3;
        if (deadline == null) continue;
        add(
          event,
          entry.$1,
          preferences.reminderMinutes == 0
              ? '${entry.$2}の締切です'
              : '${entry.$2}締切の${preferences.reminderMinutes}分前です',
          deadline.subtract(lead),
        );
      }
    }
  }
  reminders.sort((a, b) {
    final time = a.when.compareTo(b.when);
    return time == 0 ? a.key.compareTo(b.key) : time;
  });
  // iOS keeps at most 64 pending local notifications. Both platforms use the
  // same nearest-first limit so settings have predictable behavior.
  return List.unmodifiable(reminders.take(limit));
}

class GiriNotifications {
  GiriNotifications._();

  static final instance = GiriNotifications._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<String?> error = ValueNotifier(null);
  Future<void> _pending = Future.value();
  bool _initialized = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> _initialize() async {
    if (_initialized) return;
    timezone_data.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  /// Called only when the person enables notifications in Settings. Merely
  /// launching the app never opens the operating system's permission prompt.
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    try {
      await _initialize();
      final granted = defaultTargetPlatform == TargetPlatform.iOS
          ? await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: false, sound: true)
          : await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission();
      if (granted == true) error.value = null;
      return granted == true;
    } on MissingPluginException {
      error.value = 'この環境では通知を利用できません。';
    } on PlatformException {
      error.value = '通知の許可を確認できませんでした。端末の設定を確認してください。';
    } catch (_) {
      error.value = '通知の準備ができませんでした。アプリを開き直してください。';
    }
    return false;
  }

  /// Serializes replacement schedules so a save, deletion, restore or settings
  /// change cannot leave a stale reminder behind after a later sync completes.
  /// Platform failures are surfaced in Settings and never prevent data saving.
  Future<void> sync(GiriStore store) {
    final result = _pending.then((_) async {
      if (!_supported || !store.loaded) return;
      try {
        await _initialize();
        await _plugin.cancelAll();
        if (!store.preferences.notificationsEnabled) {
          error.value = null;
          return;
        }
        // Refresh after travel or a system time-zone change. Calendar-only
        // meetings always follow the device's current local calendar.
        final zone = await FlutterTimezone.getLocalTimezone();
        timezone.setLocalLocation(timezone.getLocation(zone.identifier));
        final reminders = planGiriReminders(
          events: store.events,
          preferences: store.preferences,
          now: DateTime.now(),
        );
        final ids = <int>{};
        for (final reminder in reminders) {
          var id = _notificationId(reminder.key);
          while (!ids.add(id)) {
            id = (id + 1) & 0x7fffffff;
          }
          await _plugin.zonedSchedule(
            id,
            reminder.title,
            reminder.body,
            timezone.TZDateTime.from(reminder.when, timezone.local),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'giristair_reminders',
                '予定・締切',
                channelDescription: '参加予定の開始時刻と投稿・投票の締切をお知らせします。',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentSound: true,
                presentBadge: false,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: reminder.eventId,
          );
        }
        error.value = null;
      } on MissingPluginException {
        error.value = store.preferences.notificationsEnabled
            ? 'この環境では通知を利用できません。'
            : null;
      } catch (_) {
        error.value = '通知を予約できませんでした。端末の通知設定を確認し、アプリを開き直してください。';
      }
    });
    // sync handles native failures itself. Keep the queue usable even if a
    // disposed store or an unexpected callback fails between sync requests.
    _pending = result.catchError((Object _) {});
    return _pending;
  }

  int _notificationId(String key) {
    var hash = 0x811c9dc5;
    for (final value in key.codeUnits) {
      hash = ((hash ^ value) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
