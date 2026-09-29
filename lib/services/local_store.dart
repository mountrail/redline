// local_store.dart
// -----------------------------------------------------------------------------
// The app's ONLY on-disk persistence for the logistics module right now.
// Built on Hive: pure-Dart, no native SQLite binding, no code generation —
// we store plain Map<String, dynamic> and Hive has built-in support for
// String/int/double/bool/DateTime/List/Map, so no TypeAdapter registration
// is needed.
//
// This is deliberately the seam where a future Firebase sync layer plugs
// in — exactly like Google Keep: every write here is "the truth"
// immediately, no network round-trip required, and syncing to a remote is
// a separate, best-effort concern layered on top later (a SyncCoordinator
// that mirrors LocalStore's writes out to Firestore when a connection and
// signed-in user are available, and merges remote changes back in).
// LogisticsRepository never touches Hive directly except through this
// file, and its own public API is written so that adding that sync layer
// later shouldn't require changing it — or any screen — at all.
// -----------------------------------------------------------------------------

import 'package:hive_flutter/hive_flutter.dart';

class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  static const _personelBoxName = 'personel';
  static const _itemBoxName = 'item';
  static const _logEntryBoxName = 'log_entries';
  static const _metaBoxName = 'meta';

  late Box<Map> _personelBox;
  late Box<Map> _itemBox;
  late Box<Map> _logEntryBox;
  late Box _metaBox;

  bool _initialized = false;

  /// Opens every box. Must be awaited once, before runApp() — nothing that
  /// reads or writes data can run before this completes.
  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _personelBox = await Hive.openBox<Map>(_personelBoxName);
    _itemBox = await Hive.openBox<Map>(_itemBoxName);
    _logEntryBox = await Hive.openBox<Map>(_logEntryBoxName);
    _metaBox = await Hive.openBox(_metaBoxName);
    _initialized = true;
  }

  Box<Map> get personelBox => _personelBox;
  Box<Map> get itemBox => _itemBox;
  Box<Map> get logEntryBox => _logEntryBox;

  /// Returns the next sequential log number, starting at 1. See the
  /// concurrency note in LogisticsRepository — fine for a single local
  /// device, not designed for concurrent writers.
  Future<int> nextLogNumber() async {
    final current = (_metaBox.get('log_counter') as int?) ?? 0;
    final next = current + 1;
    await _metaBox.put('log_counter', next);
    return next;
  }

  /// Reads every entry in [box] and maps it to a typed object. Fine at the
  /// data sizes a personal logistics log actually reaches — no need for
  /// incremental diffing.
  List<T> readAll<T>(Box<Map> box, T Function(String id, Map map) fromMap) {
    return box.keys
        .map((key) => fromMap(key as String, box.get(key)!))
        .toList();
  }

  /// Emits the current contents of [box] immediately, then again every
  /// time the box changes — this is what gives the UI its "live"
  /// StreamBuilder feel with zero network involved.
  Stream<List<T>> watchAll<T>(
    Box<Map> box,
    T Function(String id, Map map) fromMap,
  ) async* {
    yield readAll(box, fromMap);
    await for (final _ in box.watch()) {
      yield readAll(box, fromMap);
    }
  }
}
