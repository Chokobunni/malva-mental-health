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
- PDF dibuat `health_pdf_report.dart`, dipanggil More melalui ExportService.
  Mood/diary/log obat/screening memakai limit0 server; seluruh sumber yang diminta
  wajib berhasil. Tabel mengulang header, catatan panjang dipaginasi, emoji mood
  tertanam sebagai asset; combo/radar memakai data dan fungsi yang sama dengan UI.
- Screening PDF memakai scorer baku; WHO-5 tetap menyertakan follow-up item 0-1
  walau total tinggi. Warna adalah kategori hasil, bukan diagnosis.
- Ulasan tersimpan hanya dari pasien dengan sesi completed. Contoh ditandai jelas,
  tidak disimpan sebagai ulasan pasien atau dihitung dalam agregat nyata.
- Pengujian utama: mood_insights*, medication_checklist_ui, diary_separation,
  doctor_reviews_distance, health_export_server, health_pdf_report.
