const Object _unchanged = Object();

enum EventKind { live, online }

enum MeetingType { tournament, casual }

enum EventStatus { planned, attended, canceled }

enum NoteKind { answers, prompts, free }

/// A player's participation in a live or online meeting.
class GiriEvent {
  GiriEvent({
    required this.id,
    required this.title,
    required this.kind,
    required this.meetingType,
    required this.createdAt,
    this.organizer = '',
    this.venue = '',
    List<String> participants = const [],
    this.eventDate,
    this.startsAt,
    this.endsAt,
    this.submissionStart,
    this.submissionEnd,
    this.votingStart,
    this.votingEnd,
    this.siteUrl = '',
    this.memo = '',
    this.resultText = '',
    this.placement,
    this.status = EventStatus.planned,
  }) : participants = List.unmodifiable(participants);

  final String id;
  final String title;
  final EventKind kind;
  final MeetingType meetingType;
  final DateTime createdAt;
  final String organizer;
  final String venue;
  final List<String> participants;

  /// The calendar date of a live meeting, even if its time is still unknown.
  final DateTime? eventDate;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? submissionStart;
  final DateTime? submissionEnd;
  final DateTime? votingStart;
  final DateTime? votingEnd;
  final String siteUrl;
  final String memo;
  final String resultText;
  final int? placement;
  final EventStatus status;

  /// Incomplete periods do not claim that a deadline is currently open.
  /// The start is inclusive and the end is exclusive.
  bool isSubmissionOpen(DateTime now) {
    final start = submissionStart;
    final end = submissionEnd;
    return kind == EventKind.online &&
        status != EventStatus.canceled &&
        start != null &&
        end != null &&
        !now.isBefore(start) &&
        now.isBefore(end);
  }

  GiriEvent copyWith({
    String? id,
    String? title,
    EventKind? kind,
    MeetingType? meetingType,
    DateTime? createdAt,
    String? organizer,
    String? venue,
    List<String>? participants,
    Object? eventDate = _unchanged,
    Object? startsAt = _unchanged,
    Object? endsAt = _unchanged,
    Object? submissionStart = _unchanged,
    Object? submissionEnd = _unchanged,
    Object? votingStart = _unchanged,
    Object? votingEnd = _unchanged,
    String? siteUrl,
    String? memo,
    String? resultText,
    Object? placement = _unchanged,
    EventStatus? status,
  }) {
    return GiriEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      meetingType: meetingType ?? this.meetingType,
      createdAt: createdAt ?? this.createdAt,
      organizer: organizer ?? this.organizer,
      venue: venue ?? this.venue,
      participants: participants ?? this.participants,
      eventDate: identical(eventDate, _unchanged)
          ? this.eventDate
          : eventDate as DateTime?,
      startsAt: identical(startsAt, _unchanged)
          ? this.startsAt
          : startsAt as DateTime?,
      endsAt: identical(endsAt, _unchanged) ? this.endsAt : endsAt as DateTime?,
      submissionStart: identical(submissionStart, _unchanged)
          ? this.submissionStart
          : submissionStart as DateTime?,
      submissionEnd: identical(submissionEnd, _unchanged)
          ? this.submissionEnd
          : submissionEnd as DateTime?,
      votingStart: identical(votingStart, _unchanged)
          ? this.votingStart
          : votingStart as DateTime?,
      votingEnd: identical(votingEnd, _unchanged)
          ? this.votingEnd
          : votingEnd as DateTime?,
      siteUrl: siteUrl ?? this.siteUrl,
      memo: memo ?? this.memo,
      resultText: resultText ?? this.resultText,
      placement: identical(placement, _unchanged)
          ? this.placement
          : placement as int?,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'meetingType': meetingType.name,
    'createdAt': _encodeDate(createdAt),
    'organizer': organizer,
    'venue': venue,
    'participants': participants,
    'eventDate': _encodeCalendarDate(eventDate),
    'startsAt': _encodeDate(startsAt),
    'endsAt': _encodeDate(endsAt),
    'submissionStart': _encodeDate(submissionStart),
    'submissionEnd': _encodeDate(submissionEnd),
    'votingStart': _encodeDate(votingStart),
    'votingEnd': _encodeDate(votingEnd),
    'siteUrl': siteUrl,
    'memo': memo,
    'resultText': resultText,
    'placement': placement,
    'status': status.name,
  };

  factory GiriEvent.fromJson(Map<String, dynamic> json) => GiriEvent(
    id: _requiredString(json, 'id'),
    title: _requiredString(json, 'title'),
    kind: _enumValue(EventKind.values, json['kind'], 'kind'),
    meetingType: _enumValue(
      MeetingType.values,
      json['meetingType'],
      'meetingType',
    ),
    createdAt: _requiredDate(json, 'createdAt'),
    organizer: _optionalString(json, 'organizer'),
    venue: _optionalString(json, 'venue'),
    participants: _stringList(json, 'participants'),
    eventDate: _optionalCalendarDate(json, 'eventDate'),
    startsAt: _optionalDate(json, 'startsAt'),
    endsAt: _optionalDate(json, 'endsAt'),
    submissionStart: _optionalDate(json, 'submissionStart'),
    submissionEnd: _optionalDate(json, 'submissionEnd'),
    votingStart: _optionalDate(json, 'votingStart'),
    votingEnd: _optionalDate(json, 'votingEnd'),
    siteUrl: _optionalString(json, 'siteUrl'),
    memo: _optionalString(json, 'memo'),
    resultText: _optionalString(json, 'resultText'),
    placement: _optionalInt(json, 'placement'),
    status: json['status'] == null
        ? EventStatus.planned
        : _enumValue(EventStatus.values, json['status'], 'status'),
  );
}

/// A note can be kept independently, or linked to one registered meeting.
class ThoughtNote {
  const ThoughtNote({
    required this.id,
    required this.title,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.body = '',
    this.eventId,
  });

  final String id;
  final String title;
  final NoteKind kind;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String body;
  final String? eventId;

  ThoughtNote copyWith({
    String? id,
    String? title,
    NoteKind? kind,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? body,
    Object? eventId = _unchanged,
  }) => ThoughtNote(
    id: id ?? this.id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    body: body ?? this.body,
    eventId: identical(eventId, _unchanged) ? this.eventId : eventId as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'createdAt': _encodeDate(createdAt),
    'updatedAt': _encodeDate(updatedAt),
    'body': body,
    'eventId': eventId,
  };

  factory ThoughtNote.fromJson(Map<String, dynamic> json) {
    final eventId = json['eventId'];
    if (eventId != null && eventId is! String) {
      throw const FormatException('eventId must be a string or null.');
    }
    return ThoughtNote(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      kind: _enumValue(NoteKind.values, json['kind'], 'kind'),
      createdAt: _requiredDate(json, 'createdAt'),
      updatedAt: _requiredDate(json, 'updatedAt'),
      body: _optionalString(json, 'body'),
      eventId: eventId as String?,
    );
  }
}

String? _encodeDate(DateTime? value) => value?.toUtc().toIso8601String();

String? _encodeCalendarDate(DateTime? value) {
  if (value == null) return null;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${two(value.month)}-${two(value.day)}';
}

DateTime? _optionalCalendarDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('$key must be a calendar date (YYYY-MM-DD).');
  }
  final date = DateTime.tryParse(value);
  if (date == null || _encodeCalendarDate(date) != value) {
    throw FormatException('$key must be a valid calendar date.');
  }
  return date;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string.');
  return value;
}

String _optionalString(Map<String, dynamic> json, String key) {
  if (json[key] == null) return '';
  return _requiredString(json, key);
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _optionalDate(json, key);
  if (value == null) throw FormatException('$key is required.');
  return value;
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be an ISO date.');
  final date = DateTime.tryParse(value);
  if (date == null) throw FormatException('$key must be an ISO date.');
  return date.toLocal();
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

List<String> _stringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key must be a list of strings.');
  }
  return value.cast<String>();
}

T _enumValue<T extends Enum>(List<T> values, Object? value, String key) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('Unsupported $key: $value');
}

/// A reusable player profile. Events continue to store names for compatibility.
class GiriPlayer {
  const GiriPlayer({required this.id, required this.name, this.furigana = ''});

  final String id;
  final String name;
  final String furigana;

  GiriPlayer copyWith({String? name, String? furigana}) => GiriPlayer(
    id: id,
    name: name ?? this.name,
    furigana: furigana ?? this.furigana,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'furigana': furigana,
  };

  factory GiriPlayer.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final name = _requiredString(json, 'name');
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw const FormatException('A player needs an ID and name.');
    }
    return GiriPlayer(
      id: id,
      name: name,
      furigana: _optionalString(json, 'furigana'),
    );
  }
}

class AppPreferences {
  const AppPreferences({
    this.theme = 'light',
    this.notificationsEnabled = false,
    this.reminderMinutes = 60,
    this.reminderHour = 9,
    this.reminderMinute = 0,
  });

  final String theme;
  final bool notificationsEnabled;
  final int reminderMinutes;
  final int reminderHour;
  final int reminderMinute;

  AppPreferences copyWith({
    String? theme,
    bool? notificationsEnabled,
    int? reminderMinutes,
    int? reminderHour,
    int? reminderMinute,
  }) => AppPreferences(
    theme: theme ?? this.theme,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
  );

  Map<String, dynamic> toJson() => {
    'theme': theme,
    'notificationsEnabled': notificationsEnabled,
    'reminderMinutes': reminderMinutes,
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
  };

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    final theme = json['theme'] ?? 'light';
    final enabled = json['notificationsEnabled'] ?? false;
    final minutes = json['reminderMinutes'] ?? 60;
    final hour = json['reminderHour'] ?? 9;
    final minute = json['reminderMinute'] ?? 0;
    if (theme is! String ||
        !const ['system', 'light', 'dark', 'stair'].contains(theme) ||
        enabled is! bool ||
        minutes is! int || minutes < 0 || minutes > 10080 ||
        hour is! int || hour < 0 || hour > 23 ||
        minute is! int || minute < 0 || minute > 59) {
      throw const FormatException('Invalid application preferences.');
    }
    return AppPreferences(
      theme: theme,
      notificationsEnabled: enabled,
      reminderMinutes: minutes,
      reminderHour: hour,
      reminderMinute: minute,
    );
  }
}
