# Skill: Screening Module (PHQ-9 / GAD-7)

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
- Level: `minimal`, `mild`, `moderate`, `severe`, `crisis`. `overall_level` = level tertinggi PHQ-9/GAD-7; `crisis` bila salah satu `crisis_flag`.
- `crisis_flag` (mis. item self-harm PHQ-9 q9) → server memanggil `notifyProfessionalsForCrisis` + publish realtime `screening.created`.
- Hasil menyertakan `cf` (certainty factor) dan `rule_trace` (maks 5 rule yang menembak) untuk audit.

## Review profesional
- Status review valid: `reviewed`, `needs_follow_up`, `escalated` (default `reviewed`).
- Catatan (`note`) dipotong maksimum 2000 karakter.
- Hanya profesional yang boleh review; pasien menerima notifikasi `screening_reviewed`.

## Aturan mengikat
- Skoring adalah **alat bantu**, bukan diagnosis. Keputusan klinis tetap pada profesional berlisensi.
- Jangan mengubah bobot rule/level tanpa memperbarui `RuleVersion` dan menyamakannya dengan klien Flutter.
