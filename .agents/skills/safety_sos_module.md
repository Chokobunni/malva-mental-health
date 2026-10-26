# Skill: Safety / SOS Module

Kontak darurat, insiden krisis, dan blast SOS ke kontak via WhatsApp (gateway Fonnte).

## Lokasi kode
- Handler: `backend/internal/server/handlers_safety.go` (`createEmergencyContact`, `updateEmergencyContact`, `deleteEmergencyContact`, `listEmergencyContacts`, `handleCrisisAlertV2`, `listCrisisIncidents`, `resolveCrisisIncident`, `listBlastStatus`).
- Store: `backend/internal/store/safety.go` (`CreateCrisisIncident`, `ResolveCrisisIncident`, `CreateSOSBlastLog`, `UpdateSOSBlastStatus`, `SOSBlastStatusForIncident`, `ListEmergencyContacts`).
- Notifier: `backend/internal/notify` (`FonnteSender`) — dirakit dari `cfg.FonnteToken` di `New()`.
- Tabel: `emergency_contacts`, `crisis_incidents`, `sos_blast_log` (`migrations/006`).

## Endpoint
| Method | Path | Catatan |
|---|---|---|
| GET | `/v1/emergency-contacts` | daftar kontak darurat pasien |
| POST | `/v1/emergency-contacts` | **maksimal 5 kontak** per pasien |
| PUT | `/v1/emergency-contacts/{id}` | ubah kontak |
| DELETE | `/v1/emergency-contacts/{id}` | hapus kontak |
| POST | `/v1/crisis-alerts` | kirim SOS (rate-limit 1x / 10 menit / pasien) |
| GET | `/v1/crisis-incidents` | riwayat insiden |
| POST | `/v1/crisis-incidents/{id}/resolve` | profesional terkait / admin |
| GET | `/v1/sos-blast-status?incident_id=` | status per-kontak |

## Aturan mengikat (PALING PENTING)
- **JANGAN PERNAH mengaku "terkirim" bila kanal tidak terkonfigurasi.** Bila `MALVA_FONNTE_TOKEN` kosong → `s.sos = nil`, kanal `none`, status `unconfigured`; tiap kontak ditandai `failed` — tidak pernah `sent`.
- Status blast per kontak: `queued` → `sent` (dengan `message_id`) / `failed` / `unconfigured`. Aplikasi menampilkan "belum terkirim" + **hotline 119 ext 8** saat gagal/nonaktif.
- Blast berjalan di background (`go func` dengan context timeout 60s) karena context request dibatalkan setelah handler return.
- Insiden krisis: status `active` → `resolved` (dengan `resolution_notes` wajib). Insiden aktif lama bisa dipurge GPS-nya (`PurgeResolvedCrisisGPS`).
- Broadcast realtime `crisis_alert` ke profesional terpantau; nama pasien diambil dari `DisplayName` (bukan UUID).
- `triggered_by` valid: `screening`, `sos_button`, `manual`, `phq9_q9`, `silent_sos`.
- Nomor telepon divalidasi format Indonesia (08xxx / 62xxx), panjang 9–15 digit.
