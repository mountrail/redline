// logistics_repository.dart
// -----------------------------------------------------------------------------
// Single access point for the logistics module's data. Everything goes
// through LocalStore (Hive) right now — no network, no Firebase — so the
// app works fully offline, like Google Keep before it ever syncs. When a
// Firebase sync layer is added later, it should mirror LocalStore's writes
// out and merge remote changes back in; this file's public API is the seam
// that shouldn't need to change for that, so screens keep working as-is.
// -----------------------------------------------------------------------------

import '../models/item.dart';
import '../models/log_entry.dart';
import '../models/personel.dart';
import 'local_store.dart';

class LogisticsRepository {
  LogisticsRepository({LocalStore? store})
    : _store = store ?? LocalStore.instance;

  final LocalStore _store;

  // ---------------------------------------------------------------------
  // Reads / streams
  // ---------------------------------------------------------------------

  Stream<List<Personel>> watchAllPersonel() =>
      _store.watchAll(_store.personelBox, Personel.fromMap);

  Stream<List<Item>> watchAllItems() =>
      _store.watchAll(_store.itemBox, Item.fromMap);

  Stream<List<Item>> watchItemsOut() {
    return watchAllItems().map(
      (items) => items.where((i) => i.currentStatus == ItemStatus.out).toList(),
    );
  }

  /// All log entries, newest (highest log number) first.
  Stream<List<LogEntry>> watchAllLogEntries() {
    return _store
        .watchAll(_store.logEntryBox, LogEntry.fromMap)
        .map(
          (entries) =>
              entries..sort((a, b) => b.logNumber.compareTo(a.logNumber)),
        );
  }

  Stream<List<LogEntry>> watchOpenLogEntries() {
    return watchAllLogEntries().map(
      (entries) => entries.where((e) => !e.isReturned).toList(),
    );
  }

  /// Synchronous single-entry lookup — Hive box reads are synchronous once
  /// open, so no need for a Future/stream just to find one entry by id
  /// (used when closing the entry that currently covers a given item).
  LogEntry? getLogEntry(String id) {
    final raw = _store.logEntryBox.get(id);
    return raw == null ? null : LogEntry.fromMap(id, raw);
  }

  // ---------------------------------------------------------------------
  // Creating master data, enforcing "NRP/SN preferably unique" where present
  // ---------------------------------------------------------------------
  //
  // Concurrency note: this module is single-device/single-isolate, and
  // there's no `await` between the uniqueness check and the box write
  // below, so a normal tap is safe. A rapid double-tap on "ADD" before the
  // first write's Future resolves could still race past the check — guard
  // that at the UI layer (disable the button after first tap) rather than
  // here; a real lock isn't worth adding for a personal, local-only store.

  Future<String> createPersonel({
    String? nrp,
    required String name,
    required String satuanKerja,
    String? phone,
  }) async {
    final cleanNrp = (nrp == null || nrp.isEmpty) ? null : nrp;
    if (cleanNrp != null) {
      final clash = _store.personelBox.values.any((m) => m['nrp'] == cleanNrp);
      if (clash) {
        throw StateError(
          'NRP "$cleanNrp" is already assigned to another person.',
        );
      }
    }
    final id = _newId();
    await _store.personelBox.put(id, {
      'nrp': cleanNrp,
      'name': name,
      'satuan_kerja': satuanKerja,
      'phone': (phone == null || phone.isEmpty) ? null : phone,
    });
    return id;
  }

  Future<String> createItem({String? sn, required String name}) async {
    final cleanSn = (sn == null || sn.isEmpty) ? null : sn;
    if (cleanSn != null) {
      final clash = _store.itemBox.values.any((m) => m['sn'] == cleanSn);
      if (clash) {
        throw StateError(
          'Serial number "$cleanSn" is already assigned to another item.',
        );
      }
    }
    final id = _newId();
    await _store.itemBox.put(id, {
      'sn': cleanSn,
      'name': name,
      'current_status': 'IN_STORE',
      'current_holder_id': null,
      'last_log_entry_id': null,
    });
    return id;
  }

  // ---------------------------------------------------------------------
  // The two logistics operations: open a log entry (items go out) and
  // close one (items come back). Each item's cached current_* fields on
  // `item` stay in sync with the log entry driving them.
  // ---------------------------------------------------------------------

  /// Opens a new numbered log entry covering [itemIds]. Throws if ANY of
  /// those items is already checked out — closing a log entry closes it
  /// for every item it lists, so an item can't belong to two open entries
  /// at once.
  Future<String> createLogEntry({
    required List<String> itemIds,
    required String keterangan,
    required String keluarDiserahkanId,
    required String keluarDiterimaId,
    DateTime? date,
  }) async {
    if (itemIds.isEmpty) {
      throw StateError('A log entry needs at least one item.');
    }
    for (final itemId in itemIds) {
      final raw = _store.itemBox.get(itemId);
      if (raw == null) throw StateError('Item $itemId does not exist.');
      if (raw['current_status'] == 'OUT') {
        throw StateError('${raw['name']} is already checked out.');
      }
    }

    final id = _newId();
    final logNumber = await _store.nextLogNumber();
    final entry = LogEntry(
      id: id,
      logNumber: logNumber,
      date: date ?? DateTime.now(),
      keterangan: keterangan,
      itemIds: itemIds,
      keluarDiserahkanId: keluarDiserahkanId,
      keluarDiterimaId: keluarDiterimaId,
    );

    await _store.logEntryBox.put(id, entry.toMap());

    for (final itemId in itemIds) {
      final raw = Map<String, dynamic>.from(_store.itemBox.get(itemId)!);
      raw['current_status'] = 'OUT';
      raw['current_holder_id'] = keluarDiterimaId;
      raw['last_log_entry_id'] = id;
      await _store.itemBox.put(itemId, raw);
    }

    return id;
  }

  /// Closes [logEntryId]: fills in the masuk fields and flips every item
  /// it lists back to IN_STORE. Throws if the entry doesn't exist or is
  /// already closed.
  Future<void> closeLogEntry({
    required String logEntryId,
    required String masukDiserahkanId,
    required String masukDiterimaId,
    DateTime? date,
  }) async {
    final raw = _store.logEntryBox.get(logEntryId);
    if (raw == null) throw StateError('Log entry $logEntryId does not exist.');
    final entry = LogEntry.fromMap(logEntryId, raw);
    if (entry.isReturned) {
      throw StateError('Log ${entry.formattedLogNumber} is already closed.');
    }

    final updated = Map<String, dynamic>.from(raw);
    updated['masuk_date'] = (date ?? DateTime.now()).millisecondsSinceEpoch;
    updated['masuk_diserahkan_id'] = masukDiserahkanId;
    updated['masuk_diterima_id'] = masukDiterimaId;
    await _store.logEntryBox.put(logEntryId, updated);

    for (final itemId in entry.itemIds) {
      final itemRaw = _store.itemBox.get(itemId);
      if (itemRaw == null) continue; // item deleted since — nothing to fix up
      final updatedItem = Map<String, dynamic>.from(itemRaw);
      updatedItem['current_status'] = 'IN_STORE';
      updatedItem['current_holder_id'] = null;
      await _store.itemBox.put(itemId, updatedItem);
    }
  }

  /// Timestamp-based id, unique enough for a single local device: two
  /// calls on the same isolate can't land on the same microsecond given
  /// the `await` overhead between them. If Firestore sync is added later,
  /// consider switching to Firestore's own auto-IDs at that point instead.
  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
