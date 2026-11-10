# Check-in, diary, review dan PDF

## Home dan halaman check-in referensi (2026-11-11)

- Home memiliki lima tahap: mood → obat → tidur → energi → kecemasan/iritabilitas. Total selalu5, termasuk obat tahap2; user telah mengonfirmasi. Pilihan balik dipertahankan dan nilai0 sah. Semua metrik dikirim sesuai pilihan, tanpa substitusi nilai tetap.
- `MoodEntryScreen` adalah route penuh, memakai waktu WIB aktual dan refresh pemanggil setelah save. `MedicationHistoryScreen` meminta seluruh log server dengan limit0, urutan terbaru dan kelompok tanggal WIB. Checklist hanya menyediakan tombol riwayat, tanpa list inline.
- Dosis memakai ID server dan stok/dosis nyata. Pending/temp ID dikunci. Jika antrean gagal ditulis, hapus insert yang belum durable; retry tidak mengirim ulang mood atau mengurangi stok lagi. Sinkronisasi log yang diterima server mengonfirmasi pending pada akun/generasi sama. Satu sync run membekukan owner/generasi dan berhenti sebelum item berikutnya setelah pergantian akun; finally melepas lock meski persist gagal.
- Sumber visual ada pada [rencana](../../../docs/superpowers/plans/2026-11-10-home-checkin-reference.md). Asset bunga/mood/baterai berasal dari referensi, bukan emoji font perangkat. Data orang, tanggal dan stok pada screenshot tidak menjadi data produksi.

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

- Wizard E-Prescription hanya untuk Sp.KJ terverifikasi dan pasien terhubung. Empat tahap: Detail Obat, Atur Rutinitas, pengingat konsumsi, pengingat isi ulang. Stok hanya di pengingat isi ulang dan tetap disimpan saat toggle notifikasi mati. Nama obat maupun diagnosis tidak boleh diisi dari contoh.
- `schedule` menyimpan `times`, `weekdays` (Senin=1 sampai Minggu=7), `start_at` dengan offset WIB, `interval_hours` / `interval_days` / `interval_months`, `units_per_dose` dan `refill_enabled`. Interval saling eksklusif; bulan opsional integer0–12 (omission=0), dihitung per bulan kalender dari anchor asli, clamp ke akhir bulan pendek. Jan31→Feb28→Mar31; bukan30hari.
- Fleksibel memakai `times: []`, interval0, hari1–7, tanggal mulai tengah malam WIB. Melewati halaman pengingat konsumsi; editor/hydration tidak membuat jam default, scheduler tidak membuat alarm konsumsi. Missing/null times berbeda dari explicit[] dan ditolak. Rutinitas terjadwal tetap wajib mempunyai jam/hari, dosis dan stok valid; refill terpisah dari alarm konsumsi.
- Khusus respons bulanan, API mengirim `times: []` dan `monthly_times` aktual serta mengosongkan `reminder_time` obat. Ini mencegah klien lama menjadwalkan harian setelah refresh. `MedicationSchedule.fromJson` hanya memulihkan `monthly_times` jika interval bulan positif, lalu `toJson` mengirim `times` kanonis tanpa key proyeksi. DB dan audit tidak berubah; edit bulanan memerlukan klien baru.
- Server membuat resep, item dan obat pasien dalam satu transaksi. Jadwal, bentuk, dosis, stok dan batas pengingat harus pulang-pergi utuh; jangan menyamakan semua resep bernama sama atau mengarang jadwal dari frekuensi bebas.
- Checklist mengurangi stok sesuai jumlah per dosis dengan hasil server. Pengingat lokal mengikuti rutinitas yang tersimpan; pengingat stok mematuhi toggle dan batas stok. Pengiriman notifikasi OS tetap bergantung pada izin/perangkat. Obat legacy dengan `schedule={}` mempertahankan kompatibilitas `reminder_time`.
- Migrasi 037 menambah `medications.schedule`, `e_prescription_items.schedule`, `current_stock` dan `alert_below` pada item resep. Sudah diterapkan di produksi pada rilis 0.1.14+15 sebelum backend baru dijalankan. Rujukan: [kontrak API](../../../docs/API_DOCUMENTATION.md), [skema](../../../docs/DATABASE_SCHEMA.md).
- CRUD resep: POST menerima `status` (`issued` default atau `draft`) dan `diagnosis`; PUT `/v1/e-prescriptions/{id}` mengganti isi penuh dengan ID item lama yang stabil; DELETE melakukan soft-delete. Mutasi hanya oleh psikiater terverifikasi penulis resep, pasien tidak dapat diganti. Draft hanya terbaca penulis; pasien dan verifikasi QR hanya melihat issued. Setiap simpan mengganti token QR; draft/delete membatalkan tanda tangan dan QR lama.
- `current_stock` item adalah jumlah pasokan resep, bukan stok berjalan. `remaining_stock` pada respons dihitung dari obat pasien. Edit memakai delta pasokan (pasokan 30, sisa 25, pasokan baru 40 → sisa 35), mempertahankan konsumsi/penyesuaian pasien. Kirim ID item lama saat edit; item baru tanpa ID. Draft, item dihapus dan resep dihapus menonaktifkan obat, mempertahankan medication logs dan audit.
- Instruksi per item disimpan pada `schedule.relation_to_meal` dan `schedule.instructions`; instruksi global hanya menjadi fallback bila keduanya kosong. Migrasi 039 menambah diagnosis/item active; 040 terpisah hanya memperbaiki stok nol dengan snapshot pasokan positif yang pasti, belum diedit/dikonsumsi dan relasi obat tunggal. Pasokan legacy nol tidak ditebak dari nama, durasi atau frekuensi. Keduanya diuji lokal dan telah diterapkan di produksi pada rilis 0.1.14+15.
