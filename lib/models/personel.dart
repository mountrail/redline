// personel.dart
// -----------------------------------------------------------------------------
// Pure data class for a PERSONEL record. No storage calls live here beyond
// map conversion — reads/writes live in LogisticsRepository.
// -----------------------------------------------------------------------------

class Personel {
  /// Local store key — the internal `id` primary key. Never stored as a
  /// field inside the map itself.
  final String id;

  /// Real-world identifying attribute, NOT a relationship key. May be
  /// null — not every person has an NRP.
  final String? nrp;

  final String name;
  final String satuanKerja;
  final String? phone;

  const Personel({
    required this.id,
    this.nrp,
    required this.name,
    required this.satuanKerja,
    this.phone,
  });

  factory Personel.fromMap(String id, Map map) {
    return Personel(
      id: id,
      nrp: map['nrp'] as String?,
      name: map['name'] as String,
      satuanKerja: map['satuan_kerja'] as String,
      phone: map['phone'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'nrp': nrp,
    'name': name,
    'satuan_kerja': satuanKerja,
    'phone': phone,
  };
}
