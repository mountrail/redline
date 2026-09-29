// logistics_screen.dart
// -----------------------------------------------------------------------------
// Item list for the logistics module. Talks to local storage ONLY through
// LogisticsRepository — no Hive/Firestore calls in this file.
//
// Tapping an in-store item opens a NEW LOG ENTRY dialog: it can cover that
// one item or several (multi-select), with one keterangan, one keluar
// handover. Tapping an out item finds the log entry currently covering it
// (item.lastLogEntryId) and opens a CLOSE LOG ENTRY dialog for it.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../models/item.dart';
import '../models/log_entry.dart';
import '../models/personel.dart';
import '../services/logistics_repository.dart';
import '../theme.dart';
import 'log_book_screen.dart';

class LogisticsScreen extends StatefulWidget {
  const LogisticsScreen({super.key});

  @override
  State<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends State<LogisticsScreen> {
  final LogisticsRepository _repo = LogisticsRepository();

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: kTerminalFontFamily, fontSize: 13),
        ),
        backgroundColor: isError
            ? RedLineColors.accentDim
            : RedLineColors.background,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RedLineColors.background,
      appBar: AppBar(
        title: const Text('REDLINE // LOGISTICS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book, color: RedLineColors.accent),
            tooltip: 'LOG BOOK',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LogBookScreen())),
          ),
          PopupMenuButton<String>(
            color: RedLineColors.background,
            icon: const Icon(Icons.add, color: RedLineColors.accent),
            onSelected: (value) {
              if (value == 'item') _openAddItemDialog();
              if (value == 'personel') _openAddPersonelDialog();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'item',
                child: Text(
                  'ADD ITEM',
                  style: TextStyle(
                    fontFamily: kTerminalFontFamily,
                    color: RedLineColors.accent,
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'personel',
                child: Text(
                  'ADD PERSONEL',
                  style: TextStyle(
                    fontFamily: kTerminalFontFamily,
                    color: RedLineColors.accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Personel>>(
        stream: _repo.watchAllPersonel(),
        builder: (context, personelSnap) {
          if (personelSnap.hasError)
            return _ErrorMessage(error: personelSnap.error);
          final personelList = personelSnap.data ?? const <Personel>[];
          final personelById = {for (final p in personelList) p.id: p};

          return StreamBuilder<List<Item>>(
            stream: _repo.watchAllItems(),
            builder: (context, itemSnap) {
              if (itemSnap.hasError)
                return _ErrorMessage(error: itemSnap.error);
              if (!itemSnap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: RedLineColors.accent),
                );
              }
              final items = itemSnap.data!;
              if (items.isEmpty) {
                return const Center(
                  child: Text(
                    'NO ITEMS REGISTERED\nTAP + TO ADD ONE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: kTerminalFontFamily,
                      color: RedLineColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: RedLineColors.accentDim),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final holder = item.currentHolderId == null
                      ? null
                      : personelById[item.currentHolderId];
                  return _ItemRow(
                    item: item,
                    holderName: holder?.name,
                    onTap: () => _handleItemTap(item, items, personelList),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _handleItemTap(
    Item item,
    List<Item> allItems,
    List<Personel> personelList,
  ) async {
    if (personelList.length < 2) {
      _showSnack('ADD AT LEAST 2 PERSONEL FIRST.', isError: true);
      return;
    }

    if (item.currentStatus == ItemStatus.inStore) {
      final inStoreItems = allItems
          .where((i) => i.currentStatus == ItemStatus.inStore)
          .toList();
      final result = await showDialog<_NewLogEntryResult>(
        context: context,
        builder: (_) => _NewLogEntryDialog(
          inStoreItems: inStoreItems,
          personelList: personelList,
          preSelectedItemId: item.id,
        ),
      );
      if (result == null) return;
      try {
        final id = await _repo.createLogEntry(
          itemIds: result.itemIds,
          keterangan: result.keterangan,
          keluarDiserahkanId: result.keluarDiserahkanId,
          keluarDiterimaId: result.keluarDiterimaId,
        );
        final entry = _repo.getLogEntry(id);
        _showSnack('LOG ${entry?.formattedLogNumber ?? ''} CREATED.');
      } catch (e) {
        _showSnack(e.toString(), isError: true);
      }
      return;
    }

    // Item is OUT — find and close the log entry covering it.
    final entryId = item.lastLogEntryId;
    final entry = entryId == null ? null : _repo.getLogEntry(entryId);
    if (entry == null) {
      _showSnack('NO OPEN LOG ENTRY FOUND FOR THIS ITEM.', isError: true);
      return;
    }
    final result = await showDialog<_CloseLogEntryResult>(
      context: context,
      builder: (_) =>
          _CloseLogEntryDialog(logEntry: entry, personelList: personelList),
    );
    if (result == null) return;
    try {
      await _repo.closeLogEntry(
        logEntryId: entry.id,
        masukDiserahkanId: result.masukDiserahkanId,
        masukDiterimaId: result.masukDiterimaId,
      );
      _showSnack('LOG ${entry.formattedLogNumber} CLOSED.');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _openAddItemDialog() async {
    final result = await showDialog<_AddItemResult>(
      context: context,
      builder: (_) => const _AddItemDialog(),
    );
    if (result == null) return;
    try {
      await _repo.createItem(sn: result.sn, name: result.name);
      _showSnack('ITEM ADDED.');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _openAddPersonelDialog() async {
    final result = await showDialog<_AddPersonelResult>(
      context: context,
      builder: (_) => const _AddPersonelDialog(),
    );
    if (result == null) return;
    try {
      await _repo.createPersonel(
        nrp: result.nrp,
        name: result.name,
        satuanKerja: result.satuanKerja,
        phone: result.phone,
      );
      _showSnack('PERSONEL ADDED.');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Error display — shown instead of spinning forever if a stream fails.
// ---------------------------------------------------------------------------

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'ERROR LOADING DATA:\n$error',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: kTerminalFontFamily,
            color: RedLineColors.accent,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item row
// ---------------------------------------------------------------------------

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.holderName,
    required this.onTap,
  });

  final Item item;
  final String? holderName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOut = item.currentStatus == ItemStatus.out;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontFamily: kTerminalFontFamily,
                      color: RedLineColors.accent,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.sn == null ? 'SN: —' : 'SN: ${item.sn}',
                    style: const TextStyle(
                      fontFamily: kTerminalFontFamily,
                      color: RedLineColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  if (isOut && holderName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'WITH: $holderName',
                      style: const TextStyle(
                        fontFamily: kTerminalFontFamily,
                        color: RedLineColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isOut ? RedLineColors.accent : RedLineColors.accentDim,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isOut ? 'OUT' : 'IN STORE',
                style: TextStyle(
                  fontFamily: kTerminalFontFamily,
                  color: isOut ? RedLineColors.accent : RedLineColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared dialog chrome
// ---------------------------------------------------------------------------

class _RedLineDialog extends StatelessWidget {
  const _RedLineDialog({
    required this.title,
    required this.children,
    required this.onSubmit,
    this.submitLabel = 'CONFIRM',
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSubmit;
  final String submitLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: RedLineColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: RedLineColors.accentDim),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: kTerminalFontFamily,
                color: RedLineColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      fontFamily: kTerminalFontFamily,
                      color: RedLineColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onSubmit,
                  child: Text(
                    submitLabel,
                    style: const TextStyle(
                      fontFamily: kTerminalFontFamily,
                      color: RedLineColors.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration(String label) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(
    fontFamily: kTerminalFontFamily,
    color: RedLineColors.textMuted,
    fontSize: 12,
  ),
  enabledBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: RedLineColors.accentDim),
  ),
  focusedBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: RedLineColors.accent),
  ),
);

const TextStyle _fieldTextStyle = TextStyle(
  fontFamily: kTerminalFontFamily,
  color: RedLineColors.accent,
  fontSize: 14,
);

// ---------------------------------------------------------------------------
// Add item / Add personel
// ---------------------------------------------------------------------------

class _AddItemResult {
  final String name;
  final String? sn;
  const _AddItemResult({required this.name, this.sn});
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog();
  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _nameController = TextEditingController();
  final _snController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _snController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final sn = _snController.text.trim();
    Navigator.of(context)
        .pop(_AddItemResult(name: name, sn: sn.isEmpty ? null : sn));
  }

  @override
  Widget build(BuildContext context) {
    return _RedLineDialog(
      title: 'ADD ITEM',
      submitLabel: 'ADD',
      onSubmit: _submit,
      children: [
        TextField(
          controller: _nameController,
          style: _fieldTextStyle,
          decoration: _fieldDecoration('NAME'),
          autofocus: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _snController,
          style: _fieldTextStyle,
          decoration: _fieldDecoration('SERIAL NUMBER (OPTIONAL)'),
        ),
      ],
    );
  }
}

class _AddPersonelResult {
  final String name;
  final String satuanKerja;
  final String? nrp;
  final String? phone;
  const _AddPersonelResult({
    required this.name,
    required this.satuanKerja,
    this.nrp,
    this.phone,
  });
}

class _AddPersonelDialog extends StatefulWidget {
  const _AddPersonelDialog();
  @override
  State<_AddPersonelDialog> createState() => _AddPersonelDialogState();
}

class _AddPersonelDialogState extends State<_AddPersonelDialog> {
  final _nameController = TextEditingController();
  final _satuanController = TextEditingController();
  final _nrpController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _satuanController.dispose();
    _nrpController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final satuan = _satuanController.text.trim();
    if (name.isEmpty || satuan.isEmpty) return;
    final nrp = _nrpController.text.trim();
    final phone = _phoneController.text.trim();
    Navigator.of(context).pop(
      _AddPersonelResult(
        name: name,
        satuanKerja: satuan,
        nrp: nrp.isEmpty ? null : nrp,
        phone: phone.isEmpty ? null : phone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RedLineDialog(
      title: 'ADD PERSONEL',
      submitLabel: 'ADD',
      onSubmit: _submit,
      children: [
        TextField(
          controller: _nameController,
          style: _fieldTextStyle,
          decoration: _fieldDecoration('NAME'),
          autofocus: true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _satuanController,
          style: _fieldTextStyle,
          decoration: _fieldDecoration('SATUAN KERJA'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nrpController,
          style: _fieldTextStyle,
          decoration: _fieldDecoration('NRP (OPTIONAL)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          style: _fieldTextStyle,
          decoration: _fieldDecoration('PHONE (OPTIONAL)'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// New log entry (barang keluar) — multi-item select
// ---------------------------------------------------------------------------

class _NewLogEntryResult {
  final List<String> itemIds;
  final String keterangan;
  final String keluarDiserahkanId;
  final String keluarDiterimaId;
  const _NewLogEntryResult({
    required this.itemIds,
    required this.keterangan,
    required this.keluarDiserahkanId,
    required this.keluarDiterimaId,
  });
}

class _NewLogEntryDialog extends StatefulWidget {
  const _NewLogEntryDialog({
    required this.inStoreItems,
    required this.personelList,
    this.preSelectedItemId,
  });
  final List<Item> inStoreItems;
  final List<Personel> personelList;
  final String? preSelectedItemId;

  @override
  State<_NewLogEntryDialog> createState() => _NewLogEntryDialogState();
}

class _NewLogEntryDialogState extends State<_NewLogEntryDialog> {
  late Set<String> _selectedItemIds;
  final _keteranganController = TextEditingController();
  String? _diserahkanId;
  String? _diterimaId;

  @override
  void initState() {
    super.initState();
    _selectedItemIds = {
      if (widget.preSelectedItemId != null) widget.preSelectedItemId!,
    };
  }

  @override
  void dispose() {
    _keteranganController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedItemIds.isEmpty ||
        _diserahkanId == null ||
        _diterimaId == null)
      return;
    final keterangan = _keteranganController.text.trim();
    if (keterangan.isEmpty) return;
    Navigator.of(context).pop(
      _NewLogEntryResult(
        itemIds: _selectedItemIds.toList(),
        keterangan: keterangan,
        keluarDiserahkanId: _diserahkanId!,
        keluarDiterimaId: _diterimaId!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RedLineDialog(
      title: 'LOG BARU — BARANG KELUAR',
      submitLabel: 'SAVE',
      onSubmit: _submit,
      children: [
        const Text(
          'ITEMS',
          style: TextStyle(
            fontFamily: kTerminalFontFamily,
            color: RedLineColors.textMuted,
            fontSize: 11,
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: StatefulBuilder(
            builder: (context, setLocalState) => ListView(
              shrinkWrap: true,
              children: [
                for (final item in widget.inStoreItems)
                  CheckboxListTile(
                    dense: true,
                    activeColor: RedLineColors.accent,
                    checkColor: Colors.black,
                    title: Text(item.name, style: _fieldTextStyle),
                    value: _selectedItemIds.contains(item.id),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _selectedItemIds.add(item.id);
                      } else {
                        _selectedItemIds.remove(item.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keteranganController,
          style: _fieldTextStyle,
          maxLines: 2,
          decoration: _fieldDecoration('KETERANGAN'),
        ),
        const SizedBox(height: 12),
        _PersonelDropdown(
          label: 'KELUAR — DISERAHKAN',
          personelList: widget.personelList,
          value: _diserahkanId,
          onChanged: (v) => setState(() => _diserahkanId = v),
        ),
        const SizedBox(height: 12),
        _PersonelDropdown(
          label: 'KELUAR — DITERIMA',
          personelList: widget.personelList,
          value: _diterimaId,
          onChanged: (v) => setState(() => _diterimaId = v),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Close log entry (barang masuk)
// ---------------------------------------------------------------------------

class _CloseLogEntryResult {
  final String masukDiserahkanId;
  final String masukDiterimaId;
  const _CloseLogEntryResult({
    required this.masukDiserahkanId,
    required this.masukDiterimaId,
  });
}

class _CloseLogEntryDialog extends StatefulWidget {
  const _CloseLogEntryDialog({
    required this.logEntry,
    required this.personelList,
  });
  final LogEntry logEntry;
  final List<Personel> personelList;

  @override
  State<_CloseLogEntryDialog> createState() => _CloseLogEntryDialogState();
}

class _CloseLogEntryDialogState extends State<_CloseLogEntryDialog> {
  String? _diserahkanId;
  String? _diterimaId;

  @override
  void initState() {
    super.initState();
    // Whoever received the item(s) going out is, by default, who's
    // handing them back — just a sensible starting guess, still editable.
    _diserahkanId = widget.logEntry.keluarDiterimaId;
  }

  void _submit() {
    if (_diserahkanId == null || _diterimaId == null) return;
    Navigator.of(context).pop(
      _CloseLogEntryResult(
        masukDiserahkanId: _diserahkanId!,
        masukDiterimaId: _diterimaId!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RedLineDialog(
      title: 'CLOSE LOG ${widget.logEntry.formattedLogNumber} — BARANG MASUK',
      submitLabel: 'SAVE',
      onSubmit: _submit,
      children: [
        _PersonelDropdown(
          label: 'MASUK — DISERAHKAN',
          personelList: widget.personelList,
          value: _diserahkanId,
          onChanged: (v) => setState(() => _diserahkanId = v),
        ),
        const SizedBox(height: 12),
        _PersonelDropdown(
          label: 'MASUK — DITERIMA',
          personelList: widget.personelList,
          value: _diterimaId,
          onChanged: (v) => setState(() => _diterimaId = v),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared personel dropdown
// ---------------------------------------------------------------------------

class _PersonelDropdown extends StatelessWidget {
  const _PersonelDropdown({
    required this.label,
    required this.personelList,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<Personel> personelList;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: _fieldDecoration(label),
      dropdownColor: RedLineColors.background,
      style: _fieldTextStyle,
      items: [
        for (final p in personelList)
          DropdownMenuItem(
            value: p.id,
            child: Text(p.name, style: _fieldTextStyle),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
