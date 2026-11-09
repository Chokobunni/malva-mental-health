# Skill: Screening Module (WHO-5 / PHQ-9 / GAD-7 / DASS-21)

## Gerbang awal WHO-5 (2026-11-07)

- Persetujuan -> 5 item WHO-5 wajib (0-5) -> simpan submission versi skala 2.
- Raw = jumlah (0-25), persen = raw x4. R2 diprioritaskan: persen <50 ATAU
  satu item 0-1 -> Butuh Skrining Lanjutan -> PHQ-9 + GAD-7 dengan CF lama.
- R1 berhenti hanya bila persen >=50 DAN seluruh item >=2. Kesimpulan WHO
  tidak membuat hasil PHQ/GAD palsu atau skor nol. DASS-21 tetap manual.
- WHO/DASS tetap memakai submission/berbagi dan consent yang sudah ada;
  PHQ/GAD dihitung ulang server. Tidak ada perubahan skema/DTO.
- CF adalah dukungan model yang belum dikalibrasi klinis. Penjelasan lengkap:
  [scoring dan alur](../../docs/SCREENING_SCORING.md).
- Riwayat assessment hanya memuat WHO/DASS dengan semua jawaban integer valid;
  submission lama yang kosong/parsial tidak dihitung sebagai tes selesai.
  Skip/back tidak menyimpan hasil. Simpan/bagikan ulang formulir yang sama
  menggunakan ID hasil tersimpan, dan pengiriman ID yang sama tampil sekali.
- Symptoms Assessment hanya ditawarkan pada respons pendaftaran pasien baru
  (Google HTTP 201 atau registrasi password), bukan login/restore akun lama.
  Tawaran dikonsumsi sebelum formulir dibuka; skip/back/restart tidak mengulang
  gerbang dan tidak membuat hasil screening. Keputusan tersimpan per akun.
- Tampilan pasien memakai penjelasan singkat instrumen, total dan arti skor,
  serta jangkar angka jawaban; tanpa rumus/CF/model. Rekomendasi lanjutan hanya
  DASS, katalog manual tetap lengkap. Detail audit profesional tetap tersedia.
- Judul katalog `Screening`. Riwayat pasien/profesional memakai filter instrumen
  independen WHO/GAD/PHQ/DASS, urutan terbaru/terlama, tanggal atau label tanggal
  tidak tercatat, lima entri awal dengan ekspansi. Retake sah tetap terpisah.
- Share record mendukung PDF dan profesional yang dipilih melalui izin/paket/
  tautan aktif yang sudah ada. PDF WHO mempertahankan peringatan item rendah.
  Kegagalan sebagian sumber harus menggagalkan ekspor yang meminta seluruh
  sumber. History/ekspor memakai `limit=0` untuk seluruh screening berizin;
  default feed tetap 20 dan batas positif maksimum 100.

Modul skrining kesehatan mental. Skoring dihitung **di server** (bukan hanya klien) memakai rule base yang sama.

## Lokasi kode
- Handler: `backend/internal/server/server.go` → `createScreening`, `listScreenings`, `reviewScreening`, `listScreeningReviews`.
- Skoring: `backend/internal/screening/engine.go` (`ScoreBundle`, `Score`, `overallLevel`).
- Rule base (Forward Chaining + Certainty Factor): `backend/internal/inference/` (`Engine.Infer`, `PHQ9Rules`, `GAD7Rules`, `RuleVersion = "2026.1.FC"`).
- Store: `backend/internal/store/` → `CreateScreeningBundle`, `ListScreeningSessions`, `UpsertScreeningReview`, `ListScreeningReviews`.
- Tabel: `screening_sessions`, `screening_reviews` (lihat `migrations/003_clinical_workflow.sql`).

## Endpoint
| Method | Path | Auth | Peran |
|---|---|---|---|
| POST | `/v1/screenings` | bearer | pasien (diri sendiri) / profesional (pasien terhubung) |
| GET | `/v1/screenings?patient_id=&limit=` | bearer | idem; profesional butuh consent `screenings` |
| POST | `/v1/screenings/{screening_id}/review` | bearer | **profesional saja** |
| GET | `/v1/screening-reviews` | bearer | pasien/profesional (sesuai relasi) |

## Aturan skoring
- PHQ-9: 9 pertanyaan, tiap jawaban 0–3, skor maksimum **27**.
- GAD-7: 7 pertanyaan, tiap jawaban 0–3, skor maksimum **21**.
- Jawaban wajib 0–3; jumlah jawaban wajib persis (9 / 7), jika tidak → error 400.
- PHQ-9: 0–4 `minimal`, 5–9 `mild`, 10–14 `moderate`, 15–19 `moderately_severe`, 20–27 `severe`. GAD-7: 0–4 `minimal`, 5–9 `mild`, 10–14 `moderate`, 15–21 `severe`.
- Level instrumen mengikuti skor total. Item self-harm PHQ-9 q9 > 0 menyalakan `crisis_flag` terpisah tanpa mengubah level instrumen. `overall_level` = level tertinggi PHQ-9/GAD-7; `crisis` bila salah satu `crisis_flag`.
- Server mem-publish realtime `screening.created`; flag krisis tampil di Crisis Incident Log. Tidak membuat notifikasi `screening_crisis` per profesional.
- Hasil menyertakan `cf` (certainty factor) dan `rule_trace` (maks 5 rule yang menembak) untuk audit.
- Lampiran historis tanpa label tingkat memakai cutoff total valid; total hilang,
  pecahan, negatif atau di luar rentang tidak ditampilkan sebagai normal/nol.
  Panel PHQ/GAD di detail pasien profesional mempertahankan CF berlabel tanpa
  string jejak aturan dan paragraf teknis; skor, interpretasi dan jawaban tetap ada.

## Makna Certainty Factor
- CF adalah **dukungan aturan dalam model**, bukan probabilitas diagnosis, persentase sakit, atau persentase keparahan. Bobot CF yang ada tidak memiliki bukti kalibrasi probabilitas klinis di repo; validitas instrumen tidak otomatis memvalidasi bobot ini.
- Fakta jawaban memakai 0/0.3/0.6/0.9; fakta total skor memakai bobot model 0.95. AND memakai minimum CF kondisi, kemudian CF kesimpulan = `ruleCF × CF kondisi`. Bobot saat ini dipertahankan, bukan dikalibrasi ulang.
- Contoh band ringan PHQ-9/GAD-7: `0.72 × min(0.95, 0.95) = 0.684` → **CF 68%** setelah pembulatan. Kedua kondisi adalah batas bawah/atas pada total skor yang sama, bukan dua bukti independen. Nilai tersebut tidak berarti peluang diagnosis 68%.
- Bukti independen pada kesimpulan yang sama memakai kombinasi paralel CF; setiap ID rule hanya menembak sekali agar bukti yang sama tidak dihitung berulang. Rule pola gejala saat ini membuat fakta terpisah dan tidak menambah CF band keparahan.
- Tampilkan CF mentah 0–1 tanpa normalisasi signed `(-1..1) → (0..1)` dan tanpa label kepastian seperti “Pasti”. Skor/level tetap ditampilkan terpisah. Item keselamatan dapat menaikkan CF hasil ke 0.95 sesuai model lama; indikator keselamatan tetap memerlukan tinjauan profesional.

## Review profesional
- Status review valid: `reviewed`, `needs_follow_up`, `escalated` (default `reviewed`).
- Catatan (`note`) dipotong maksimum 2000 karakter.
- Hanya profesional yang boleh review; pasien menerima notifikasi `screening_reviewed`.

## Aturan mengikat
- Skoring adalah **alat bantu**, bukan diagnosis. Keputusan klinis tetap pada profesional berlisensi.
- Jangan mengubah bobot rule/level tanpa memperbarui `RuleVersion` dan menyamakannya dengan klien Flutter.

## Detail profesional (2026-11-09)

- PHQ/GAD menampilkan skor, kategori, indikator keselamatan, interpretasi dan detail jawaban; gejala teridentifikasi bersumber hanya dari jawaban positif pada `bundle.*.answers` yang sudah disediakan API. Jawaban hilang/invalid tetap tidak tersedia, tidak direkayasa menjadi jawaban nol atau gejala dari skor total. Skor/CF/jejak aturan dipertahankan.
- WHO-5 memakai panel mint dan DASS panel lavender dengan skor/subskala, kategori, arahan tindak lanjut serta penjelasan skor. Detail per item memakai jawaban tersimpan. Metadata `scale_min`/`scale_max`/`scale_version` tidak menjadi jawaban klinis yang ditampilkan.
- Penghapusan Crisis Incident Log profesional tidak menghapus indikator keselamatan skrining atau data SOS global/pasien.
