// log_book_screen.dart
// -----------------------------------------------------------------------------
// Read-only view of every log entry, formatted like a physical log book
// page: LOG number, date, keterangan, barang keluar, then the keluar and
// masuk handover lines. Newest entry first.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../models/item.dart';
import '../models/log_entry.dart';
import '../models/personel.dart';
import '../services/logistics_repository.dart';
import '../theme.dart';

class LogBookScreen extends StatefulWidget {
  const LogBookScreen({super.key});

  @override
  State<LogBookScreen> createState() => _LogBookScreenState();
}

class _LogBookScreenState extends State<LogBookScreen> {
  final LogisticsRepository _repo = LogisticsRepository();

  static String _formatDate(DateTime d) => '${d.day}-${d.month}-${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RedLineColors.background,
      appBar: AppBar(title: const Text('REDLINE // LOG BOOK')),
      body: StreamBuilder<List<Personel>>(
        stream: _repo.watchAllPersonel(),
        builder: (context, personelSnap) {
          final personelById = {
            for (final p in personelSnap.data ?? const <Personel>[]) p.id: p,
          };
          return StreamBuilder<List<Item>>(
            stream: _repo.watchAllItems(),
            builder: (context, itemSnap) {
              final itemById = {
                for (final i in itemSnap.data ?? const <Item>[]) i.id: i,
              };
              return StreamBuilder<List<LogEntry>>(
                stream: _repo.watchAllLogEntries(),
                builder: (context, logSnap) {
                  if (!logSnap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: RedLineColors.accent));
                  }
                  final entries = logSnap.data!;
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text(
                        'NO LOG ENTRIES YET',
                        style: TextStyle(fontFamily: kTerminalFontFamily, color: RedLineColors.textMuted, fontSize: 13),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 28, color: RedLineColors.accentDim),
                    itemBuilder: (context, index) => _LogEntryCard(
                      entry: entries[index],
                      personelById: personelById,
                      itemById: itemById,
                      formatDate: _formatDate,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({
    required this.entry,
    required this.personelById,
    required this.itemById,
    required this.formatDate,
  });

  final LogEntry entry;
  final Map<String, Personel> personelById;
  final Map<String, Item> itemById;
  final String Function(DateTime) formatDate;

  String _name(String? id) => id == null ? '—' : (personelById[id]?.name ?? id);

  static const _labelStyle = TextStyle(
    fontFamily: kTerminalFontFamily,
    color: RedLineColors.textMuted,
    fontSize: 11,
    letterSpacing: 0.5,
  );

  static const _valueStyle = TextStyle(
    fontFamily: kTerminalFontFamily,
    color: RedLineColors.accent,
    fontSize: 13,
  );

  @override
  Widget build(BuildContext context) {
    final itemNames = entry.itemIds.map((id) => itemById[id]?.name ?? id).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'LOG ${entry.formattedLogNumber}',
              style: const TextStyle(
                fontFamily: kTerminalFontFamily,
                color: RedLineColors.accent,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: entry.isReturned ? RedLineColors.accentDim : RedLineColors.accent),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.isReturned ? 'CLOSED' : 'OPEN',
                style: TextStyle(
                  fontFamily: kTerminalFontFamily,
                  color: entry.isReturned ? RedLineColors.textMuted : RedLineColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(formatDate(entry.date), style: _labelStyle),
        const SizedBox(height: 8),
        const Text('KETERANGAN', style: _labelStyle),
        Text(entry.keterangan, style: _valueStyle),
        const SizedBox(height: 8),
        const Text('BARANG KELUAR', style: _labelStyle),
        Text(itemNames, style: _valueStyle),
        const SizedBox(height: 8),
        const Text('KELUAR', style: _labelStyle),
        Text(
          'DISERAHKAN: ${_name(entry.keluarDiserahkanId)}   DITERIMA: ${_name(entry.keluarDiterimaId)}',
          style: _valueStyle,
        ),
        const SizedBox(height: 8),
        const Text('MASUK', style: _labelStyle),
        Text(
          entry.isReturned
              ? 'DISERAHKAN: ${_name(entry.masukDiserahkanId)}   DITERIMA: ${_name(entry.masukDiterimaId)}  (${formatDate(entry.masukDate!)})'
              : 'DISERAHKAN: —   DITERIMA: —',
          style: _valueStyle,
        ),
      ],
    );
  }
}