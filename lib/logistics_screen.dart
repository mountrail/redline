import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'data.dart';
import 'personel_screen.dart';
import 'picker.dart';
import 'theme.dart';

String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day}-${d.month}-${d.year}';
}

String _num(Map m) => m['log_number'].toString().padLeft(3, '0');

String _accText(Map acc) =>
    acc.entries.map((e) => '${e.key} x${e.value}').join(', ');

String _units(int n) => '$n ${n == 1 ? 'unit' : 'units'}';

List<(String, Map)> _all(Box<Map> b) => [
  for (final e in b.toMap().entries) (e.key as String, e.value),
];

/// One item type going out: the chosen serial numbers plus additional items.
class Line {
  const Line(this.typeId, this.unitIds, this.acc);
  final String typeId;
  final List<String> unitIds;
  final Map<String, int> acc;
}

// ================================================================ screen

class LogisticsScreen extends StatelessWidget {
  const LogisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('REDLINE // LOGISTICS'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'LOG BOOK'),
              Tab(text: 'ITEMS'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tab(
              source: Listenable.merge([
                Db.logs.listenable(),
                Db.people.listenable(),
                Db.types.listenable(),
                Db.units.listenable(),
              ]),
              rows: () => _all(Db.logs)
                ..sort(
                  (a, b) =>
                      (b.$2['log_number'] as int).compareTo(a.$2['log_number']),
                ),
              onAdd: (c) => Navigator.push(
                c,
                MaterialPageRoute(builder: (_) => const NewLogScreen()),
              ),
              row: _logRow,
            ),
            _tab(
              source: Listenable.merge([
                Db.types.listenable(),
                Db.units.listenable(),
              ]),
              rows: () => _all(Db.types)
                ..sort(
                  (a, b) => a.$2['name'].toString().toLowerCase().compareTo(
                    b.$2['name'].toString().toLowerCase(),
                  ),
                ),
              onAdd: _addItem,
              row: _typeRow,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _tab({
  required Listenable source,
  required List<(String, Map)> Function() rows,
  required void Function(BuildContext) onAdd,
  required Widget Function(BuildContext, String, Map) row,
}) {
  return Builder(
    builder: (c) => Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => onAdd(c),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: source,
        builder: (_, __) {
          final list = rows();
          if (list.isEmpty)
            return const Center(child: Text('EMPTY', style: kLabel));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 24),
            itemBuilder: (_, i) => row(c, list[i].$1, list[i].$2),
          );
        },
      ),
    ),
  );
}

// ============================================================ log book

/// Short summary row. Tap opens [LogDetail] with the full write-up.
Widget _logRow(BuildContext c, String id, Map m) {
  final open = m['back_from_id'] == null;
  final summary = [
    for (final l in Db.logLines(m))
      '${Db.lineName(l)} (${(l['unit_ids'] as List).length})',
  ].join(', ');
  return InkWell(
    onTap: () =>
        Navigator.push(c, MaterialPageRoute(builder: (_) => LogDetail(id: id))),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LOG ${_num(m)}  [${open ? 'OPEN' : 'CLOSED'}]',
                style: kBold,
              ),
              Text(_date(m['date']), style: kLabel),
              const SizedBox(height: 6),
              Text(m['note']),
              if (summary.isNotEmpty) Text(summary, style: kLabel),
              const SizedBox(height: 4),
              Text(
                'OUT: ${Db.name(m['from_id'])} -> ${Db.name(m['to_id'])}',
                style: kLabel,
              ),
            ],
          ),
        ),
        actionButtons(
          onEdit: () => _editLog(c, id),
          onDelete: () => _deleteLog(c, id),
        ),
      ],
    ),
  );
}

void _closeLog(BuildContext c, String id) {
  String? from, to;
  _dialog(
    c,
    'CLOSE LOG',
    (set) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PersonField(
          label: 'HANDED BACK BY',
          value: from,
          onPicked: (v) => set(() => from = v),
        ),
        PersonField(
          label: 'RECEIVED BY',
          value: to,
          onPicked: (v) => set(() => to = v),
        ),
      ],
    ),
    () async {
      if (from == null || to == null) throw 'Pick both people';
      await Db.closeLog(id, from!, to!);
    },
  );
}

void _editLog(BuildContext c, String id) {
  final m = Db.logs.get(id);
  if (m == null) return;
  final note = TextEditingController(text: m['note']);
  String from = m['from_id'], to = m['to_id'];
  String? backFrom = m['back_from_id'], backTo = m['back_to_id'];
  final closed = backFrom != null;
  _dialog(
    c,
    'EDIT LOG ${_num(m)}',
    (set) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(note, 'Description'),
        PersonField(
          label: 'HANDED OVER BY',
          value: from,
          onPicked: (v) => set(() => from = v),
        ),
        PersonField(
          label: 'RECEIVED BY',
          value: to,
          onPicked: (v) => set(() => to = v),
        ),
        if (closed) ...[
          PersonField(
            label: 'HANDED BACK BY',
            value: backFrom,
            onPicked: (v) => set(() => backFrom = v),
          ),
          PersonField(
            label: 'RECEIVED BACK BY',
            value: backTo,
            onPicked: (v) => set(() => backTo = v),
          ),
        ],
      ],
    ),
    () => Db.updateLog(
      id,
      note: note.text,
      fromId: from,
      toId: to,
      backFromId: backFrom,
      backToId: backTo,
    ),
  );
}

Future<bool> _deleteLog(BuildContext c, String id) async {
  final m = Db.logs.get(id);
  if (m == null) return false;
  final open = m['back_from_id'] == null;
  final ok = await confirmDelete(
    c,
    'Delete LOG ${_num(m)}?',
    warning: open ? 'Its units will go back to store.' : null,
  );
  if (!ok || !c.mounted) return false;
  return runGuarded(c, () => Db.deleteLog(id));
}

// ------------------------------------------------------- log write-up

Map _legacyAcc(Map m) =>
    m['lines'] == null ? ((m['acc'] as Map?) ?? const {}) : const {};

/// Plain-text version of a log (used by the copy button).
String _logText(Map m) {
  final b = StringBuffer('LOG ${_num(m)}\n${_date(m['date'])}\n${m['note']}\n');
  for (final l in Db.logLines(m)) {
    final sns = Db.lineSns(l);
    final acc = l['acc'] as Map;
    b.writeln('\n${Db.lineName(l)} (${_units(sns.length)})');
    b.writeln('Serial Number:');
    for (final s in sns) {
      b.writeln('* $s');
    }
    if (acc.isNotEmpty) {
      b.writeln('\nAdditional:');
      for (final e in acc.entries) {
        b.writeln('* ${e.key} (${e.value})');
      }
    }
  }
  final old = _legacyAcc(m);
  if (old.isNotEmpty) {
    b.writeln('\nAdditional:');
    for (final e in old.entries) {
      b.writeln('* ${e.key} (${e.value})');
    }
  }
  b.writeln(
    '\nOUT: diserahkan oleh ${Db.name(m['from_id'])} diterima oleh ${Db.name(m['to_id'])}.',
  );
  b.write(
    m['back_from_id'] == null
        ? 'IN: -'
        : 'IN: diserahkan oleh ${Db.name(m['back_from_id'])} diterima oleh ${Db.name(m['back_to_id'])}.',
  );
  return b.toString();
}

/// Underlined, tappable name that opens the person's info. Back returns here.
InlineSpan _link(BuildContext c, String? id) {
  final name = Db.name(id);
  if (id == null || !Db.people.containsKey(id)) return TextSpan(text: name);
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: GestureDetector(
      onTap: () => Navigator.push(
        c,
        MaterialPageRoute(builder: (_) => PersonDetail(id: id)),
      ),
      child: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  );
}

Widget _handover(BuildContext c, String tag, String? from, String? to) {
  if (from == null) return Text('$tag: -');
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '$tag: diserahkan oleh '),
        _link(c, from),
        const TextSpan(text: ' diterima oleh '),
        _link(c, to),
        const TextSpan(text: '.'),
      ],
    ),
  );
}

Widget _bullets(String title, List<String> items) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    const SizedBox(height: 8),
    Text(title),
    for (final s in items) Text('* $s'),
  ],
);

class LogDetail extends StatelessWidget {
  const LogDetail({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        Db.logs.listenable(),
        Db.people.listenable(),
        Db.types.listenable(),
        Db.units.listenable(),
      ]),
      builder: (ctx, _) {
        final m = Db.logs.get(id);
        if (m == null) return const Scaffold();
        final open = m['back_from_id'] == null;
        final old = _legacyAcc(m);
        return Scaffold(
          appBar: AppBar(
            title: Text('LOG ${_num(m)}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copy text',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _logText(m)));
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(const SnackBar(content: Text('COPIED')));
                },
              ),
              actionButtons(
                onEdit: () => _editLog(ctx, id),
                onDelete: () async {
                  if (await _deleteLog(ctx, id) && ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '[${open ? 'OPEN' : 'CLOSED'}]  ${_date(m['date'])}',
                style: kLabel,
              ),
              const SizedBox(height: 6),
              Text(m['note']),
              for (final l in Db.logLines(m)) ...[
                const Divider(height: 28),
                Text(
                  '${Db.lineName(l)} (${_units((l['unit_ids'] as List).length)})',
                  style: kBold,
                ),
                _bullets('Serial Number:', Db.lineSns(l)),
                if ((l['acc'] as Map).isNotEmpty)
                  _bullets('Additional:', [
                    for (final e in (l['acc'] as Map).entries)
                      '${e.key} (${e.value})',
                  ]),
              ],
              if (old.isNotEmpty) ...[
                const Divider(height: 28),
                _bullets('Additional:', [
                  for (final e in old.entries) '${e.key} (${e.value})',
                ]),
              ],
              const Divider(height: 28),
              _handover(ctx, 'OUT', m['from_id'], m['to_id']),
              const SizedBox(height: 6),
              _handover(ctx, 'IN', m['back_from_id'], m['back_to_id']),
              if (!open)
                Text('RETURNED ${_date(m['back_date'])}', style: kLabel),
              if (open) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => _closeLog(ctx, id),
                  child: const Text('CLOSE LOG (RETURN)'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ================================================================ items

Widget _typeRow(BuildContext c, String id, Map m) {
  final total = Db.units.values.where((u) => u['type_id'] == id).length;
  return InkWell(
    onTap: () => Navigator.push(
      c,
      MaterialPageRoute(builder: (_) => TypeScreen(typeId: id)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m['name'], style: kBold),
              Text(
                'IN STORE ${Db.freeUnits(id).length} / $total',
                style: kLabel,
              ),
            ],
          ),
        ),
        actionButtons(
          onEdit: () => Navigator.push(
            c,
            MaterialPageRoute(builder: (_) => TypeForm(id: id)),
          ),
          onDelete: () => _deleteType(c, id),
        ),
      ],
    ),
  );
}

Future<bool> _deleteType(BuildContext c, String id) async {
  final t = Db.types.get(id);
  if (t == null) return false;
  final n = Db.units.values.where((u) => u['type_id'] == id).length;
  final ok = await confirmDelete(
    c,
    'Delete "${t['name']}"?',
    warning: n == 0 ? null : 'Its $n serial number(s) will be deleted too.',
  );
  if (!ok || !c.mounted) return false;
  return runGuarded(c, () => Db.deleteType(id));
}

/// Search an item name, or add a new one (opens [TypeForm]). Returns the id.
Future<String?> pickType(BuildContext c) => Navigator.push<String>(
  c,
  MaterialPageRoute(
    builder: (_) => SearchPicker(
      title: 'SELECT ITEM',
      options: [
        for (final e in Db.types.toMap().entries)
          (
            e.key as String,
            e.value['name'] as String,
            'IN STORE: ${Db.freeUnits(e.key as String).length}',
          ),
      ],
      onAdd: (ctx, q) => Navigator.push<String>(
        ctx,
        MaterialPageRoute(builder: (_) => TypeForm(initialName: q)),
      ),
    ),
  ),
);

/// Items tab "+": pick or create the item name, then enter serial numbers.
Future<void> _addItem(BuildContext c) async {
  final typeId = await pickType(c);
  if (typeId != null && c.mounted) await addSn(c, typeId);
}

Future<void> addSn(BuildContext c, String typeId) {
  final ctl = TextEditingController();
  return _dialog(
    c,
    'ADD SERIAL NUMBERS',
    (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(Db.types.get(typeId)!['name'], style: kBold),
        _field(ctl, 'Serial numbers (comma separated)'),
      ],
    ),
    () => Db.addUnits(typeId, ctl.text.split(',')),
  );
}

void _editUnit(BuildContext c, String unitId) {
  final ctl = TextEditingController(text: Db.units.get(unitId)!['sn']);
  _dialog(
    c,
    'EDIT SERIAL NUMBER',
    (_) => _field(ctl, 'Serial number'),
    () => Db.updateUnit(unitId, ctl.text),
  );
}

Future<void> _deleteUnit(BuildContext c, String unitId) async {
  final u = Db.units.get(unitId);
  if (u == null) return;
  if (!await confirmDelete(c, 'Delete serial number "${u['sn']}"?')) return;
  if (c.mounted) await runGuarded(c, () => Db.deleteUnit(unitId));
}

/// Add ([index] null) or rename one additional item of a type.
void _editAcc(BuildContext c, String typeId, {int? index}) {
  final list = List<String>.from(
    Db.types.get(typeId)!['accessories'] ?? const [],
  );
  final ctl = TextEditingController(text: index == null ? '' : list[index]);
  _dialog(
    c,
    index == null ? 'ADD ADDITIONAL ITEM' : 'EDIT ADDITIONAL ITEM',
    (_) => _field(ctl, 'Additional item', hint: 'e.g. Clipper'),
    () async {
      final v = ctl.text.trim();
      if (v.isEmpty) throw 'Name is required';
      if (index == null) {
        list.add(v);
      } else {
        list[index] = v;
      }
      await Db.setAccessories(typeId, list);
    },
  );
}

Future<void> _deleteAcc(BuildContext c, String typeId, int index) async {
  final list = List<String>.from(
    Db.types.get(typeId)!['accessories'] ?? const [],
  );
  if (!await confirmDelete(c, 'Delete additional item "${list[index]}"?')) {
    return;
  }
  list.removeAt(index);
  if (c.mounted) await runGuarded(c, () => Db.setAccessories(typeId, list));
}

class TypeScreen extends StatelessWidget {
  const TypeScreen({super.key, required this.typeId});

  final String typeId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        Db.types.listenable(),
        Db.units.listenable(),
        Db.people.listenable(),
      ]),
      builder: (ctx, _) {
        final t = Db.types.get(typeId);
        if (t == null) return const Scaffold();
        final acc = List<String>.from(t['accessories'] ?? const []);
        final list =
            Db.units
                .toMap()
                .entries
                .where((e) => e.value['type_id'] == typeId)
                .toList()
              ..sort(
                (a, b) => a.value['sn'].toString().compareTo(
                  b.value['sn'].toString(),
                ),
              );
        return Scaffold(
          appBar: AppBar(
            title: Text(t['name']),
            actions: [
              actionButtons(
                onEdit: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => TypeForm(id: typeId)),
                ),
                onDelete: () async {
                  if (await _deleteType(ctx, typeId) && ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                },
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => addSn(ctx, typeId),
            child: const Icon(Icons.add),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('ADDITIONAL ITEMS', style: kLabel),
                  ),
                  TextButton.icon(
                    onPressed: () => _editAcc(ctx, typeId),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('ADD'),
                  ),
                ],
              ),
              if (acc.isEmpty) const Text('NONE', style: kLabel),
              for (var i = 0; i < acc.length; i++)
                Row(
                  children: [
                    Expanded(child: Text(acc[i])),
                    actionButtons(
                      onEdit: () => _editAcc(ctx, typeId, index: i),
                      onDelete: () => _deleteAcc(ctx, typeId, i),
                    ),
                  ],
                ),
              const Divider(height: 28),
              const Text('SERIAL NUMBERS', style: kLabel),
              const SizedBox(height: 4),
              if (list.isEmpty)
                const Text('NO SERIAL NUMBERS YET', style: kLabel),
              for (final e in list)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${e.value['sn']}   ${e.value['status'] == 'OUT' ? 'OUT -> ${Db.name(e.value['holder_id'])}' : 'IN STORE'}',
                      ),
                    ),
                    actionButtons(
                      onEdit: () => _editUnit(ctx, e.key as String),
                      onDelete: () => _deleteUnit(ctx, e.key as String),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Item name + its additional items (clipper, battery, ...). New or edit.
class TypeForm extends StatefulWidget {
  const TypeForm({super.key, this.id, this.initialName = ''});

  final String? id;
  final String initialName;

  @override
  State<TypeForm> createState() => _TypeFormState();
}

class _TypeFormState extends State<TypeForm> {
  late final Map? _old = widget.id == null ? null : Db.types.get(widget.id);
  late final _name = TextEditingController(
    text: _old?['name'] ?? widget.initialName,
  );
  late final _acc = <TextEditingController>[
    for (final a in (_old?['accessories'] as List? ?? const []))
      TextEditingController(text: '$a'),
  ];

  @override
  void dispose() {
    _name.dispose();
    for (final c in _acc) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final id = await Db.saveType(_name.text, [
        for (final c in _acc)
          if (c.text.trim().isNotEmpty) c.text.trim(),
      ], id: widget.id);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? 'NEW ITEM' : 'EDIT ITEM')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field(_name, 'Item name'),
          const SizedBox(height: 16),
          const Text('ADDITIONAL ITEMS', style: kLabel),
          for (var i = 0; i < _acc.length; i++)
            Row(
              children: [
                Expanded(
                  child: _field(
                    _acc[i],
                    'Additional item #${i + 1}',
                    hint: 'e.g. Clipper',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _acc.removeAt(i).dispose()),
                ),
              ],
            ),
          TextButton.icon(
            onPressed: () => setState(() => _acc.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: const Text('ADDITIONAL ITEM'),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('SAVE')),
        ],
      ),
    );
  }
}

// ============================================================== new log

class NewLogScreen extends StatefulWidget {
  const NewLogScreen({super.key});

  @override
  State<NewLogScreen> createState() => _NewLogScreenState();
}

class _NewLogScreenState extends State<NewLogScreen> {
  final _note = TextEditingController();
  final _lines = <Line>[];
  String? _from, _to;

  Set<String> get _used => {for (final l in _lines) ...l.unitIds};

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _addLine() async {
    final typeId = await pickType(context);
    if (typeId == null || !mounted) return;
    // A brand-new item name has no units yet: enter serial numbers first.
    if (Db.freeUnits(typeId, exclude: _used).isEmpty) {
      await addSn(context, typeId);
      if (!mounted) return;
    }
    final line = await Navigator.push<Line>(
      context,
      MaterialPageRoute(
        builder: (_) => TakeScreen(typeId: typeId, exclude: _used),
      ),
    );
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _save() async {
    try {
      if (_note.text.trim().isEmpty ||
          _from == null ||
          _to == null ||
          _lines.isEmpty) {
        throw 'Fill in the description, both people and at least one item';
      }
      // Same item added twice -> one block in the log.
      final units = <String, List<String>>{};
      final acc = <String, Map<String, int>>{};
      for (final l in _lines) {
        (units[l.typeId] ??= []).addAll(l.unitIds);
        final a = acc[l.typeId] ??= {};
        l.acc.forEach((k, v) => a[k] = (a[k] ?? 0) + v);
      }
      await Db.openLog(
        note: _note.text.trim(),
        fromId: _from!,
        toId: _to!,
        lines: [
          for (final e in units.entries)
            {'type_id': e.key, 'unit_ids': e.value, 'acc': acc[e.key]!},
        ],
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NEW LOG')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_note, 'Description'),
          PersonField(
            label: 'HANDED OVER BY',
            value: _from,
            onPicked: (v) => setState(() => _from = v),
          ),
          PersonField(
            label: 'RECEIVED BY',
            value: _to,
            onPicked: (v) => setState(() => _to = v),
          ),
          const Divider(height: 24),
          const Text('ITEMS OUT', style: kLabel),
          for (var i = 0; i < _lines.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(Db.lines(_lines[i].unitIds).first),
              subtitle: _lines[i].acc.isEmpty
                  ? null
                  : Text('+ ${_accText(_lines[i].acc)}'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _lines.removeAt(i)),
              ),
            ),
          TextButton.icon(
            onPressed: _addLine,
            icon: const Icon(Icons.add),
            label: const Text('ADD ITEM'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('SAVE LOG')),
        ],
      ),
    );
  }
}

/// Step 2 of adding an item to a log: how many, which serial numbers, and
/// which additional items go along. An additional item can be set to
/// "every unit" so its amount always equals the quantity. Pops with a [Line].
class TakeScreen extends StatefulWidget {
  const TakeScreen({super.key, required this.typeId, required this.exclude});

  final String typeId;
  final Set<String> exclude;

  @override
  State<TakeScreen> createState() => _TakeScreenState();
}

class _TakeScreenState extends State<TakeScreen> {
  late final _free = Db.freeUnits(widget.typeId, exclude: widget.exclude);
  late final _type = Db.types.get(widget.typeId)!;
  late final _names = List<String>.from(_type['accessories'] ?? const []);
  late final _ctl = {
    for (final n in _names) n: TextEditingController(text: '1'),
  };
  final _qtyCtl = TextEditingController();
  final _on = <String>{}; // additional items that go along
  final _each = <String>{}; // ...of which: one per unit (amount = quantity)
  final _sel = <String>[];
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    _pick(1);
    _setQtyText();
  }

  @override
  void dispose() {
    _qtyCtl.dispose();
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Sets the quantity and auto-selects the first [q] serial numbers.
  void _pick(int q) {
    _qty = _free.isEmpty
        ? 0
        : (q < 1 ? 1 : (q > _free.length ? _free.length : q));
    _sel
      ..clear()
      ..addAll(_free.take(_qty).map((e) => e.key as String));
  }

  void _setQtyText() {
    final t = '$_qty';
    _qtyCtl.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  void _setQty(int q) => setState(() {
    _pick(q);
    _setQtyText();
  });

  void _confirm() => Navigator.pop(
    context,
    Line(widget.typeId, List.of(_sel), {
      for (final n in _on)
        n: _each.contains(n) ? _qty : max(1, int.tryParse(_ctl[n]!.text) ?? 1),
    }),
  );

  @override
  Widget build(BuildContext context) {
    final ready =
        _qty > 0 && _sel.length == _qty && int.tryParse(_qtyCtl.text) == _qty;
    final allOn =
        _names.isNotEmpty &&
        _names.every((n) => _on.contains(n) && _each.contains(n));
    return Scaffold(
      appBar: AppBar(title: Text(_type['name'])),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('IN STORE: ${_free.length}', style: kLabel),
          if (_free.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('NO UNITS IN STORE. ADD SERIAL NUMBERS FIRST.'),
            )
          else ...[
            Row(
              children: [
                const Text('HOW MANY'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () => _setQty(_qty - 1),
                ),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _qtyCtl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: kBold,
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (v) {
                      final q = int.tryParse(v);
                      setState(() {
                        if (q != null) {
                          _pick(q);
                          if (_qty != q) _setQtyText();
                        }
                      });
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _setQty(_qty + 1),
                ),
                TextButton(
                  onPressed: () => _setQty(_free.length),
                  child: const Text('ALL'),
                ),
              ],
            ),
            const Divider(),
            Text('PICK SERIAL NUMBERS (${_sel.length}/$_qty)', style: kLabel),
            for (final e in _free)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.value['sn']),
                value: _sel.contains(e.key),
                onChanged: (v) => setState(() {
                  final id = e.key as String;
                  if (v == true) {
                    if (_sel.length < _qty) _sel.add(id);
                  } else {
                    _sel.remove(id);
                  }
                }),
              ),
          ],
          if (_names.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('ADDITIONAL ITEMS', style: kLabel),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('ALL ADDITIONAL ITEMS FOR EVERY UNIT (x$_qty)'),
              value: allOn,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _on.addAll(_names);
                  _each.addAll(_names);
                } else {
                  _on.clear();
                }
              }),
            ),
            for (final n in _names) ...[
              Row(
                children: [
                  Checkbox(
                    value: _on.contains(n),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _on.add(n);
                        _each.add(n);
                      } else {
                        _on.remove(n);
                      }
                    }),
                  ),
                  Expanded(child: Text(n)),
                  if (_on.contains(n))
                    _each.contains(n)
                        ? Text('x$_qty', style: kBold)
                        : SizedBox(
                            width: 64,
                            child: TextField(
                              controller: _ctl[n],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(isDense: true),
                            ),
                          ),
                ],
              ),
              if (_on.contains(n))
                Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text('EVERY UNIT HAS THIS (x$_qty)', style: kLabel),
                    value: _each.contains(n),
                    onChanged: (v) => setState(
                      () => v == true ? _each.add(n) : _each.remove(n),
                    ),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: ready ? _confirm : null,
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );
  }
}

// ============================================================== helpers

Widget _field(TextEditingController c, String label, {String? hint}) =>
    TextField(
      controller: c,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );

/// Small popup for quick actions (close log, add/edit serial numbers...).
/// Anything with search or several steps is a full screen instead.
Future<void> _dialog(
  BuildContext c,
  String title,
  Widget Function(StateSetter) body,
  Future<void> Function() onOk,
) {
  return showDialog(
    context: c,
    builder: (_) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: body(set)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            child: const Text('OK'),
            onPressed: () async {
              try {
                await onOk();
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('$e')));
                }
              }
            },
          ),
        ],
      ),
    ),
  );
}
