// item.dart
// -----------------------------------------------------------------------------
// Pure data class for an ITEM record.
//
// current_status / current_holder_id / last_log_entry_id are a cache of
// "what does this item's most recent LOG_ENTRY say" — rewritten only
// inside LogisticsRepository's createLogEntry()/closeLogEntry(), never
// edited independently. log_entries remains the permanent record.
// -----------------------------------------------------------------------------

enum ItemStatus { inStore, out }

ItemStatus itemStatusFromString(String? raw) =>
    raw == 'OUT' ? ItemStatus.out : ItemStatus.inStore;

String itemStatusToString(ItemStatus status) =>
    status == ItemStatus.out ? 'OUT' : 'IN_STORE';

class Item {
  final String id;

  /// Real-world identifying attribute, NOT a relationship key. May be
  /// null — not every item has a serial number.
  final String? sn;

  final String name;

  final ItemStatus currentStatus;

  /// Cached copy of the covering log entry's `keluar_diterima_id`. Null
  /// when currentStatus is inStore.
  final String? currentHolderId;

  /// The log entry currently (or most recently) covering this item. Used
  /// by closeLogEntry() to find which entry to close without a query.
  final String? lastLogEntryId;

  const Item({
    required this.id,
    this.sn,
    required this.name,
    this.currentStatus = ItemStatus.inStore,
    this.currentHolderId,
    this.lastLogEntryId,
  });

  factory Item.fromMap(String id, Map map) {
    return Item(
      id: id,
      sn: map['sn'] as String?,
      name: map['name'] as String,
      currentStatus: itemStatusFromString(map['current_status'] as String?),
      currentHolderId: map['current_holder_id'] as String?,
      lastLogEntryId: map['last_log_entry_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'sn': sn,
    'name': name,
    'current_status': itemStatusToString(currentStatus),
    'current_holder_id': currentHolderId,
    'last_log_entry_id': lastLogEntryId,
  };
}
