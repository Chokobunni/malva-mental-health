-- 022_merge_care_packages.sql
-- Gabungkan paket sesi pasien+profesional yang sama menjadi satu paket.
--
-- Aturan bisnis: bila pasien sudah punya paket 4 sesi aktif dan membeli paket
-- lagi dari profesional yang sama, total pertemuan digabung dan MyCare
-- menampilkan satu paket gabungan. Migrasi ini:
--   1. Menambah kolom penanda penggabungan (merged_into, merged_at).
--   2. Melonggarkan CHECK status agar menerima 'merged'.
--   3. Membersihkan data lama: pasangan yang sudah punya >1 paket aktif
--      digabung ke paket aktif paling awal. Idempoten: setelah sekali jalan,
--      tiap pasangan hanya punya satu paket aktif sehingga blok jadi no-op.
--
-- Semua kolom waktu memakai timestamptz. Idempoten (IF NOT EXISTS / DO block).

ALTER TABLE care_packages ADD COLUMN IF NOT EXISTS merged_into uuid;
ALTER TABLE care_packages ADD COLUMN IF NOT EXISTS merged_at timestamptz;

-- Longgarkan CHECK status agar menerima 'merged'. DROP lalu ADD ulang membuat
-- langkah ini idempoten (dijalankan berulang tetap menghasilkan constraint sama).
ALTER TABLE care_packages DROP CONSTRAINT IF EXISTS care_packages_status_check;
ALTER TABLE care_packages ADD CONSTRAINT care_packages_status_check
  CHECK (status IN ('pending_payment','active','expired','completed','cancelled','merged'));

-- Data cleanup: gabung pasangan yang masih punya lebih dari satu paket aktif.
DO $$
DECLARE
  grp RECORD;
  target_id uuid;
  add_total int;
  add_price bigint;
  max_exp timestamptz;
BEGIN
  FOR grp IN
    SELECT patient_id, professional_id
    FROM care_packages
    WHERE status = 'active'
    GROUP BY patient_id, professional_id
    HAVING count(*) > 1
  LOOP
    -- Target = paket aktif paling awal dibuat.
    SELECT id INTO target_id
    FROM care_packages
    WHERE patient_id = grp.patient_id
      AND professional_id = grp.professional_id
      AND status = 'active'
    ORDER BY created_at ASC, id ASC
    LIMIT 1;

    -- Akumulasi total sesi & harga dari paket aktif lain.
    SELECT COALESCE(SUM(total_sessions), 0), COALESCE(SUM(price), 0), MAX(expires_at)
    INTO add_total, add_price, max_exp
    FROM care_packages
    WHERE patient_id = grp.patient_id
      AND professional_id = grp.professional_id
      AND status = 'active'
      AND id <> target_id;

    -- Pindahkan sesi lama agar tetap menunjuk paket target (jejak tetap utuh).
    UPDATE care_sessions
    SET package_id = target_id
    WHERE package_id IN (
      SELECT id FROM care_packages
      WHERE patient_id = grp.patient_id
        AND professional_id = grp.professional_id
        AND status = 'active'
        AND id <> target_id
    );

    -- Tandai paket lain sebagai merged.
    UPDATE care_packages
    SET status = 'merged', merged_into = target_id, merged_at = now(), updated_at = now()
    WHERE patient_id = grp.patient_id
      AND professional_id = grp.professional_id
      AND status = 'active'
      AND id <> target_id;

    -- Akumulasikan ke paket target.
    UPDATE care_packages
    SET total_sessions = total_sessions + add_total,
        price = price + add_price,
        expires_at = GREATEST(expires_at, max_exp),
        updated_at = now()
    WHERE id = target_id;
  END LOOP;
END $$;
