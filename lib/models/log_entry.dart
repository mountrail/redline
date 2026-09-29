// log_entry.dart
// -----------------------------------------------------------------------------
// Pure data class for a LOG_ENTRY — one numbered line in the equipment log
// book. Unlike the old one-item-per-record HISTORY design, one entry here
// can cover several items going out together under a single keterangan
// (e.g. "pinjam pakai HT (2 unit) oleh ... guna mendukung giat pam PMJ"),
// with one keluar (handover-out) event and, eventually, one masuk
// (handover-back) event closing the whole entry at once.
//
// If you later need PARTIAL returns (some items back, others still out),
// that's a real design change — for now, closing a log entry closes it for
// every item it lists, matching how a physical log book line works.
// -----------------------------------------------------------------------------

class LogEntry {
  final String id;

  /// Sequential, starting at 1 — see LocalStore.nextLogNumber(). Always
  /// display via [formattedLogNumber], never this raw int, so padding
  /// stays consistent everywhere.
  final int logNumber;

  final DateTime date;
  final String keterangan;

  /// FK list -> item.id. "Barang keluar" — every item this entry covers.
  final List<String> itemIds;

  /// FK -> personel.id. Who handed the item(s) out of the store.
  final String keluarDiserahkanId;

  /// FK -> personel.id. Who received the item(s) going out.
  final String keluarDiterimaId;

  /// Null while the entry is still open.
  final DateTime? masukDate;

  /// FK -> personel.id. Who handed the item(s) back in. Null while open.
  final String? masukDiserahkanId;

  /// FK -> personel.id. Who received the item(s) back into the store.
  /// Null while open.
  final String? masukDiterimaId;

  const LogEntry({
    required this.id,
    required this.logNumber,
    required this.date,
    required this.keterangan,
    required this.itemIds,
    required this.keluarDiserahkanId,
    required this.keluarDiterimaId,
    this.masukDate,
    this.masukDiserahkanId,
    this.masukDiterimaId,
  });

  bool get isReturned => masukDiserahkanId != null;

  String get formattedLogNumber => logNumber.toString().padLeft(3, '0');

  factory LogEntry.fromMap(String id, Map map) {
    return LogEntry(
      id: id,
      logNumber: map['log_number'] as int,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      keterangan: map['keterangan'] as String,
      itemIds: (map['item_ids'] as List).cast<String>(),
      keluarDiserahkanId: map['keluar_diserahkan_id'] as String,
      keluarDiterimaId: map['keluar_diterima_id'] as String,
      masukDate: map['masuk_date'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['masuk_date'] as int),
      masukDiserahkanId: map['masuk_diserahkan_id'] as String?,
      masukDiterimaId: map['masuk_diterima_id'] as String?,
    );
  }

  /// Dates stored as millisecondsSinceEpoch (plain int) rather than a
  /// DateTime object — Hive can store DateTime natively, but keeping it a
  /// plain int here means this map is already exactly what you'd hand to
  /// Timestamp.fromMillisecondsSinceEpoch() when the Firestore sync layer
  /// gets built, with no conversion logic to add later.
  Map<String, dynamic> toMap() => {
    'log_number': logNumber,
    'date': date.millisecondsSinceEpoch,
    'keterangan': keterangan,
    'item_ids': itemIds,
    'keluar_diserahkan_id': keluarDiserahkanId,
    'keluar_diterima_id': keluarDiterimaId,
    'masuk_date': masukDate?.millisecondsSinceEpoch,
    'masuk_diserahkan_id': masukDiserahkanId,
    'masuk_diterima_id': masukDiterimaId,
  };
}
