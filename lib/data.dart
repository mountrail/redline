import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart';

/// Local storage + logistics logic. Records are plain maps.
///
///  people : name, nrp, satuan_kerja (unit), phone, photo (jpeg bytes)
///  types  : name, accessories [String]            e.g. HT -> Clipper, Battery
///  units  : type_id, sn, status (IN_STORE/OUT), holder_id   one row per serial number
///  logs   : log_number, date, note, from_id, to_id, unit_ids,
///           lines [{type_id, type_name, unit_ids, sns, acc {name: qty}}],
///           back_date, back_from_id, back_to_id
///           (old logs have a single top-level `acc` instead of `lines`)
class Db {
  static late Box<Map> people, types, units, logs;
  static late Box meta;

  static Future<void> init() async {
    await Hive.initFlutter();
    people = await Hive.openBox<Map>('personel');
    types = await Hive.openBox<Map>('item_types');
    units = await Hive.openBox<Map>('item_units');
    logs = await Hive.openBox<Map>('log_book');
    meta = await Hive.openBox('meta');
  }

  static String _id() => DateTime.now().microsecondsSinceEpoch.toString();
  static String? _n(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  static String name(String? id) =>
      id == null ? '-' : (people.get(id)?['name'] ?? '(deleted)');

  // ------------------------------------------------------------ people

  static Future<String> savePerson({
    String? id,
    required String name,
    String? nrp,
    String? unit,
    String? phone,
    Uint8List? photo,
  }) async {
    if (name.trim().isEmpty) throw 'Name is required';
    final cleanNrp = _n(nrp);
    if (cleanNrp != null &&
        people.toMap().entries.any(
          (e) => e.key != id && e.value['nrp'] == cleanNrp,
        )) {
      throw 'NRP is already registered';
    }
    id ??= _id();
    await people.put(id, {
      'name': name.trim(),
      'nrp': cleanNrp,
      'satuan_kerja': _n(unit),
      'phone': _n(phone),
      'photo': photo,
    });
    return id;
  }

  /// Number of logs that mention this person.
  static int personRefs(String id) => logs.values
      .where(
        (l) =>
            l['from_id'] == id ||
            l['to_id'] == id ||
            l['back_from_id'] == id ||
            l['back_to_id'] == id,
      )
      .length;

  static Future<void> deletePerson(String id) => people.delete(id);

  // ------------------------------------------------------------- items

  static List<String> _cleanAcc(List<String> accessories) {
    final out = <String>[];
    final seen = <String>{};
    for (final a in accessories) {
      final t = a.trim();
      if (t.isEmpty) continue;
      if (!seen.add(t.toLowerCase())) throw 'Duplicate additional item: $t';
      out.add(t);
    }
    return out;
  }

  /// Creates a type, or updates it when [id] is given.
  static Future<String> saveType(
    String name,
    List<String> accessories, {
    String? id,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw 'Item name is required';
    final dup = types.toMap().entries.any(
      (e) =>
          e.key != id &&
          e.value['name'].toString().toLowerCase() == n.toLowerCase(),
    );
    if (dup) throw '"$n" already exists';
    final acc = _cleanAcc(accessories);
    id ??= _id();
    await types.put(id, {'name': n, 'accessories': acc});
    return id;
  }

  static Future<void> setAccessories(String typeId, List<String> acc) async {
    await saveType(types.get(typeId)!['name'], acc, id: typeId);
  }

  /// Deletes the type and all its serial numbers. Refuses while any is out.
  static Future<void> deleteType(String id) async {
    final mine = units
        .toMap()
        .entries
        .where((e) => e.value['type_id'] == id)
        .toList();
    if (mine.any((e) => e.value['status'] == 'OUT')) {
      throw 'Some units of this item are still out. Close their logs first.';
    }
    await units.deleteAll(mine.map((e) => e.key));
    await types.delete(id);
  }

  static Future<void> addUnits(String typeId, List<String> sns) async {
    final clean = {
      for (final s in sns)
        if (s.trim().isNotEmpty) s.trim(),
    };
    if (clean.isEmpty) throw 'Enter at least one serial number';
    final have = units.values
        .where((u) => u['type_id'] == typeId)
        .map((u) => u['sn'].toString().toLowerCase())
        .toSet();
    final dup = clean.where((s) => have.contains(s.toLowerCase()));
    if (dup.isNotEmpty) throw 'Already exists: ${dup.join(', ')}';
    var seed = DateTime.now().microsecondsSinceEpoch;
    for (final sn in clean) {
      await units.put('${seed++}', {
        'type_id': typeId,
        'sn': sn,
        'status': 'IN_STORE',
      });
    }
  }

  static Future<void> updateUnit(String id, String sn) async {
    final s = sn.trim();
    if (s.isEmpty) throw 'Serial number is required';
    final u = units.get(id)!;
    final dup = units.toMap().entries.any(
      (e) =>
          e.key != id &&
          e.value['type_id'] == u['type_id'] &&
          e.value['sn'].toString().toLowerCase() == s.toLowerCase(),
    );
    if (dup) throw 'Already exists: $s';
    await units.put(id, {...u, 'sn': s});
  }

  static Future<void> deleteUnit(String id) async {
    if (units.get(id)?['status'] == 'OUT') {
      throw 'This unit is out. Close its log first.';
    }
    await units.delete(id);
  }

  /// Units of [typeId] currently in store, sorted by serial number.
  static List<MapEntry<dynamic, Map>> freeUnits(
    String typeId, {
    Set<String> exclude = const {},
  }) {
    return units
        .toMap()
        .entries
        .where(
          (e) =>
              e.value['type_id'] == typeId &&
              e.value['status'] != 'OUT' &&
              !exclude.contains(e.key),
        )
        .toList()
      ..sort(
        (a, b) => a.value['sn'].toString().compareTo(b.value['sn'].toString()),
      );
  }

  /// "HT (2)  SN: ht001, ht002" — one line per item type.
  static List<String> lines(List unitIds) {
    final groups = <String, List<String>>{};
    for (final u in unitIds) {
      final m = units.get(u);
      if (m != null) (groups[m['type_id']] ??= []).add(m['sn']);
    }
    return [
      for (final e in groups.entries)
        '${types.get(e.key)?['name'] ?? '?'} (${e.value.length})  SN: ${e.value.join(', ')}',
    ];
  }

  // -------------------------------------------------------------- logs

  /// Normalised item lines of a log: {type_id, type_name, unit_ids, sns, acc}.
  /// Old logs (no `lines`) are rebuilt from their units, without additionals.
  static List<Map> logLines(Map log) {
    final raw = log['lines'] as List?;
    if (raw != null) {
      return [
        for (final l in raw)
          {
            'type_id': l['type_id'],
            'type_name': l['type_name'],
            'unit_ids': List<String>.from(l['unit_ids'] ?? const []),
            'sns': List<String>.from(l['sns'] ?? const []),
            'acc': Map<String, int>.from(l['acc'] ?? const {}),
          },
      ];
    }
    final groups = <String, List<String>>{};
    for (final u in (log['unit_ids'] as List? ?? const [])) {
      final m = units.get(u);
      if (m != null) (groups[m['type_id']] ??= []).add(u);
    }
    return [
      for (final e in groups.entries)
        {
          'type_id': e.key,
          'type_name': types.get(e.key)?['name'],
          'unit_ids': e.value,
          'sns': [for (final u in e.value) units.get(u)!['sn'].toString()],
          'acc': <String, int>{},
        },
    ];
  }

  static String lineName(Map l) =>
      (types.get(l['type_id'])?['name'] ?? l['type_name'] ?? '?').toString();

  /// Serial numbers of a line: live value if the unit exists, else snapshot.
  static List<String> lineSns(Map l) {
    final ids = l['unit_ids'] as List;
    final snap = l['sns'] as List;
    return [
      for (var i = 0; i < ids.length; i++)
        (units.get(ids[i])?['sn'] ?? (i < snap.length ? snap[i] : '?'))
            .toString(),
    ];
  }

  /// [lines]: [{type_id, unit_ids: List<String>, acc: Map<String,int>}]
  static Future<void> openLog({
    required String note,
    required String fromId,
    required String toId,
    required List<Map<String, dynamic>> lines,
  }) async {
    final all = [
      for (final l in lines) ...(l['unit_ids'] as List<String>),
    ];
    for (final u in all) {
      if (units.get(u)?['status'] != 'IN_STORE') {
        throw 'A selected unit is not in store';
      }
    }
    final stored = [
      for (final l in lines)
        {
          'type_id': l['type_id'],
          'type_name': types.get(l['type_id'])?['name'],
          'unit_ids': l['unit_ids'],
          'sns': [
            for (final u in l['unit_ids'] as List<String>) units.get(u)!['sn'],
          ],
          'acc': l['acc'],
        },
    ];
    final number = ((meta.get('log_counter') as int?) ?? 0) + 1;
    await meta.put('log_counter', number);
    final id = _id();
    await logs.put(id, {
      'log_number': number,
      'date': DateTime.now().millisecondsSinceEpoch,
      'note': note,
      'from_id': fromId,
      'to_id': toId,
      'unit_ids': all,
      'lines': stored,
    });
    for (final u in all) {
      await units.put(u, {
        ...units.get(u)!,
        'status': 'OUT',
        'holder_id': toId,
      });
    }
  }

  static Future<void> closeLog(String id, String fromId, String toId) async {
    final log = logs.get(id)!;
    await logs.put(id, {
      ...log,
      'back_date': DateTime.now().millisecondsSinceEpoch,
      'back_from_id': fromId,
      'back_to_id': toId,
    });
    for (final u in log['unit_ids']) {
      final unit = units.get(u);
      if (unit != null)
        await units.put(u, {...unit, 'status': 'IN_STORE', 'holder_id': null});
    }
  }

  /// Edits the note and the people of a log (return people only if closed).
  static Future<void> updateLog(
    String id, {
    required String note,
    required String fromId,
    required String toId,
    String? backFromId,
    String? backToId,
  }) async {
    if (note.trim().isEmpty) throw 'Description is required';
    final log = logs.get(id)!;
    final closed = log['back_from_id'] != null;
    await logs.put(id, {
      ...log,
      'note': note.trim(),
      'from_id': fromId,
      'to_id': toId,
      if (closed) 'back_from_id': backFromId ?? log['back_from_id'],
      if (closed) 'back_to_id': backToId ?? log['back_to_id'],
    });
    if (!closed) {
      for (final u in log['unit_ids']) {
        final unit = units.get(u);
        if (unit != null) await units.put(u, {...unit, 'holder_id': toId});
      }
    }
  }

  /// Deletes a log. An open log first puts its units back in store.
  static Future<void> deleteLog(String id) async {
    final log = logs.get(id);
    if (log == null) return;
    if (log['back_from_id'] == null) {
      for (final u in log['unit_ids']) {
        final unit = units.get(u);
        if (unit != null) {
          await units.put(u, {
            ...unit,
            'status': 'IN_STORE',
            'holder_id': null,
          });
        }
      }
    }
    await logs.delete(id);
  }
}