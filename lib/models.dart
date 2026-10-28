const Object _unchanged = Object();

enum EventKind { live, online }

enum MeetingType { tournament, casual }

enum EventStatus { planned, attended, canceled }

enum NoteKind { answers, prompts, free }

enum TournamentFormat { individual, pair, team }

enum TournamentOutcome {
  unrecorded,
  champion,
  runnerUp,
  placed,
  eliminated,
  advanced,
  other,
}

/// Each round has its own posting and voting windows. IDs survive renaming.
class EventRound {
  const EventRound({
    required this.id,
    required this.name,
    this.submissionStart,
    this.submissionEnd,
    this.votingStart,
    this.votingEnd,
  });

  final String id;
  final String name;
  final DateTime? submissionStart;
  final DateTime? submissionEnd;
  final DateTime? votingStart;
  final DateTime? votingEnd;

  bool isSubmissionOpen(DateTime now) =>
      submissionStart != null &&
      submissionEnd != null &&
      !now.isBefore(submissionStart!) &&
      now.isBefore(submissionEnd!);

  EventRound copyWith({
    String? id,
    String? name,
    Object? submissionStart = _unchanged,
    Object? submissionEnd = _unchanged,
    Object? votingStart = _unchanged,
    Object? votingEnd = _unchanged,
  }) => EventRound(
    id: id ?? this.id,
    name: name ?? this.name,
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
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'submissionStart': _encodeDate(submissionStart),
    'submissionEnd': _encodeDate(submissionEnd),
    'votingStart': _encodeDate(votingStart),
    'votingEnd': _encodeDate(votingEnd),
  };

  factory EventRound.fromJson(Map<String, dynamic> json) => EventRound(
    id: _requiredId(json),
    name: _requiredString(json, 'name'),
    submissionStart: _optionalDate(json, 'submissionStart'),
    submissionEnd: _optionalDate(json, 'submissionEnd'),
    votingStart: _optionalDate(json, 'votingStart'),
    votingEnd: _optionalDate(json, 'votingEnd'),
  );
}

/// A result at one stage does not imply the final tournament outcome.
class ResultStage {
  const ResultStage({
    required this.id,
    required this.name,
    this.outcome = TournamentOutcome.unrecorded,
    this.placement,
    this.memo = '',
  });

  final String id;
  final String name;
  final TournamentOutcome outcome;
  final int? placement;
  final String memo;

  ResultStage copyWith({
    String? name,
    TournamentOutcome? outcome,
    Object? placement = _unchanged,
    String? memo,
  }) => ResultStage(
    id: id,
    name: name ?? this.name,
    outcome: outcome ?? this.outcome,
    placement: identical(placement, _unchanged)
        ? this.placement
        : placement as int?,
    memo: memo ?? this.memo,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'outcome': outcome.name,
    'placement': placement,
    'memo': memo,
  };

  factory ResultStage.fromJson(Map<String, dynamic> json) => ResultStage(
    id: _requiredId(json),
    name: _requiredString(json, 'name'),
    outcome: json['outcome'] == null
        ? TournamentOutcome.unrecorded
        : _enumValue(TournamentOutcome.values, json['outcome'], 'outcome'),
    placement: _positiveInt(json, 'placement'),
    memo: _optionalString(json, 'memo'),
  );
}

class TournamentResult {
  TournamentResult({
    this.format = TournamentFormat.individual,
    this.outcome = TournamentOutcome.unrecorded,
    this.teamName = '',
    List<String> members = const [],
    List<ResultStage> stages = const [],
    this.memo = '',
  }) : members = List.unmodifiable(members),
       stages = List.unmodifiable(stages);

  final TournamentFormat format;
  final TournamentOutcome outcome;
  final String teamName;
  final List<String> members;
  final List<ResultStage> stages;
  final String memo;

  bool get hasRecord =>
      outcome != TournamentOutcome.unrecorded ||
      stages.any(
        (stage) =>
            stage.outcome != TournamentOutcome.unrecorded ||
            stage.placement != null ||
            stage.memo.trim().isNotEmpty,
      ) ||
      memo.trim().isNotEmpty;

  TournamentResult copyWith({
    TournamentFormat? format,
    TournamentOutcome? outcome,
    String? teamName,
    List<String>? members,
    List<ResultStage>? stages,
    String? memo,
  }) => TournamentResult(
    format: format ?? this.format,
    outcome: outcome ?? this.outcome,
    teamName: teamName ?? this.teamName,
    members: members ?? this.members,
    stages: stages ?? this.stages,
    memo: memo ?? this.memo,
  );

  Map<String, dynamic> toJson() => {
    'format': format.name,
    'outcome': outcome.name,
    'teamName': teamName,
    'members': members,
    'stages': stages.map((stage) => stage.toJson()).toList(),
    'memo': memo,
  };

  factory TournamentResult.fromJson(Map<String, dynamic> json) =>
      TournamentResult(
        format: json['format'] == null
            ? TournamentFormat.individual
            : _enumValue(TournamentFormat.values, json['format'], 'format'),
        outcome: json['outcome'] == null
            ? TournamentOutcome.unrecorded
            : _enumValue(TournamentOutcome.values, json['outcome'], 'outcome'),
        teamName: _optionalString(json, 'teamName'),
        members: _stringList(json, 'members'),
        stages: _recordList(json, 'stages', ResultStage.fromJson),
        memo: _optionalString(json, 'memo'),
      );
}

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
    List<EventRound> rounds = const [],
    this.tournamentResult,
  }) : participants = List.unmodifiable(participants),
       rounds = List.unmodifiable(rounds);

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
  final List<EventRound> rounds;
  final TournamentResult? tournamentResult;

  /// Old single-window records remain readable and can be edited as a round.
  List<EventRound> get effectiveRounds {
    if (rounds.isNotEmpty) return rounds;
    if (submissionStart == null &&
        submissionEnd == null &&
        votingStart == null &&
        votingEnd == null) {
      return const [];
    }
    return [
      EventRound(
        id: 'legacy',
        name: '投稿・投票',
        submissionStart: submissionStart,
        submissionEnd: submissionEnd,
        votingStart: votingStart,
        votingEnd: votingEnd,
      ),
    ];
  }

  bool get hasRecordedResult =>
      tournamentResult?.hasRecord == true ||
      resultText.trim().isNotEmpty ||
      (placement != null && placement! > 0);

  /// Only an explicit final outcome or numeric final rank is aggregated.
  int? get effectivePlacement {
    switch (tournamentResult?.outcome) {
      case TournamentOutcome.champion:
        return 1;
      case TournamentOutcome.runnerUp:
        return 2;
      case TournamentOutcome.eliminated:
      case TournamentOutcome.advanced:
        return null;
      default:
        return placement != null && placement! > 0 ? placement : null;
    }
  }

  DateTime? nextSubmissionEnd(DateTime now) {
    if (kind != EventKind.online || status == EventStatus.canceled) return null;
    final ends =
        effectiveRounds
            .where((round) => round.isSubmissionOpen(now))
            .map((round) => round.submissionEnd!)
            .toList()
          ..sort();
    return ends.isEmpty ? null : ends.first;
  }

  /// Incomplete periods do not claim that a deadline is currently open.
  /// The start is inclusive and the end is exclusive.
  bool isSubmissionOpen(DateTime now) =>
      kind == EventKind.online &&
      status != EventStatus.canceled &&
      effectiveRounds.any((round) => round.isSubmissionOpen(now));

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
    List<EventRound>? rounds,
    Object? tournamentResult = _unchanged,
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
      rounds: rounds ?? this.rounds,
      tournamentResult: identical(tournamentResult, _unchanged)
          ? this.tournamentResult
          : tournamentResult as TournamentResult?,
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
    'rounds': rounds.map((round) => round.toJson()).toList(),
    'tournamentResult': tournamentResult?.toJson(),
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
    rounds: _recordList(json, 'rounds', EventRound.fromJson),
    tournamentResult: _optionalRecord(
      json,
      'tournamentResult',
      TournamentResult.fromJson,
    ),
    status: json['status'] == null
        ? EventStatus.planned
        : _enumValue(EventStatus.values, json['status'], 'status'),
  );
}

/// A note can be kept independently, or linked to one registered meeting.
class ThoughtNote {
  ThoughtNote({
    required this.id,
    required this.title,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.body = '',
    this.eventId,
    this.roundId,
    this.prompt = '',
    List<String> answers = const [],
    this.used = false,
  }) : answers = List.unmodifiable(answers);

  final String id;
  final String title;
  final NoteKind kind;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String body;
  final String? eventId;
  final String? roundId;
  final String prompt;
  final List<String> answers;
  final bool used;

  ThoughtNote copyWith({
    String? id,
    String? title,
    NoteKind? kind,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? body,
    Object? eventId = _unchanged,
    Object? roundId = _unchanged,
    String? prompt,
    List<String>? answers,
    bool? used,
  }) => ThoughtNote(
    id: id ?? this.id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    body: body ?? this.body,
    eventId: identical(eventId, _unchanged) ? this.eventId : eventId as String?,
    roundId: identical(roundId, _unchanged) ? this.roundId : roundId as String?,
    prompt: prompt ?? this.prompt,
    answers: answers ?? this.answers,
    used: used ?? this.used,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'createdAt': _encodeDate(createdAt),
    'updatedAt': _encodeDate(updatedAt),
    'body': body,
    'eventId': eventId,
    'roundId': roundId,
    'prompt': prompt,
    'answers': answers,
    'used': used,
  };

  factory ThoughtNote.fromJson(Map<String, dynamic> json) {
    final eventId = json['eventId'];
    final roundId = json['roundId'];
    final used = json['used'] ?? false;
    if (roundId != null && roundId is! String) {
      throw const FormatException('roundId must be a string or null.');
    }
    if (used is! bool) throw const FormatException('used must be a boolean.');
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
      roundId: roundId as String?,
      prompt: _optionalString(json, 'prompt'),
      answers: _stringList(json, 'answers'),
      used: used,
    );
  }
}

String _requiredId(Map<String, dynamic> json) {
  final id = _requiredString(json, 'id');
  if (id.trim().isEmpty) throw const FormatException('An ID is required.');
  return id;
}

int? _positiveInt(Map<String, dynamic> json, String key) {
  final value = _optionalInt(json, key);
  if (value != null && value < 1) {
    throw FormatException('$key must be positive.');
  }
  return value;
}

T? _optionalRecord<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) decode,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is! Map<String, dynamic>) throw FormatException('Invalid $key.');
  return decode(value);
}

List<T> _recordList<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) decode,
) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) throw FormatException('Invalid $key list.');
  final records = value.map((item) {
    if (item is! Map<String, dynamic>) {
      throw FormatException('Invalid $key record.');
    }
    return decode(item);
  }).toList();
  // All structured child records have stable IDs, except the outer result.
  final ids = <String>{};
  for (final item in value) {
    final id = (item as Map<String, dynamic>)['id'];
    if (id is String && !ids.add(id)) {
      throw FormatException('Duplicate $key IDs.');
    }
  }
  return records;
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
        minutes is! int ||
        minutes < 0 ||
        minutes > 10080 ||
        hour is! int ||
        hour < 0 ||
        hour > 23 ||
        minute is! int ||
        minute < 0 ||
        minute > 59) {
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
