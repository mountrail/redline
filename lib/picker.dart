import 'package:flutter/material.dart';

import 'theme.dart';

Widget searchField(ValueChanged<String> onChanged, {bool autofocus = false}) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        autofocus: autofocus,
        onChanged: onChanged,
        cursorColor: kRed,
        decoration: const InputDecoration(
          hintText: 'SEARCH...',
          prefixIcon: Icon(Icons.search, color: kDim),
          border: OutlineInputBorder(borderSide: BorderSide(color: kDim)),
          isDense: true,
        ),
      ),
    );

/// Compact edit / delete icon pair used on every list row and detail screen.
Widget actionButtons({VoidCallback? onEdit, VoidCallback? onDelete}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (onEdit != null)
      IconButton(
        icon: const Icon(Icons.edit, size: 20),
        tooltip: 'Edit',
        visualDensity: VisualDensity.compact,
        onPressed: onEdit,
      ),
    if (onDelete != null)
      IconButton(
        icon: const Icon(Icons.delete_outline, size: 22, color: kRed),
        tooltip: 'Delete',
        visualDensity: VisualDensity.compact,
        onPressed: onDelete,
      ),
  ],
);

/// "Are you sure?" dialog. Returns true when the user confirms.
Future<bool> confirmDelete(
  BuildContext c,
  String message, {
  String? warning,
}) async {
  final ok = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: const Text('DELETE?'),
      content: Text(warning == null ? message : '$message\n\n$warning'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('DELETE'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Runs [f]; on error shows the message in a snackbar. Returns success.
Future<bool> runGuarded(BuildContext c, Future<void> Function() f) async {
  try {
    await f();
    return true;
  } catch (e) {
    if (c.mounted) {
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('$e')));
    }
    return false;
  }
}

/// Full-screen "search, or add new" picker. Pops with the chosen id.
/// [options] are (id, title, subtitle). [onAdd] opens the add-new screen and
/// returns the new id (or null if cancelled).
class SearchPicker extends StatefulWidget {
  const SearchPicker({
    super.key,
    required this.title,
    required this.options,
    required this.onAdd,
  });

  final String title;
  final List<(String, String, String)> options;
  final Future<String?> Function(BuildContext context, String query) onAdd;

  @override
  State<SearchPicker> createState() => _SearchPickerState();
}

class _SearchPickerState extends State<SearchPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final shown = widget.options
        .where((o) => '${o.$2} ${o.$3}'.toLowerCase().contains(q.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          searchField((v) => setState(() => _q = v), autofocus: true),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(q.isEmpty ? 'ADD NEW' : 'ADD NEW "$q"'),
                  onTap: () async {
                    final id = await widget.onAdd(context, q);
                    if (id != null && context.mounted)
                      Navigator.pop(context, id);
                  },
                ),
                const Divider(),
                for (final o in shown)
                  ListTile(
                    title: Text(o.$2),
                    subtitle: Text(o.$3, style: kLabel),
                    onTap: () => Navigator.pop(context, o.$1),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
