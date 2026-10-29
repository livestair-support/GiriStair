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
    this.stageId,
    this.promptNumber = 1,
    this.block = '',
    this.submissionEnabled = true,
    this.votingRequired = true,
  });
  final String id;
  final String name;
  final DateTime? submissionStart;
  final DateTime? submissionEnd;
  final DateTime? votingStart;
  final DateTime? votingEnd;
  final String? stageId;
  final int promptNumber;
  final String block;
  final bool submissionEnabled;
  final bool votingRequired;
  EventRound copyWith({
    String? id,
    String? name,
    Object? submissionStart = _unchanged,
    Object? submissionEnd = _unchanged,
    Object? votingStart = _unchanged,
    Object? votingEnd = _unchanged,
    Object? stageId = _unchanged,
    int? promptNumber,
    String? block,
    bool? submissionEnabled,
    bool? votingRequired,
  }) => EventRound(
    id: id ?? this.id,
    name: name ?? this.name,
    submissionStart: identical(submissionStart, _unchanged) ? this.submissionStart : submissionStart as DateTime?,
    submissionEnd: identical(submissionEnd, _unchanged) ? this.submissionEnd : submissionEnd as DateTime?,
    votingStart: identical(votingStart, _unchanged) ? this.votingStart : votingStart as DateTime?,
    votingEnd: identical(votingEnd, _unchanged) ? this.votingEnd : votingEnd as DateTime?,
    stageId: identical(stageId, _unchanged) ? this.stageId : stageId as String?,
    promptNumber: promptNumber ?? this.promptNumber,
    block: block ?? this.block,
    submissionEnabled: submissionEnabled ?? this.submissionEnabled,
    votingRequired: votingRequired ?? this.votingRequired,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'submissionStart': _encodeDate(submissionStart),
    'submissionEnd': _encodeDate(submissionEnd),
    'votingStart': _encodeDate(votingStart),
    'votingEnd': _encodeDate(votingEnd),
    'stageId': stageId,
    'promptNumber': promptNumber,
    'block': block,
    'submissionEnabled': submissionEnabled,
    'votingRequired': votingRequired,
  };
  factory EventRound.fromJson(Map<String, dynamic> json) {
    final result = EventRound(
      id: _requiredId(json),
      name: _requiredString(json, 'name'),
      submissionStart: _optionalDate(json, 'submissionStart'),
      submissionEnd: _optionalDate(json, 'submissionEnd'),
      votingStart: _optionalDate(json, 'votingStart'),
      votingEnd: _optionalDate(json, 'votingEnd'),
      stageId: _nullableString(json, 'stageId'),
      promptNumber: _optionalInt(json, 'promptNumber') ?? 1,
      block: _optionalString(json, 'block'),
      submissionEnabled: _boolValue(json, 'submissionEnabled', true),
      votingRequired: _boolValue(json, 'votingRequired', true),
    );
    if (result.promptNumber < 1) throw const FormatException('Invalid prompt number.');
    return result;
  }

  String get effectiveStageId => stageId ?? id;
  bool isSubmissionOpen(DateTime now) => submissionEnabled && submissionStart != null && submissionEnd != null && !now.isBefore(submissionStart!) && now.isBefore(submissionEnd!);
  bool isVotingOpen(DateTime now) => votingRequired && votingStart != null && votingEnd != null && !now.isBefore(votingStart!) && now.isBefore(votingEnd!);

}

/// A result at one stage does not imply the final tournament outcome.
class ResultStage {
  const ResultStage({
    required this.id,
    required this.name,
    this.outcome = TournamentOutcome.unrecorded,
    this.placement,
    this.memo = '',
    this.roundId,
    this.stageId,
    this.teamPlacement,
    this.individualPlacement,
    this.voterCount,
    this.points,
    this.maxPointsPerVoter = 1,
  });
  final String id;
  final String name;
  final TournamentOutcome outcome;
  final int? placement;
  final String memo;
  final String? roundId;
  final String? stageId;
  final int? teamPlacement;
  final int? individualPlacement;
  final int? voterCount;
  final double? points;
  final int maxPointsPerVoter;
  ResultStage copyWith({
    String? name,
    TournamentOutcome? outcome,
    Object? placement = _unchanged,
    String? memo,
    Object? roundId = _unchanged,
    Object? stageId = _unchanged,
    Object? teamPlacement = _unchanged,
    Object? individualPlacement = _unchanged,
    Object? voterCount = _unchanged,
    Object? points = _unchanged,
    int? maxPointsPerVoter,
  }) => ResultStage(
    id: id,
    name: name ?? this.name,
    outcome: outcome ?? this.outcome,
    placement: identical(placement, _unchanged) ? this.placement : placement as int?,
    memo: memo ?? this.memo,
    roundId: identical(roundId, _unchanged) ? this.roundId : roundId as String?,
    stageId: identical(stageId, _unchanged) ? this.stageId : stageId as String?,
    teamPlacement: identical(teamPlacement, _unchanged) ? this.teamPlacement : teamPlacement as int?,
    individualPlacement: identical(individualPlacement, _unchanged) ? this.individualPlacement : individualPlacement as int?,
    voterCount: identical(voterCount, _unchanged) ? this.voterCount : voterCount as int?,
    points: identical(points, _unchanged) ? this.points : (points as num?)?.toDouble(),
    maxPointsPerVoter: maxPointsPerVoter ?? this.maxPointsPerVoter,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'outcome': outcome.name,
    'placement': placement,
    'memo': memo,
    'roundId': roundId,
    'stageId': stageId,
    'teamPlacement': teamPlacement,
    'individualPlacement': individualPlacement,
    'voterCount': voterCount,
    'points': points,
    'maxPointsPerVoter': maxPointsPerVoter,
  };
  factory ResultStage.fromJson(Map<String, dynamic> json) {
    final result = ResultStage(
      id: _requiredId(json),
      name: _requiredString(json, 'name'),
      outcome: json['outcome'] == null ? TournamentOutcome.unrecorded : _enumValue(TournamentOutcome.values, json['outcome'], 'outcome'),
      placement: _positiveInt(json, 'placement'),
      memo: _optionalString(json, 'memo'),
      roundId: _nullableString(json, 'roundId'),
      stageId: _nullableString(json, 'stageId'),
      teamPlacement: _positiveInt(json, 'teamPlacement'),
      individualPlacement: _positiveInt(json, 'individualPlacement'),
      voterCount: _optionalInt(json, 'voterCount'),
      points: _nonnegativeNumber(json, 'points'),
      maxPointsPerVoter: _optionalInt(json, 'maxPointsPerVoter') ?? 1,
    );
    if ((result.voterCount != null && result.voterCount! < 0) || result.maxPointsPerVoter < 1) throw const FormatException('Invalid scoring denominator.');
    return result;
  }

  double? get voteRate => voterCount != null && voterCount! > 0 &&
      maxPointsPerVoter > 0 && points != null && points!.isFinite && points! >= 0
      ? points! * 100 / (voterCount! * maxPointsPerVoter)
      : null;
  bool get hasRecord => outcome != TournamentOutcome.unrecorded ||
      placement != null || teamPlacement != null || individualPlacement != null ||
      voterCount != null || points != null || maxPointsPerVoter != 1 ||
      memo.trim().isNotEmpty;

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

  bool get hasRecord => outcome != TournamentOutcome.unrecorded || stages.any((stage) => stage.hasRecord) || memo.trim().isNotEmpty;

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
    this.onlineSiteId,
    this.cycleKey,
    this.affiliation = '',
    this.block = '',
    List<GiriTeam> teams = const [],
    this.teamSize,
    this.myTeamId,
    this.tournamentFormat = TournamentFormat.individual,
    this.venueId,
    List<TournamentStanding> standings = const [],
    this.isParticipating = true,

  }) : participants = List.unmodifiable(participants),
       rounds = List.unmodifiable(rounds),
       teams = List.unmodifiable(teams),
       standings = List.unmodifiable(standings);

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
  final String? onlineSiteId;
  final String? cycleKey;
  final String affiliation;
  final String block;
  final List<GiriTeam> teams;
  final int? teamSize;
  final String? myTeamId;
  final TournamentFormat tournamentFormat;
  final String? venueId;
  final List<TournamentStanding> standings;
  final bool isParticipating;

  bool isHostedBy(String name) => name.trim().isNotEmpty && organizer.trim().toLowerCase() == name.trim().toLowerCase();
  bool get hasFinalResult => (tournamentResult != null && tournamentResult!.outcome != TournamentOutcome.unrecorded && tournamentResult!.outcome != TournamentOutcome.advanced) || (placement != null && placement! > 0) || resultText.trim().isNotEmpty;


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
    if (kind != EventKind.online || !isParticipating || status == EventStatus.canceled) return null;
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
      isParticipating &&
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
    Object? onlineSiteId = _unchanged,
    Object? cycleKey = _unchanged,
    String? affiliation,
    String? block,
    List<GiriTeam>? teams,
    Object? teamSize = _unchanged,
    Object? myTeamId = _unchanged,
    TournamentFormat? tournamentFormat,
    Object? venueId = _unchanged,
    List<TournamentStanding>? standings,
    bool? isParticipating,

  }) {
    return GiriEvent(
      id: id ?? this.id,
      onlineSiteId: identical(onlineSiteId, _unchanged) ? this.onlineSiteId : onlineSiteId as String?,
      cycleKey: identical(cycleKey, _unchanged) ? this.cycleKey : cycleKey as String?,
      affiliation: affiliation ?? this.affiliation,
      block: block ?? this.block,
      teams: teams ?? this.teams,
      teamSize: identical(teamSize, _unchanged) ? this.teamSize : teamSize as int?,
      myTeamId: identical(myTeamId, _unchanged) ? this.myTeamId : myTeamId as String?,
      tournamentFormat: tournamentFormat ?? this.tournamentFormat,
      venueId: identical(venueId, _unchanged) ? this.venueId : venueId as String?,
      standings: standings ?? this.standings,
      isParticipating: isParticipating ?? this.isParticipating,

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
    'onlineSiteId': onlineSiteId,
    'cycleKey': cycleKey,
    'affiliation': affiliation,
    'block': block,
    'teams': teams.map((item) => item.toJson()).toList(),
    'teamSize': teamSize,
    'myTeamId': myTeamId,
    'tournamentFormat': tournamentFormat.name,
    'venueId': venueId,
    'standings': standings.map((item) => item.toJson()).toList(),
    'isParticipating': isParticipating,

  };

  factory GiriEvent.fromJson(Map<String, dynamic> json) => _checkedEvent(GiriEvent(
    id: _requiredId(json),
    onlineSiteId: _nullableString(json, 'onlineSiteId'),
    cycleKey: _nullableString(json, 'cycleKey'),
    affiliation: _optionalString(json, 'affiliation'),
    block: _optionalString(json, 'block'),
    teams: _recordList(json, 'teams', GiriTeam.fromJson),
    teamSize: _positiveInt(json, 'teamSize'),
    myTeamId: _nullableString(json, 'myTeamId'),
    tournamentFormat: json['tournamentFormat'] == null ? (_optionalRecord(json, 'tournamentResult', TournamentResult.fromJson)?.format ?? TournamentFormat.individual) : _enumValue(TournamentFormat.values, json['tournamentFormat'], 'tournamentFormat'),
    venueId: _nullableString(json, 'venueId'),
    standings: _recordList(json, 'standings', TournamentStanding.fromJson),
    isParticipating: _boolValue(json, 'isParticipating', true),

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
  ));
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
    this.imageDataBase64 = '',
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
  final String imageDataBase64;

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
    String? imageDataBase64,
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
    imageDataBase64: imageDataBase64 ?? this.imageDataBase64,
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
    'imageDataBase64': imageDataBase64,
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
      id: _requiredId(json),
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
      imageDataBase64: _optionalString(json, 'imageDataBase64'),
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
  const GiriPlayer({
    required this.id,
    required this.name,
    this.furigana = '',
    this.region = '',
    this.iconDataBase64 = '',
    this.twitterUrl = '',
    this.memo = '',
  });
  final String id;
  final String name;
  final String furigana;
  final String region;
  final String iconDataBase64;
  final String twitterUrl;
  final String memo;
  GiriPlayer copyWith({
    String? id,
    String? name,
    String? furigana,
    String? region,
    String? iconDataBase64,
    String? twitterUrl,
    String? memo,
  }) => GiriPlayer(
    id: id ?? this.id,
    name: name ?? this.name,
    furigana: furigana ?? this.furigana,
    region: region ?? this.region,
    iconDataBase64: iconDataBase64 ?? this.iconDataBase64,
    twitterUrl: twitterUrl ?? this.twitterUrl,
    memo: memo ?? this.memo,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'furigana': furigana,
    'region': region,
    'iconDataBase64': iconDataBase64,
    'twitterUrl': twitterUrl,
    'memo': memo,
  };
  factory GiriPlayer.fromJson(Map<String, dynamic> json) {
    final result = GiriPlayer(
      id: _requiredId(json),
      name: _requiredString(json, 'name'),
      furigana: _optionalString(json, 'furigana'),
      region: _optionalString(json, 'region'),
      iconDataBase64: _optionalString(json, 'iconDataBase64'),
      twitterUrl: _optionalString(json, 'twitterUrl'),
      memo: _optionalString(json, 'memo'),
    );
    if (result.name.trim().isEmpty) throw const FormatException('A player needs a name.');
    return result;
  }

}

class AppPreferences {
  const AppPreferences({
    this.theme = 'light',
    this.notificationsEnabled = false,
    this.reminderMinutes = 60,
    this.reminderHour = 9,
    this.reminderMinute = 0,
    this.selfName = '',
    this.onboardingCompleted = false,
    this.listCurrentMode = false,
    this.submissionDays = 7,
    this.votingDays = 7,
    this.submissionStartDayOffset = -1,
    this.submissionStartHour = 22,
    this.submissionStartMinute = 0,
    this.playerIconMode = 'auto',
  });
  final String theme;
  final bool notificationsEnabled;
  final int reminderMinutes;
  final int reminderHour;
  final int reminderMinute;
  final String selfName;
  final bool onboardingCompleted;
  final bool listCurrentMode;
  final int submissionDays;
  final int votingDays;
  final int submissionStartDayOffset;
  final int submissionStartHour;
  final int submissionStartMinute;
  final String playerIconMode;
  AppPreferences copyWith({
    String? theme,
    bool? notificationsEnabled,
    int? reminderMinutes,
    int? reminderHour,
    int? reminderMinute,
    String? selfName,
    bool? onboardingCompleted,
    bool? listCurrentMode,
    int? submissionDays,
    int? votingDays,
    int? submissionStartDayOffset,
    int? submissionStartHour,
    int? submissionStartMinute,
    String? playerIconMode,
  }) => AppPreferences(
    theme: theme ?? this.theme,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    selfName: selfName ?? this.selfName,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    listCurrentMode: listCurrentMode ?? this.listCurrentMode,
    submissionDays: submissionDays ?? this.submissionDays,
    votingDays: votingDays ?? this.votingDays,
    submissionStartDayOffset: submissionStartDayOffset ?? this.submissionStartDayOffset,
    submissionStartHour: submissionStartHour ?? this.submissionStartHour,
    submissionStartMinute: submissionStartMinute ?? this.submissionStartMinute,
    playerIconMode: playerIconMode ?? this.playerIconMode,
  );
  Map<String, dynamic> toJson() => {
    'theme': theme,
    'notificationsEnabled': notificationsEnabled,
    'reminderMinutes': reminderMinutes,
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
    'selfName': selfName,
    'onboardingCompleted': onboardingCompleted,
    'listCurrentMode': listCurrentMode,
    'submissionDays': submissionDays,
    'votingDays': votingDays,
    'submissionStartDayOffset': submissionStartDayOffset,
    'submissionStartHour': submissionStartHour,
    'submissionStartMinute': submissionStartMinute,
    'playerIconMode': playerIconMode,
  };
  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    final result = AppPreferences(
      theme: json['theme'] == null ? 'light' : _requiredString(json, 'theme'),
      notificationsEnabled: _boolValue(json, 'notificationsEnabled', false),
      reminderMinutes: _optionalInt(json, 'reminderMinutes') ?? 60,
      reminderHour: _optionalInt(json, 'reminderHour') ?? 9,
      reminderMinute: _optionalInt(json, 'reminderMinute') ?? 0,
      selfName: _optionalString(json, 'selfName'),
      onboardingCompleted: _boolValue(json, 'onboardingCompleted', false),
      listCurrentMode: _boolValue(json, 'listCurrentMode', false),
      submissionDays: _optionalInt(json, 'submissionDays') ?? 7,
      votingDays: _optionalInt(json, 'votingDays') ?? 7,
      submissionStartDayOffset: _optionalInt(json, 'submissionStartDayOffset') ?? -1,
      submissionStartHour: _optionalInt(json, 'submissionStartHour') ?? 22,
      submissionStartMinute: _optionalInt(json, 'submissionStartMinute') ?? 0,
      playerIconMode: json['playerIconMode'] == null ? 'auto' : _requiredString(json, 'playerIconMode'),
    );
    if (!const ['system','light','dark','stair'].contains(result.theme) || result.reminderMinutes < 0 || result.reminderMinutes > 10080 || result.reminderHour < 0 || result.reminderHour > 23 || result.reminderMinute < 0 || result.reminderMinute > 59 || result.submissionDays < 1 || result.submissionDays > 365 || result.votingDays < 1 || result.votingDays > 365 || result.submissionStartDayOffset < -365 || result.submissionStartDayOffset > 365 || result.submissionStartHour < 0 || result.submissionStartHour > 23 || result.submissionStartMinute < 0 || result.submissionStartMinute > 59 || !const ['auto','show','hide'].contains(result.playerIconMode)) throw const FormatException('Invalid application preferences.');
    return result;
  }

}

enum SiteRecurrence { irregular, weekly }

class OnlineSite {
  const OnlineSite({
    required this.id,
    required this.name,
    this.url = '',
    this.recurrence = SiteRecurrence.irregular,
    this.weekday = 1,
    this.startHour = 22,
    this.startMinute = 0,
    this.submissionDays = 7,
    this.votingDays = 7,
    this.affiliation = '',
    this.block = '',
    this.memo = '',
  });
  final String id;
  final String name;
  final String url;
  final SiteRecurrence recurrence;
  final int weekday;
  final int startHour;
  final int startMinute;
  final int submissionDays;
  final int votingDays;
  final String affiliation;
  final String block;
  final String memo;
  OnlineSite copyWith({
    String? name,
    String? url,
    SiteRecurrence? recurrence,
    int? weekday,
    int? startHour,
    int? startMinute,
    int? submissionDays,
    int? votingDays,
    String? affiliation,
    String? block,
    String? memo,
  }) => OnlineSite(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    recurrence: recurrence ?? this.recurrence,
    weekday: weekday ?? this.weekday,
    startHour: startHour ?? this.startHour,
    startMinute: startMinute ?? this.startMinute,
    submissionDays: submissionDays ?? this.submissionDays,
    votingDays: votingDays ?? this.votingDays,
    affiliation: affiliation ?? this.affiliation,
    block: block ?? this.block,
    memo: memo ?? this.memo,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'recurrence': recurrence.name,
    'weekday': weekday,
    'startHour': startHour,
    'startMinute': startMinute,
    'submissionDays': submissionDays,
    'votingDays': votingDays,
    'affiliation': affiliation,
    'block': block,
    'memo': memo,
  };
  factory OnlineSite.fromJson(Map<String, dynamic> json) {
    final result = OnlineSite(
      id: _requiredId(json),
      name: _requiredString(json, 'name'),
      url: _optionalString(json, 'url'),
      recurrence: json['recurrence'] == null ? SiteRecurrence.irregular : _enumValue(SiteRecurrence.values, json['recurrence'], 'recurrence'),
      weekday: _optionalInt(json, 'weekday') ?? 1,
      startHour: _optionalInt(json, 'startHour') ?? 22,
      startMinute: _optionalInt(json, 'startMinute') ?? 0,
      submissionDays: _optionalInt(json, 'submissionDays') ?? 7,
      votingDays: _optionalInt(json, 'votingDays') ?? 7,
      affiliation: _optionalString(json, 'affiliation'),
      block: _optionalString(json, 'block'),
      memo: _optionalString(json, 'memo'),
    );
    if (result.name.trim().isEmpty || result.weekday < 1 || result.weekday > 7 || result.startHour < 0 || result.startHour > 23 || result.startMinute < 0 || result.startMinute > 59 || result.submissionDays < 1 || result.votingDays < 1) throw const FormatException('Invalid online site.');
    return result;
  }

}

class GiriTeam {
  GiriTeam({
    required this.id,
    this.name = '',
    List<String> members = const [],
    this.isMine = false,
  }) : members = List.unmodifiable(members);
  final String id;
  final String name;
  final List<String> members;
  final bool isMine;
  GiriTeam copyWith({
    String? name,
    List<String>? members,
    bool? isMine,
  }) => GiriTeam(
    id: id,
    name: name ?? this.name,
    members: members ?? this.members,
    isMine: isMine ?? this.isMine,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'members': members,
    'isMine': isMine,
  };
  factory GiriTeam.fromJson(Map<String, dynamic> json) {
    final result = GiriTeam(
      id: _requiredId(json),
      name: _optionalString(json, 'name'),
      members: _stringList(json, 'members'),
      isMine: _boolValue(json, 'isMine', false),
    );

    return result;
  }

}

class TournamentStanding {
  TournamentStanding({
    required this.id,
    required this.placement,
    List<String> playerNames = const [],
    this.teamName = '',
    this.memo = '',
  }) : playerNames = List.unmodifiable(playerNames);
  final String id;
  final int placement;
  final List<String> playerNames;
  final String teamName;
  final String memo;
  TournamentStanding copyWith({
    int? placement,
    List<String>? playerNames,
    String? teamName,
    String? memo,
  }) => TournamentStanding(
    id: id,
    placement: placement ?? this.placement,
    playerNames: playerNames ?? this.playerNames,
    teamName: teamName ?? this.teamName,
    memo: memo ?? this.memo,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'placement': placement,
    'playerNames': playerNames,
    'teamName': teamName,
    'memo': memo,
  };
  factory TournamentStanding.fromJson(Map<String, dynamic> json) {
    final result = TournamentStanding(
      id: _requiredId(json),
      placement: _requiredPositiveInt(json, 'placement'),
      playerNames: _stringList(json, 'playerNames'),
      teamName: _optionalString(json, 'teamName'),
      memo: _optionalString(json, 'memo'),
    );

    return result;
  }

}

class GiriVenue {
  const GiriVenue({
    required this.id,
    required this.name,
    this.prefecture = '',
    this.mapUrl = '',
    this.memo = '',
    this.latitude,
    this.longitude,
    this.mapAddress = '',
  });
  final String id;
  final String name;
  final String prefecture;
  final String mapUrl;
  final String memo;
  final double? latitude;
  final double? longitude;
  final String mapAddress;
  GiriVenue copyWith({
    String? id,
    String? name,
    String? prefecture,
    String? mapUrl,
    String? memo,
    Object? latitude = _unchanged,
    Object? longitude = _unchanged,
    String? mapAddress,
  }) => GiriVenue(
    id: id ?? this.id,
    name: name ?? this.name,
    prefecture: prefecture ?? this.prefecture,
    mapUrl: mapUrl ?? this.mapUrl,
    memo: memo ?? this.memo,
    latitude: identical(latitude, _unchanged) ? this.latitude : (latitude as num?)?.toDouble(),
    longitude: identical(longitude, _unchanged) ? this.longitude : (longitude as num?)?.toDouble(),
    mapAddress: mapAddress ?? this.mapAddress,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prefecture': prefecture,
    'mapUrl': mapUrl,
    'memo': memo,
    'latitude': latitude,
    'longitude': longitude,
    'mapAddress': mapAddress,
  };
  factory GiriVenue.fromJson(Map<String, dynamic> json) {
    final result = GiriVenue(
      id: _requiredId(json),
      name: _requiredString(json, 'name'),
      prefecture: _optionalString(json, 'prefecture'),
      mapUrl: _optionalString(json, 'mapUrl'),
      memo: _optionalString(json, 'memo'),
      latitude: _finiteNumber(json, 'latitude'),
      longitude: _finiteNumber(json, 'longitude'),
      mapAddress: _optionalString(json, 'mapAddress'),
    );
    if (result.name.trim().isEmpty) throw const FormatException('A venue needs a name.');
    if ((result.latitude == null) != (result.longitude == null) ||
        (result.latitude != null && (result.latitude! < -90 || result.latitude! > 90)) ||
        (result.longitude != null && (result.longitude! < -180 || result.longitude! > 180))) {
      throw const FormatException('Invalid venue coordinates.');
    }
    return result;
  }

}


String? _nullableString(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _requiredString(json, key);
}
bool _boolValue(Map<String, dynamic> json, String key, bool fallback) {
  final value = json[key] ?? fallback;
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}
double? _nonnegativeNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite || value < 0) throw FormatException('Invalid $key.');
  return value.toDouble();
}

int _requiredPositiveInt(Map<String, dynamic> json, String key) {
  final value = _positiveInt(json, key);
  if (value == null) throw FormatException('$key is required.');
  return value;
}

GiriEvent _checkedEvent(GiriEvent event) {
  if (event.teamSize != null && event.teamSize! < 2) {
    throw const FormatException('A team needs at least two members.');
  }
  return event;
}

double? _finiteNumber(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite) throw FormatException('Invalid $key.');
  return value.toDouble();
}
