# Diary attachment editing implementation plan

**Goal:** pasien dapat membuka ulang PNG hasil draw untuk memperbaikinya dan mengganti foto melalui galeri dari editor diary.

**Architecture:** hasil draw lama dimuat secara terautentikasi sebagai raster dasar kanvas, dengan rasio asli dipertahankan. Pena/penghapus/rotasi serta undo/redo perubahan sesi berjalan memakai kanvas yang ada. Foto dipilih ulang melalui FilePickerPort. Unggah menghasilkan referensi baru yang menggantikan lampiran di posisi yang sama hanya setelah berhasil; tombol Simpan diary tetap menjadi titik penyimpanan record.

**Impact:** S/M, editor/preview/kanvas dan helper pembacaan media API klien beserta test. Tidak mengubah endpoint/DTO/skema/backend. Konten diary dan lampiran legacy kompatibel. Rancangan iOS yang belum disetujui tidak termasuk perubahan ini.

**Trade-off:** PNG tersimpan tidak memuat riwayat stroke sebelum disimpan. Pengguna dapat menggambar dan menghapus pixel gambar lama; undo/redo berlaku pada perubahan sesi edit ini. Tidak menambahkan format drawing/vector baru atau dependency baru.

## Global constraints

- Media privat hanya dimuat dari URL endpoint diary pada origin API yang sama, dengan autentikasi dan penjagaan generasi akun.
- Batal memilih, batal draw, gagal download/decode/upload tidak boleh menghapus/mengganti lampiran lama.
- Penggantian tetap dapat dilakukan saat enam slot penuh; tidak menambah jumlah atau mengubah urutan lampiran.
- Tidak menimpa berkas lama di server; diary lain/referensi lama tidak berubah.
- Kanvas dan preview ditutup melalui protectRoute yang sudah ada ketika akun berganti, termasuk A-B-A.
- Waktu WIB dan rilis mengikuti aturan repository; source/file desain iOS tidak ikut commit diary.

## Task 1 — Replace gallery photos and reopen drawings

- [x] Tambah widget test yang gagal pada aksi Ganti foto/Edit gambar yang belum tersedia.
- [x] Tambah callback edit opsional pada DiaryImage; editor menentukan mengganti foto atau mengedit draw.
- [x] Perluas upload dengan target penggantian, mempertahankan posisi dan lampiran lama sampai unggah valid selesai; cegah aksi ganda selama picker/draw/upload berlangsung.
- [x] Tambah fetchDiaryImage pada API client, validasi origin/path, tanpa redirect kredensial ke origin lain, batas ukuran, reuse refresh/auth-generation guard.
- [x] Kanvas menerima ui.Image awal dengan clone milik route, menggambar dasar di layer tinta yang dapat dihapus, menjaga rasio asli/rotasi/transparansi, membuang resource saat dispose.
- [x] Uji sukses, batal/gagal, enam lampiran, posisi penggantian, pembacaan privat, penggantian akun, dan pixel ekspor draw yang diedit.

## Task 2 — Verification and release

- [x] Jalankan suite Flutter penuh, analyzer, format dan gate WIB/platform; lakukan review independen.
- [x] Sinkronkan kontrak fitur/dokumentasi dan bump versi patch untuk APK.
- [ ] Commit/push dan buat PR; gabungkan hanya setelah gate wajib yang relevan lulus.
- [ ] Verifikasi deployment web/APK pada commit rilis, health backend, versi/tanda tangan/checksum APK unduhan publik; laporkan batas QA perangkat.
