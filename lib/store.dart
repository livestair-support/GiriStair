import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'participant_import.dart';
import 'storage.dart';

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
    for (final name in _document.events.expand((event) => event.participants)) {
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

  Future<void> saveEvent(GiriEvent event) => _mutate((document) {
    final index = document.events.indexWhere((item) => item.id == event.id);
    if (index < 0) {
      document.events.add(event);
    } else {
      document.events[index] = event;
    }
    final known = document.players
        .map((player) => playerSearchKey(player.name))
        .toSet();
    for (final name in event.participants) {
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
        document.notes[i] = document.notes[i].copyWith(eventId: null, roundId: null);
      }
    }
  });

  Future<void> saveNote(ThoughtNote note) => _mutate((document) {
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
        document.events[i] = event.copyWith(
          participants: event.participants
              .map(
                (participant) =>
                    playerSearchKey(participant) == oldKey ? name : participant,
              )
              .toList(),
        );
      }
    }
  });

  /// Removing a profile does not erase participant names from past records.
  Future<void> deletePlayer(String id) => _mutate((document) {
    document.players.removeWhere((player) => player.id == id);
  });

  Future<void> savePreferences(AppPreferences preferences) =>
      _mutate((document) {
        document.preferences = AppPreferences.fromJson(preferences.toJson());
      });

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
    this.preferences = const AppPreferences(),
    this.lastBackupAt,
  }) : events = events ?? [],
       notes = notes ?? [],
       players = players ?? [];

  final List<GiriEvent> events;
  final List<ThoughtNote> notes;
  final List<GiriPlayer> players;
  AppPreferences preferences;
  DateTime? lastBackupAt;

  _GiriDocument copy() => _GiriDocument(
    events: List.of(events),
    notes: List.of(notes),
    players: List.of(players),
    preferences: preferences,
    lastBackupAt: lastBackupAt,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'events': events.map((event) => event.toJson()).toList(),
    'notes': notes.map((note) => note.toJson()).toList(),
    'players': players.map((player) => player.toJson()).toList(),
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
      preferences: settings == null
          ? const AppPreferences()
          : AppPreferences.fromJson(settings as Map<String, dynamic>),
      lastBackupAt: backupAt == null
          ? null
          : DateTime.parse(backupAt as String).toLocal(),
    );
  }
}
