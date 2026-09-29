import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 'en' or 'id'. Saved in the meta box; first launch follows the phone.
final lang = ValueNotifier<String>(
  (Hive.box('meta').get('lang') as String?) ??
      (WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'id'
          ? 'id'
          : 'en'),
);

void toggleLang() {
  lang.value = lang.value == 'id' ? 'en' : 'id';
  Hive.box('meta').put('lang', lang.value);
}

/// English text is the key; only Indonesian is stored. Unknown -> unchanged.
String tr(String s) => lang.value == 'id' ? (_id[s] ?? s) : s;

const _id = {
  // menu / tabs
  'MAIN MENU': 'MENU UTAMA', 'LOGISTICS': 'LOGISTIK', 'PERSONNEL': 'PERSONEL',
  'LOG BOOK': 'BUKU LOG', 'ITEMS': 'BARANG', 'EMPTY': 'KOSONG',
  // common
  'SAVE': 'SIMPAN', 'CANCEL': 'BATAL', 'DELETE?': 'HAPUS?', 'DELETE': 'HAPUS',
  'Delete': 'Hapus', 'Edit': 'Edit', 'SEARCH...': 'CARI...', 'ADD': 'TAMBAH',
  'ADD NEW': 'TAMBAH BARU', 'ALL': 'SEMUA', 'CONFIRM': 'KONFIRMASI',
  'NONE': 'TIDAK ADA', 'COPIED': 'TERSALIN', 'Copy text': 'Salin teks',
  'TAP TO SELECT': 'KETUK UNTUK PILIH', 'SELECT ITEM': 'PILIH BARANG',
  'SELECT PERSON': 'PILIH PERSONEL', '(deleted)': '(dihapus)',
  'unit': 'unit', 'units': 'unit', 'IN STORE': 'DI GUDANG',
  // log
  'OPEN': 'TERBUKA', 'CLOSED': 'DITUTUP', 'OUT': 'KELUAR', 'IN': 'MASUK',
  'handed over by': 'diserahkan oleh', 'received by': 'diterima oleh',
  'HANDED OVER BY': 'DISERAHKAN OLEH', 'RECEIVED BY': 'DITERIMA OLEH',
  'HANDED BACK BY': 'DIKEMBALIKAN OLEH',
  'RECEIVED BACK BY': 'DITERIMA KEMBALI OLEH',
  'CLOSE LOG': 'TUTUP LOG', 'CLOSE LOG (RETURN)': 'TUTUP LOG (KEMBALI)',
  'EDIT LOG': 'EDIT LOG', 'NEW LOG': 'LOG BARU', 'SAVE LOG': 'SIMPAN LOG',
  'RETURNED': 'DIKEMBALIKAN', 'Description': 'Deskripsi',
  'Serial Number:': 'Nomor Seri:', 'Additional:': 'Tambahan:',
  'Its units will go back to store.': 'Unitnya akan kembali ke gudang.',
  'Pick both people': 'Pilih kedua orang',
  'Fill in the description, both people and at least one item':
      'Isi deskripsi, kedua orang, dan minimal satu barang',
  // items
  'ITEMS OUT': 'BARANG KELUAR', 'ADD ITEM': 'TAMBAH BARANG',
  'NEW ITEM': 'BARANG BARU', 'EDIT ITEM': 'EDIT BARANG',
  'Item name': 'Nama barang', 'ADDITIONAL ITEMS': 'BARANG TAMBAHAN',
  'ADDITIONAL ITEM': 'BARANG TAMBAHAN', 'Additional item': 'Barang tambahan',
  'ADD ADDITIONAL ITEM': 'TAMBAH BARANG TAMBAHAN',
  'EDIT ADDITIONAL ITEM': 'EDIT BARANG TAMBAHAN',
  'Delete additional item': 'Hapus barang tambahan',
  'e.g. Clipper': 'mis. Clipper', 'UNITS': 'UNIT', 'NO UNITS YET': 'BELUM ADA UNIT',
  'ADD UNITS': 'TAMBAH UNIT',
  'Serial numbers (comma separated)': 'Nomor seri (pisahkan koma)',
  'Or quantity without serial number': 'Atau jumlah tanpa nomor seri',
  'EDIT SERIAL NUMBER': 'EDIT NOMOR SERI', 'Serial number': 'Nomor seri',
  'Empty = no serial number': 'Kosong = tanpa nomor seri',
  'Its {} serial number(s) will be deleted too.':
      '{} nomor seri di dalamnya ikut terhapus.',
  'HOW MANY': 'JUMLAH', 'PICK UNITS': 'PILIH UNIT',
  'NO UNITS IN STORE. ADD UNITS FIRST.':
      'TIDAK ADA UNIT DI GUDANG. TAMBAH UNIT DULU.',
  'ALL ADDITIONAL ITEMS FOR EVERY UNIT':
      'SEMUA BARANG TAMBAHAN UNTUK SETIAP UNIT',
  'EVERY UNIT HAS THIS': 'SETIAP UNIT PUNYA INI',
  // people
  'NAME': 'NAMA', 'Name': 'Nama', 'UNIT': 'SATUAN KERJA', 'Unit': 'Satuan kerja',
  'PHONE': 'TELEPON', 'Phone number': 'Nomor telepon',
  'VIEW PHOTO': 'LIHAT FOTO', 'VIEW': 'LIHAT', 'PHOTO': 'FOTO',
  'CAMERA': 'KAMERA', 'GALLERY': 'GALERI', 'ADD PHOTO': 'TAMBAH FOTO',
  'CHANGE PHOTO': 'GANTI FOTO', 'NEW PERSON': 'PERSONEL BARU',
  'EDIT PERSON': 'EDIT PERSONEL',
  'Named in {} log(s). They will show "(deleted)" there.':
      'Tercantum di {} log. Akan tampil "(dihapus)" di sana.',
  // errors
  'Name is required': 'Nama wajib diisi',
  'NRP is already registered': 'NRP sudah terdaftar',
  'Duplicate additional item': 'Barang tambahan ganda',
  'Item name is required': 'Nama barang wajib diisi',
  'already exists': 'sudah ada', 'Already exists': 'Sudah ada',
  'Some units of this item are still out. Close their logs first.':
      'Sebagian unit barang ini masih keluar. Tutup lognya dulu.',
  'Enter a serial number or a quantity': 'Isi nomor seri atau jumlah',
  'This unit is out. Close its log first.':
      'Unit ini sedang keluar. Tutup lognya dulu.',
  'A selected unit is not in store': 'Unit terpilih tidak ada di gudang',
  'Description is required': 'Deskripsi wajib diisi',
};
