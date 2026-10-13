-- Migration 013: refund paket (ledger) + idempotensi webhook gateway.
-- Idempoten, TANPA FK (role malva_app). Lihat catatan rollback di bawah.
--
-- CATATAN AZURE: konsisten dengan 012 — role aplikasi `malva_app` hanya
-- punya CREATE + DML, tanpa REFERENCES ke tabel milik admin `malva`.
-- Karena itu seluruh tabel di bawah SENGAJA tanpa FOREIGN KEY; integritas
-- referensial (user/package/session/payment harus ada) ditegakkan di
-- application layer. Seluruh pernyataan idempoten.

-- 1. Ledger refund/kredit untuk pembatalan oleh profesional.
CREATE TABLE IF NOT EXISTS care_refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid,                      -- paket terkait (boleh null bila sesi quick)
  session_id uuid,                      -- sesi yang dibatalkan
  patient_id uuid NOT NULL,
  professional_id uuid NOT NULL,
  amount bigint NOT NULL DEFAULT 0 CHECK (amount >= 0),   -- refund_value (price/total_sessions)
  kind text NOT NULL DEFAULT 'credit'
    CHECK (kind IN ('credit','refund')),   -- credit = kredit kuota; refund = uang kembali
  status text NOT NULL DEFAULT 'recorded'
    CHECK (status IN ('recorded','processing','paid','failed','cancelled')),
  reason text NOT NULL DEFAULT '',
  idempotency_key text NOT NULL,        -- mis. 'refund:care_session:<id>'
  external_id text NOT NULL DEFAULT '', -- ref payout/gateway (opsional)
  created_by uuid,                      -- aktor (profesional/admin/pasien)
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
-- Idempotensi: satu kunci -> satu baris (aman retry / double-click).
CREATE UNIQUE INDEX IF NOT EXISTS care_refunds_idem_uidx
  ON care_refunds (idempotency_key);
CREATE INDEX IF NOT EXISTS care_refunds_package_idx
  ON care_refunds (package_id, created_at DESC);
CREATE INDEX IF NOT EXISTS care_refunds_patient_idx
  ON care_refunds (patient_id, created_at DESC);

-- 2. Kolom akumulasi refund di paket (aditif; default 0 -> aman untuk baris lama).
ALTER TABLE care_packages
  ADD COLUMN IF NOT EXISTS refunded_amount bigint NOT NULL DEFAULT 0;

-- 3. Guard idempoten: pastikan kolom cancelled_by ada (sudah dibuat di 012:78;
--    baris ini no-op bila sudah ada, tapi melindungi DB lama).
ALTER TABLE care_sessions
  ADD COLUMN IF NOT EXISTS cancelled_by uuid;

-- 4. Log event webhook gateway -> idempotensi (kunci gateway+order_id+status).
CREATE TABLE IF NOT EXISTS payment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gateway text NOT NULL DEFAULT 'midtrans',
  external_id text NOT NULL,            -- = order_id Midtrans (payments.reference)
  event_type text NOT NULL DEFAULT '',  -- transaction_status (settlement/capture/expire/...)
  signature text NOT NULL DEFAULT '',
  gross_amount bigint NOT NULL DEFAULT 0,
  raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'received'
    CHECK (status IN ('received','processed','ignored','rejected')),
  payment_id uuid,
  booking_id uuid,
  processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
-- Idempotensi replay: event yang sama tidak diproses dua kali.
CREATE UNIQUE INDEX IF NOT EXISTS payment_events_idem_uidx
  ON payment_events (gateway, external_id, event_type);

-- 5. Kolom gateway pada payments (aditif).
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway text NOT NULL DEFAULT '';
ALTER TABLE payments ADD COLUMN IF NOT EXISTS snap_token text NOT NULL DEFAULT '';
ALTER TABLE payments ADD COLUMN IF NOT EXISTS redirect_url text NOT NULL DEFAULT '';

-- ROLLBACK 013 (jalankan hanya bila perlu):
-- DROP INDEX IF EXISTS payment_events_idem_uidx;
-- DROP TABLE IF EXISTS payment_events;
-- DROP INDEX IF EXISTS care_refunds_idem_uidx;
-- DROP INDEX IF EXISTS care_refunds_package_idx;
-- DROP INDEX IF EXISTS care_refunds_patient_idx;
-- DROP TABLE IF EXISTS care_refunds;
-- ALTER TABLE care_packages DROP COLUMN IF EXISTS refunded_amount;
-- ALTER TABLE payments DROP COLUMN IF EXISTS gateway;
-- ALTER TABLE payments DROP COLUMN IF EXISTS snap_token;
-- ALTER TABLE payments DROP COLUMN IF EXISTS redirect_url;
-- cancelled_by JANGAN di-drop (dipakai 012; biarkan).
