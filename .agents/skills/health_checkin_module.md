# Check-in, diary, review dan PDF

- Mood tersimpan melalui `/v1/mood-checkins`; diary terpisah melalui
  `/v1/diary-entries`. Jangan menghapus mood lama saat membersihkan tampilan diary.
- `services/mood_insights.dart` menghitung streak per tanggal WIB, rata-rata
  harian combo chart dan radar. `widgets/mood_insights.dart` dipakai kedua role.
  Tanpa data bukan skor nol. Filter weekly/monthly/yearly/lifetime milik radar.
- Kalender/detail terikat pada ownerKey. Respons async harus menguji pemilik
  akun; rotasi token untuk identitas yang sama tetap sah.
- Medication checklist mengunci aksi per obat selama request; ID sementara
  menunggu create server. Tampilkan kegagalan melalui context layar yang aktif.
- Obat resep boleh tanpa pengingat. Kartu, form edit dan sinkronisasi tidak
  mengambil `.first` dari daftar kosong; tampilkan `Belum diatur` dan pertahankan
  `reminder_time` kosong sampai pasien memilih jam. Jangan membuat jadwal/aturan
  makan palsu saat refresh. Dialog checklist dapat discroll pada teks besar.
- Mini Summary dan ringkasan yang dibagikan menghitung tujuh tanggal WIB,
  termasuk hari ini; Last Diary Entry tidak ditampilkan. Diary chat dipilih
  pasien dari riwayat server, bukan otomatis entri terakhir. Recent mood maksimal
  tiga entri terbaru; filter periode tetap milik radar.
- Jam pengingat obat boleh kosong; form, kartu dan sinkronisasi tidak boleh
  mengambil `.first` pada daftar kosong atau membuat jam default saat refresh/edit.
  Obat tanpa jam tetap dapat diedit dan dicentang sesuai aturan yang ada.
- Mini Summary mencakup tujuh hari kalender WIB, tidak menampilkan diary terakhir.
  Mood Recent hanya tiga item. PDF menghapus kolom feedback/catatan yang diminta,
  menjaga teks diary dan grafik mood serta sumber data/server/consent yang sama.
- PDF dibuat `health_pdf_report.dart`, dipanggil More melalui ExportService.
  Mood/diary/log obat/screening memakai limit0 server; seluruh sumber yang diminta
  wajib berhasil. Tabel mengulang header, catatan panjang dipaginasi, emoji mood
  tertanam sebagai asset; combo/radar memakai data dan fungsi yang sama dengan UI.
- Ekspor diary memuat tanggal, judul dan isi diary, tanpa Catatan/Tanggapan
  profesional. Ekspor mood tanpa kolom Catatan, tetap memuat emoji dan chart.
- Screening PDF memakai scorer baku; WHO-5 tetap menyertakan follow-up item 0-1
  walau total tinggi. Warna adalah kategori hasil, bukan diagnosis.
- Ulasan tepat satu per sesi satu kali completed atau per seluruh paket selesai,
  bukan per pertemuan paket. Kuota pembelian paket harus completed/no_show, tanpa
  scheduled/pending dalam rentang itu dan minimal satu completed. Penggabungan
  4+4 tetap bersaldo 8 tetapi dua ID pembelian memberi dua hak terpisah; sesi
  pemakai kuota diurut kalender/id dan dibagi ke rentang pembelian awal/renewal.
  Renewal baru dapat diulas setelah semua pertemuan pemakai kuota sebelumnya
  terminal, sehingga kredit dari pembatalan profesional tidak menggeser range terpakai.
  Rantai merged, kuota atau ownership ambigu ditolak. `/v1/review-entitlements` terikat
  akun; POST lama tanpa ID dan POST baru dengan session_id/care_package_id sama-sama
  diperiksa atomik dan dilindungi index unik 035. Prompt setelah refresh/resume/poll
  tidak membuka dialog berulang per akun/unit selama sesi aplikasi; aksi manual
  tetap tersedia setelah ditutup. Legacy tetap terlihat tanpa tautan dugaan;
  unit berakhir pada/sebelum ulasan legacy terakhir pasangan ditekan konservatif.
  completed_at memakai akhir jadwal terminal yang stabil, bukan updated_at detail.
  Profil profesional hanya menampilkan ulasan pasien tersimpan, tanpa contoh/demo.
- Backfill lokasi praktik lama mengikat UUID profesional dan alamat praktik
  yang diketahui, tanpa menggantungkan identitas pada email login yang dapat
  berubah. Pertahankan koordinat yang sudah ada dan praktik/alamat yang berubah.
- Pengujian utama: mood_insights*, medication_checklist_ui, diary_separation,
  doctor_reviews_distance, health_export_server, health_pdf_report.

## Resep dan rutinitas obat (2026-11-10)

- Wizard E-Prescription hanya untuk Sp.KJ terverifikasi dan pasien terhubung. Alurnya memilih pasien, obat/bentuk/dosis/satuan, rutinitas WIB, lalu stok/pengingat dan penerbitan. Nama obat maupun diagnosis tidak boleh diisi dari contoh.
- `schedule` menyimpan `times`, `weekdays` (Senin=1 sampai Minggu=7), `start_at` dengan offset WIB, `interval_hours` atau `interval_days`, `units_per_dose` dan `refill_enabled`. Interval jam/hari tidak boleh aktif bersamaan; rutinitas baru harus mempunyai jam/hari, dosis dan stok yang valid.
- Server membuat resep, item dan obat pasien dalam satu transaksi. Jadwal, bentuk, dosis, stok dan batas pengingat harus pulang-pergi utuh; jangan menyamakan semua resep bernama sama atau mengarang jadwal dari frekuensi bebas.
- Checklist mengurangi stok sesuai jumlah per dosis dengan hasil server. Pengingat lokal mengikuti rutinitas yang tersimpan; pengingat stok mematuhi toggle dan batas stok. Pengiriman notifikasi OS tetap bergantung pada izin/perangkat. Obat legacy dengan `schedule={}` mempertahankan kompatibilitas `reminder_time`.
- Migrasi 037 menambah `medications.schedule`, `e_prescription_items.schedule`, `current_stock` dan `alert_below` pada item resep. Belum diterapkan produksi dalam pekerjaan ini; terapkan sebelum menjalankan backend baru. Rujukan: [kontrak API](../../../docs/API_DOCUMENTATION.md), [skema](../../../docs/DATABASE_SCHEMA.md).
