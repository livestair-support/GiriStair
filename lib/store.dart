import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'participant_import.dart';
import 'storage.dart';
import 'scheduling.dart';

class GiriStore extends ChangeNotifier {
  GiriStore({required GiriStorage storage}) : _storage = storage;

  final GiriStorage _storage;
  final Random _random = Random.secure();
  _GiriDocument _document = _GiriDocument();
  Future<void> _pending = Future.value();
  bool _loaded = false;

  List<GiriEvent> get events => List.unmodifiable(_document.events);
  List<ThoughtNote> get notes => List.unmodifiable(_document.notes);
  List<GiriPlayer> get players => List.unmodifiable(_document.players);
  List<OnlineSite> get onlineSites => List.unmodifiable(_document.onlineSites);
  List<GiriVenue> get venues => List.unmodifiable(_document.venues);
  OnlineSite? onlineSiteById(String? id) =>
      onlineSites.where((site) => site.id == id).firstOrNull;
  GiriVenue? venueById(String? id) =>
      venueDirectory.where((venue) => venue.id == id).firstOrNull;
  GiriPlayer? playerByName(String name) => playerDirectory
      .where((player) => playerSearchKey(player.name) == playerSearchKey(name))
      .firstOrNull;
  bool get showPlayerIcons =>
      preferences.playerIconMode == 'show' ||
      (preferences.playerIconMode == 'auto' &&
          players.any((player) => player.iconDataBase64.isNotEmpty));
  AppPreferences get preferences => _document.preferences;
  DateTime? get lastBackupAt => _document.lastBackupAt;
  bool get loaded => _loaded;

  /// Existing records become available in the directory without requiring a
  /// migration write. Synthetic IDs are converted to durable IDs when edited.
  List<GiriPlayer> get playerDirectory {
    final profiles = <String, GiriPlayer>{
      for (final player in _document.players)
        playerSearchKey(player.name): player,
    };
    for (final name in [
      preferences.selfName,
      ..._document.events.expand(
        (event) => [
          event.organizer,
          ...event.participants,
          ...event.teams.expand((team) => team.members),
          ...?event.tournamentResult?.members,
          ...event.standings.expand((standing) => standing.playerNames),
        ],
      ),
    ]) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      final key = playerSearchKey(trimmed);
      profiles.putIfAbsent(
        key,
        () => GiriPlayer(id: 'history:$key', name: trimmed),
      );
    }
    return List.unmodifiable(
      profiles.values.toList()..sort((a, b) {
        final aKey = playerSearchKey(a.furigana.isEmpty ? a.name : a.furigana);
        final bKey = playerSearchKey(b.furigana.isEmpty ? b.name : b.furigana);
        final order = aKey.compareTo(bKey);
        return order == 0 ? a.name.compareTo(b.name) : order;
      }),
    );
  }

  String newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void> load() => _enqueue(() async {
    if (_loaded) return;
    final contents = await _storage.read();
    // Decode every record before publishing any data. A malformed file never
    // becomes an empty document that could overwrite the user's saved data.
    final document = contents == null
        ? _GiriDocument()
        : _GiriDocument.decode(contents);
    _document = document;
    _loaded = true;
    notifyListeners();
  });

  Future<void> saveEvent(GiriEvent candidate) => _mutate((document) {
    final event = GiriEvent.fromJson(candidate.toJson());
    final index = document.events.indexWhere((item) => item.id == event.id);
    if (index < 0) {
      document.events.add(event);
    } else {
      document.events[index] = event;
    }
    final known = document.players
        .map((player) => playerSearchKey(player.name))
        .toSet();
    for (final name in [
      event.organizer,
      ...event.participants,
      ...event.teams.expand((team) => team.members),
      ...?event.tournamentResult?.members,
      ...event.standings.expand((standing) => standing.playerNames),
    ]) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty && known.add(playerSearchKey(trimmed))) {
        document.players.add(GiriPlayer(id: newId(), name: trimmed));
      }
    }
  });

  Future<void> deleteEvent(String id) => _mutate((document) {
    document.events.removeWhere((event) => event.id == id);
    for (var i = 0; i < document.notes.length; i++) {
      if (document.notes[i].eventId == id) {
        document.notes[i] = document.notes[i].copyWith(
          eventId: null,
          roundId: null,
        );
      }
    }
  });

  Future<void> saveNote(ThoughtNote candidate) => _mutate((document) {
    final note = ThoughtNote.fromJson(candidate.toJson());
    final index = document.notes.indexWhere((item) => item.id == note.id);
    if (index < 0) {
      document.notes.add(note);
    } else {
      document.notes[index] = note;
    }
  });

  Future<void> deleteNote(String id) => _mutate((document) {
    document.notes.removeWhere((note) => note.id == id);
  });

  Future<void> savePlayer(GiriPlayer player) => _mutate((document) {
    final name = player.name.trim();
    if (player.id.trim().isEmpty) {
      throw const FormatException('プレイヤーIDが不正です。');
    }
    if (name.isEmpty) throw const FormatException('名前を入力してください。');
    final old = playerDirectory.where((p) => p.id == player.id).firstOrNull;
    final key = playerSearchKey(name);
    if (playerDirectory.any(
      (p) => p.id != player.id && playerSearchKey(p.name) == key,
    )) {
      throw const FormatException('同じ名前のプレイヤーが登録されています。');
    }
    final index = document.players.indexWhere((p) => p.id == player.id);
    final saved = GiriPlayer(
      id: player.id.startsWith('history:') ? newId() : player.id,
      name: name,
      furigana: player.furigana.trim(),
      region: player.region.trim(),
      iconDataBase64: player.iconDataBase64,
      twitterUrl: player.twitterUrl.trim(),
      memo: player.memo,
    );
    if (index < 0) {
      document.players.add(saved);
    } else {
      document.players[index] = saved;
    }
    if (old != null && old.name != name) {
      final oldKey = playerSearchKey(old.name);
      for (var i = 0; i < document.events.length; i++) {
        final event = document.events[i];
        String renamed(String name) =>
            playerSearchKey(name) == oldKey ? saved.name : name;
        document.events[i] = event.copyWith(
          organizer: renamed(event.organizer),
          teams: event.teams
              .map(
                (team) =>
                    team.copyWith(members: team.members.map(renamed).toList()),
              )
              .toList(),
          standings: event.standings
              .map(
                (standing) => standing.copyWith(
                  playerNames: standing.playerNames.map(renamed).toList(),
                ),
              )
              .toList(),
          tournamentResult: event.tournamentResult?.copyWith(
            members: event.tournamentResult!.members.map(renamed).toList(),
          ),
          participants: event.participants
              .map(
                (participant) =>
                    playerSearchKey(participant) == oldKey ? name : participant,
              )
              .toList(),
        );
    }
      if (playerSearchKey(document.preferences.selfName) == oldKey) {
        document.preferences = document.preferences.copyWith(selfName: name);
      }
    }
  });

  /// Removing a profile does not erase participant names from past records.
  Future<void> deletePlayer(String id) => _mutate((document) {
    document.players.removeWhere((player) => player.id == id);
  });

  Future<void> savePreferences(AppPreferences preferences) => _mutate((
    document,
  ) {
    final checked = AppPreferences.fromJson(preferences.toJson());
    document.preferences = checked.copyWith(selfName: checked.selfName.trim());
    final name = document.preferences.selfName;
    if (name.isNotEmpty &&
        !document.players.any(
          (player) => playerSearchKey(player.name) == playerSearchKey(name),
        )) {
      document.players.add(GiriPlayer(id: newId(), name: name));
    }
  });

  List<GiriPlayer> suggestPlayers(String query, {bool organizer = false}) {
    final key = playerSearchKey(query);
    final counts = <String, int>{};
    for (final event in events.where(
      (event) => event.status != EventStatus.canceled,
    )) {
      for (final name
          in organizer ? [event.organizer] : event.participants.toSet()) {
        final normalized = playerSearchKey(name);
        counts.update(normalized, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final result = playerDirectory
        .where(
          (player) =>
              key.isEmpty ||
              playerSearchKey(player.name).contains(key) ||
              playerSearchKey(player.furigana).contains(key),
        )
        .toList();
    result.sort((a, b) {
      final frequent = (counts[playerSearchKey(b.name)] ?? 0).compareTo(
        counts[playerSearchKey(a.name)] ?? 0,
      );
      return frequent != 0
          ? frequent
          : playerSearchKey(a.furigana.isEmpty ? a.name : a.furigana).compareTo(
              playerSearchKey(b.furigana.isEmpty ? b.name : b.furigana),
            );
    });
    return result;
  }

  List<GiriVenue> get venueDirectory {
    final result = <String, GiriVenue>{
      for (final venue in venues) playerSearchKey(venue.name): venue,
    };
    for (final event in events) {
      if (event.venue.trim().isEmpty) continue;
      final key = playerSearchKey(event.venue);
      result.putIfAbsent(
        key,
        () => GiriVenue(id: 'history:$key', name: event.venue.trim()),
      );
    }
    return result.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> saveVenue(GiriVenue venue) => _mutate((document) {
    final checked = GiriVenue.fromJson(venue.toJson());
    final old = venueById(venue.id);
    if (venueDirectory.any(
      (other) =>
          other.id != venue.id &&
          playerSearchKey(other.name) == playerSearchKey(checked.name),
    )) {
      throw const FormatException('同じ会場名が登録されています。');
    }
    final saved = checked.id.startsWith('history:')
        ? checked.copyWith(id: newId())
        : checked;
    final index = document.venues.indexWhere((item) => item.id == venue.id);
    if (index < 0) {
      document.venues.add(saved);
    } else {
      document.venues[index] = saved;
    }
    if (old != null) {
      for (var i = 0; i < document.events.length; i++) {
        final event = document.events[i];
        if (event.venueId == old.id ||
            playerSearchKey(event.venue) == playerSearchKey(old.name)) {
          document.events[i] = event.copyWith(
            venue: saved.name,
            venueId: saved.id,
          );
        }
      }
    }
  });
  Future<void> deleteVenue(String id) => _mutate((document) {
    document.venues.removeWhere((venue) => venue.id == id);
    for (var i = 0; i < document.events.length; i++) {
      if (document.events[i].venueId == id) {
        document.events[i] = document.events[i].copyWith(venueId: null);
      }
    }
  });

  Future<void> saveOnlineSite(OnlineSite site) => _mutate((document) {
    final checked = OnlineSite.fromJson(site.toJson());
    final index = document.onlineSites.indexWhere((item) => item.id == site.id);
    if (index < 0) {
      document.onlineSites.add(checked);
    } else {
      document.onlineSites[index] = checked;
    }
  });
  Future<void> deleteOnlineSite(String id) => _mutate((document) {
    document.onlineSites.removeWhere((site) => site.id == id);
    for (var i = 0; i < document.events.length; i++) {
      if (document.events[i].onlineSiteId == id) {
        document.events[i] = document.events[i].copyWith(onlineSiteId: null);
      }
    }
  });

  Future<GiriEvent> createSiteCycle(
    String siteId, {
    DateTime? weekOf,
    int weekOffset = 0,
    DateTime? submissionStart,
    bool join = true,
  }) async {
    late GiriEvent result;
    await _enqueue(() async {
      _requireLoaded();
      final site = onlineSiteById(siteId);
      if (site == null) throw const FormatException('サイトが見つかりません。');
      final start =
          submissionStart ??
          siteCycleStart(
            site,
            weekOf ?? DateTime.now(),
            weekOffset: weekOffset,
          );
      final key = cycleKeyFor(start);
      final existing = _document.events
          .where(
            (event) => event.onlineSiteId == siteId && event.cycleKey == key,
          )
          .firstOrNull;
      if (existing != null) {
        if (!join || existing.isParticipating) {
          result = existing;
          return;
        }
        final selfName = preferences.selfName.trim();
        final participants = List<String>.of(existing.participants);
        if (selfName.isNotEmpty &&
            !participants.any(
              (name) => playerSearchKey(name) == playerSearchKey(selfName),
            )) {
          participants.add(selfName);
        }
        result = existing.copyWith(
          isParticipating: true,
          participants: participants,
        );
        final document = _document.copy();
        final index = document.events.indexWhere(
          (event) => event.id == existing.id,
        );
        document.events[index] = result;
        await _storage.write(jsonEncode(document.toJson()));
        _document = document;
        notifyListeners();
        return;
      }
      final roundId = newId();
      final round = completeRoundSchedule(
        EventRound(
          id: roundId,
          name: '投稿・投票',
          stageId: roundId,
          block: site.block,
          submissionStart: start,
        ),
        submissionDays: site.submissionDays,
        votingDays: site.votingDays,
      );
      result = GiriEvent(
        id: newId(),
        title: site.name,
        kind: EventKind.online,
        meetingType: MeetingType.casual,
        createdAt: DateTime.now(),
        onlineSiteId: site.id,
        cycleKey: key,
        affiliation: site.affiliation,
        block: site.block,
        siteUrl: site.url,
        memo: site.memo,
        rounds: [round],
        isParticipating: join,
        participants: join && preferences.selfName.isNotEmpty
            ? [preferences.selfName]
            : const [],
      );
      final document = _document.copy();
      document.events.add(result);
      await _storage.write(jsonEncode(document.toJson()));
      _document = document;
      notifyListeners();
    });
    return result;
  }

  Future<void> ensureCurrentSiteCycles({DateTime? now}) async {
    for (final site in onlineSites.where(
      (site) => site.recurrence == SiteRecurrence.weekly,
    )) {
      await createSiteCycle(site.id, weekOf: now, weekOffset: -1, join: false);
      await createSiteCycle(site.id, weekOf: now, join: false);
      await createSiteCycle(site.id, weekOf: now, weekOffset: 1, join: false);
    }
  }

  String exportBackup() {
    _requireLoaded();
    return const JsonEncoder.withIndent('  ').convert(_document.toJson());
  }

  Future<void> recordBackupExported() => _mutate((document) {
    document.lastBackupAt = DateTime.now();
  });

  Future<void> restoreBackup(String contents) => _enqueue(() async {
    _requireLoaded();
    final restored = _GiriDocument.decode(contents);
    await _storage.write(jsonEncode(restored.toJson()));
    _document = restored;
    notifyListeners();
  });

  Future<void> _mutate(void Function(_GiriDocument document) change) =>
      _enqueue(() async {
        _requireLoaded();
        final document = _document.copy();
        change(document);
        // Commit to memory only after the durable write succeeds.
        await _storage.write(jsonEncode(document.toJson()));
        _document = document;
        notifyListeners();
      });

  void _requireLoaded() {
    if (!_loaded) {
      throw StateError('Load saved data successfully before making changes.');
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    // A failed operation must not poison the queue or prevent a retry.
    _pending = result.catchError((Object error, StackTrace stackTrace) {});
    return result;
  }
}

class _GiriDocument {
  _GiriDocument({
    List<GiriEvent>? events,
    List<ThoughtNote>? notes,
    List<GiriPlayer>? players,
    List<OnlineSite>? onlineSites,
    List<GiriVenue>? venues,
    this.preferences = const AppPreferences(),
    this.lastBackupAt,
  }) : events = events ?? [],
       notes = notes ?? [],
       players = players ?? [],
       onlineSites = onlineSites ?? [],
       venues = venues ?? [];

  final List<GiriEvent> events;
  final List<ThoughtNote> notes;
  final List<GiriPlayer> players;
  final List<OnlineSite> onlineSites;
  final List<GiriVenue> venues;
  AppPreferences preferences;
  DateTime? lastBackupAt;

  _GiriDocument copy() => _GiriDocument(
    events: List.of(events),
    notes: List.of(notes),
    players: List.of(players),
    onlineSites: List.of(onlineSites),
    venues: List.of(venues),
    preferences: preferences,
    lastBackupAt: lastBackupAt,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'events': events.map((event) => event.toJson()).toList(),
    'notes': notes.map((note) => note.toJson()).toList(),
    'players': players.map((player) => player.toJson()).toList(),
    'onlineSites': onlineSites.map((site) => site.toJson()).toList(),
    'venues': venues.map((venue) => venue.toJson()).toList(),
    'preferences': preferences.toJson(),
    'lastBackupAt': lastBackupAt?.toUtc().toIso8601String(),
  };

  factory _GiriDocument.decode(String contents) {
    final json = jsonDecode(contents);
    if (json is! Map<String, dynamic> ||
        json['schemaVersion'] != 1 ||
        json['events'] is! List ||
        json['notes'] is! List) {
      throw const FormatException('Unsupported GiriStair data format.');
    }
    List<T> records<T>(
      String key,
      T Function(Map<String, dynamic>) decode, {
      bool optional = false,
    }) {
      final value = json[key];
      if (optional && value == null) return [];
      if (value is! List) throw FormatException('Invalid $key list.');
      return value.map((item) {
        if (item is! Map<String, dynamic>) {
          throw FormatException('Invalid $key record.');
        }
        return decode(item);
      }).toList();
    }

    final events = records('events', GiriEvent.fromJson);
    final notes = records('notes', ThoughtNote.fromJson);
    final players = records('players', GiriPlayer.fromJson, optional: true);
    final onlineSites = records(
      'onlineSites',
      OnlineSite.fromJson,
      optional: true,
    );
    final venues = records('venues', GiriVenue.fromJson, optional: true);
    if (onlineSites.map((item) => item.id).toSet().length !=
            onlineSites.length ||
        venues.map((item) => item.id).toSet().length != venues.length) {
      throw const FormatException('Duplicate site or venue IDs.');
    }
    if (events.map((item) => item.id).toSet().length != events.length ||
        notes.map((item) => item.id).toSet().length != notes.length ||
        players.map((item) => item.id).toSet().length != players.length ||
        players.map((item) => playerSearchKey(item.name)).toSet().length !=
            players.length) {
      throw const FormatException('Duplicate record IDs or player names.');
    }
    final settings = json['preferences'];
    if (settings != null && settings is! Map<String, dynamic>) {
      throw const FormatException('Invalid application preferences.');
    }
    final backupAt = json['lastBackupAt'];
    if (backupAt != null &&
        (backupAt is! String || DateTime.tryParse(backupAt) == null)) {
      throw const FormatException('Invalid backup date.');
    }
    return _GiriDocument(
      events: events,
      notes: notes,
      players: players,
      onlineSites: onlineSites,
      venues: venues,
      preferences: settings == null
          ? const AppPreferences()
          : AppPreferences.fromJson(settings as Map<String, dynamic>),
      lastBackupAt: backupAt == null
          ? null
          : DateTime.parse(backupAt as String).toLocal(),
    );
  }
}
