import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'data.dart';
import 'picker.dart';
import 'theme.dart';

Widget _photoBox(Uint8List? bytes, double size) => Container(
  width: size,
  height: size,
  alignment: Alignment.center,
  decoration: BoxDecoration(
    border: Border.all(color: kDim),
    image: bytes == null
        ? null
        : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
  ),
  child: bytes == null ? Icon(Icons.person, size: size / 2, color: kDim) : null,
);

/// Full-screen photo with pinch-to-zoom.
class PhotoViewer extends StatelessWidget {
  const PhotoViewer({super.key, required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      ),
    );
  }
}

void _viewPhoto(BuildContext c, String title, Uint8List? bytes) {
  if (bytes == null) return;
  Navigator.push(
    c,
    MaterialPageRoute(builder: (_) => PhotoViewer(title: title, bytes: bytes)),
  );
}

Future<bool> deletePerson(BuildContext c, String id) async {
  if (!Db.people.containsKey(id)) return false;
  final refs = Db.personRefs(id);
  final ok = await confirmDelete(
    c,
    'Delete ${Db.name(id)}?',
    warning: refs == 0
        ? null
        : 'Named in $refs log(s). They will show "(deleted)" there.',
  );
  if (!ok || !c.mounted) return false;
  return runGuarded(c, () => Db.deletePerson(id));
}

// ------------------------------------------------------------------ list

class PersonelScreen extends StatefulWidget {
  const PersonelScreen({super.key});

  @override
  State<PersonelScreen> createState() => _PersonelScreenState();
}

class _PersonelScreenState extends State<PersonelScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('REDLINE // PERSONNEL')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PersonForm()),
        ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          searchField((v) => setState(() => _q = v)),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: Db.people.listenable(),
              builder: (_, __, ___) {
                final q = _q.trim().toLowerCase();
                final rows =
                    Db.people
                        .toMap()
                        .entries
                        .where(
                          (e) =>
                              '${e.value['name']} ${e.value['nrp'] ?? ''} ${e.value['satuan_kerja'] ?? ''}'
                                  .toLowerCase()
                                  .contains(q),
                        )
                        .toList()
                      ..sort(
                        (a, b) =>
                            a.value['name'].toString().toLowerCase().compareTo(
                              b.value['name'].toString().toLowerCase(),
                            ),
                      );
                if (rows.isEmpty)
                  return const Center(child: Text('EMPTY', style: kLabel));
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final p = rows[i].value;
                    final id = rows[i].key as String;
                    final photo = p['photo'] as Uint8List?;
                    return ListTile(
                      leading: GestureDetector(
                        onTap: () => _viewPhoto(context, p['name'], photo),
                        child: _photoBox(photo, 44),
                      ),
                      title: Text(p['name'], style: kBold),
                      subtitle: Text(
                        'NRP: ${p['nrp'] ?? '-'}  |  UNIT: ${p['satuan_kerja'] ?? '-'}',
                        style: kLabel,
                      ),
                      trailing: actionButtons(
                        onEdit: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PersonForm(id: id),
                          ),
                        ),
                        onDelete: () => deletePerson(context, id),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PersonDetail(id: id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- detail

class PersonDetail extends StatelessWidget {
  const PersonDetail({super.key, required this.id});

  final String id;

  Widget _info(String label, dynamic v) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: kLabel),
        Text(
          (v == null || '$v'.isEmpty) ? '-' : '$v',
          style: const TextStyle(fontSize: 16),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Db.people.listenable(keys: [id]),
      builder: (_, __, ___) {
        final p = Db.people.get(id);
        if (p == null) return const Scaffold(); // just deleted
        final photo = p['photo'] as Uint8List?;
        return Scaffold(
          appBar: AppBar(
            title: Text(p['name']),
            actions: [
              actionButtons(
                onEdit: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PersonForm(id: id)),
                ),
                onDelete: () async {
                  if (await deletePerson(context, id) && context.mounted) {
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: GestureDetector(
                  onTap: () => _viewPhoto(context, p['name'], photo),
                  child: _photoBox(photo, 160),
                ),
              ),
              if (photo != null)
                Center(
                  child: TextButton(
                    onPressed: () => _viewPhoto(context, p['name'], photo),
                    child: const Text('VIEW PHOTO'),
                  ),
                ),
              const SizedBox(height: 20),
              _info('NAME', p['name']),
              _info('NRP', p['nrp']),
              _info('UNIT', p['satuan_kerja']),
              _info('PHONE', p['phone']),
            ],
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ form

/// Add or edit a person. Pops with the saved id (used by the picker).
class PersonForm extends StatefulWidget {
  const PersonForm({super.key, this.id, this.initialName = ''});

  final String? id;
  final String initialName;

  @override
  State<PersonForm> createState() => _PersonFormState();
}

class _PersonFormState extends State<PersonForm> {
  late final Map _old = widget.id == null
      ? const {}
      : Db.people.get(widget.id)!;
  late final _name = TextEditingController(
    text: widget.id == null ? widget.initialName : _old['name'],
  );
  late final _nrp = TextEditingController(text: _old['nrp']);
  late final _unit = TextEditingController(text: _old['satuan_kerja']);
  late final _phone = TextEditingController(text: _old['phone']);
  late Uint8List? _photo = _old['photo'];

  @override
  void dispose() {
    for (final c in [_name, _nrp, _unit, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Picks a photo and shrinks it: max ~480px on the short side, JPEG,
  /// quality lowered step by step until the file is under 100 KB.
  Future<void> _pickPhoto() async {
    final src = await showDialog<ImageSource>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('PHOTO'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, ImageSource.camera),
            child: const Text('CAMERA'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, ImageSource.gallery),
            child: const Text('GALLERY'),
          ),
        ],
      ),
    );
    if (src == null) return;
    final file = await ImagePicker().pickImage(source: src);
    if (file == null) return;
    Uint8List? out;
    for (var q = 80; q >= 30; q -= 10) {
      out = await FlutterImageCompress.compressWithFile(
        file.path,
        minWidth: 480,
        minHeight: 480,
        quality: q,
      );
      if (out != null && out.length <= 100 * 1024) break;
    }
    if (out != null && mounted) setState(() => _photo = out);
  }

  Future<void> _save() async {
    try {
      final id = await Db.savePerson(
        id: widget.id,
        name: _name.text,
        nrp: _nrp.text,
        unit: _unit.text,
        phone: _phone.text,
        photo: _photo,
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _field(TextEditingController c, String label, [TextInputType? type]) =>
      TextField(
        controller: c,
        keyboardType: type,
        decoration: InputDecoration(labelText: label),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'NEW PERSON' : 'EDIT PERSON'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: _photoBox(_photo, 120),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _pickPhoto,
                child: Text(
                  _photo == null
                      ? 'ADD PHOTO'
                      : 'CHANGE PHOTO (${(_photo!.length / 1024).round()} KB)',
                ),
              ),
              if (_photo != null)
                TextButton(
                  onPressed: () => _viewPhoto(
                    context,
                    _name.text.isEmpty ? 'PHOTO' : _name.text,
                    _photo,
                  ),
                  child: const Text('VIEW'),
                ),
            ],
          ),
          _field(_name, 'Name'),
          _field(_nrp, 'NRP'),
          _field(_unit, 'Unit'),
          _field(_phone, 'Phone number', TextInputType.phone),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('SAVE')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- picker

/// Search a person, or add a new one (opens [PersonForm]). Returns the id.
Future<String?> pickPerson(BuildContext c) => Navigator.push<String>(
  c,
  MaterialPageRoute(
    builder: (_) => SearchPicker(
      title: 'SELECT PERSON',
      options: [
        for (final e in Db.people.toMap().entries)
          (
            e.key as String,
            e.value['name'] as String,
            'NRP: ${e.value['nrp'] ?? '-'}  |  ${e.value['satuan_kerja'] ?? '-'}',
          ),
      ],
      onAdd: (ctx, q) => Navigator.push<String>(
        ctx,
        MaterialPageRoute(builder: (_) => PersonForm(initialName: q)),
      ),
    ),
  ),
);

/// Tappable "who?" row: shows the chosen person, opens the picker on tap.
class PersonField extends StatelessWidget {
  const PersonField({
    super.key,
    required this.label,
    required this.value,
    required this.onPicked,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: kLabel),
      subtitle: Text(
        value == null ? 'TAP TO SELECT' : Db.name(value),
        style: const TextStyle(fontSize: 15),
      ),
      trailing: const Icon(Icons.search),
      onTap: () async {
        final id = await pickPerson(context);
        if (id != null) onPicked(id);
      },
    );
  }
}