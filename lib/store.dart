import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'storage.dart';

class GiriStore extends ChangeNotifier {
  GiriStore({required GiriStorage storage}) : _storage = storage;

  final GiriStorage _storage;
  final Random _random = Random.secure();
  List<GiriEvent> _events = const [];
  List<ThoughtNote> _notes = const [];
  Future<void> _pending = Future.value();
  bool _loaded = false;

  List<GiriEvent> get events => List.unmodifiable(_events);
  List<ThoughtNote> get notes => List.unmodifiable(_notes);
  bool get loaded => _loaded;

  String newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Future<void> load() => _enqueue(() async {
    if (_loaded) return;
    final contents = await _storage.read();
    var events = <GiriEvent>[];
    var notes = <ThoughtNote>[];
    if (contents != null) {
      final document = jsonDecode(contents);
      if (document is! Map<String, dynamic> ||
          document['schemaVersion'] != 1 ||
          document['events'] is! List ||
          document['notes'] is! List) {
        throw const FormatException('Unsupported GiriStair data format.');
      }
      events = (document['events'] as List).map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid event record.');
        }
        return GiriEvent.fromJson(value);
      }).toList();
      notes = (document['notes'] as List).map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid thought record.');
        }
        return ThoughtNote.fromJson(value);
      }).toList();
      if (events.map((event) => event.id).toSet().length != events.length ||
          notes.map((note) => note.id).toSet().length != notes.length) {
        throw const FormatException('Duplicate record IDs.');
      }
    }
    // Do not expose partial data if decoding any record fails.
    _events = events;
    _notes = notes;
    _loaded = true;
    notifyListeners();
  });

  Future<void> saveEvent(GiriEvent event) => _mutate((events, notes) {
    final index = events.indexWhere((item) => item.id == event.id);
    if (index < 0) {
      events.add(event);
    } else {
      events[index] = event;
    }
  });

  Future<void> deleteEvent(String id) => _mutate((events, notes) {
    events.removeWhere((event) => event.id == id);
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].eventId == id) {
        notes[i] = notes[i].copyWith(eventId: null);
      }
    }
  });

  Future<void> saveNote(ThoughtNote note) => _mutate((events, notes) {
    final index = notes.indexWhere((item) => item.id == note.id);
    if (index < 0) {
      notes.add(note);
    } else {
      notes[index] = note;
    }
  });

  Future<void> deleteNote(String id) => _mutate((events, notes) {
    notes.removeWhere((note) => note.id == id);
  });

  Future<void> _mutate(
    void Function(List<GiriEvent> events, List<ThoughtNote> notes) change,
  ) => _enqueue(() async {
    if (!_loaded) {
      throw StateError('Load saved data successfully before making changes.');
    }
    final events = List<GiriEvent>.of(_events);
    final notes = List<ThoughtNote>.of(_notes);
    change(events, notes);
    final contents = jsonEncode({
      'schemaVersion': 1,
      'events': events.map((event) => event.toJson()).toList(),
      'notes': notes.map((note) => note.toJson()).toList(),
    });
    // Commit to memory only after the durable write succeeds.
    await _storage.write(contents);
    _events = events;
    _notes = notes;
    notifyListeners();
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    // A failed operation is still returned to its caller, but must not poison
    // the queue and prevent retrying a read or a subsequent save.
    _pending = result.catchError((Object error, StackTrace stackTrace) {});
    return result;
  }
}
