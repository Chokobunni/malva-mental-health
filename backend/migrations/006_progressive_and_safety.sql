-- Migration 006: Progressive Profiling, Safety Protocol, Professional Verification
-- PostGIS dipanggil di production (Supabase sudah preload postgis); di local fallback tanpa extension jika tidak ada
-- CREATE EXTENSION IF NOT EXISTS postgis; -- uncomment untuk production

ALTER TABLE users ADD COLUMN IF NOT EXISTS sso_provider VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS sso_id VARCHAR(255);
-- phone column ditambahkan oleh migration 011; DROP NOT NULL hanya bila kolom ada.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_name = 'users' AND column_name = 'phone') THEN
    ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
  END IF;
END $$;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_name VARCHAR(100) NOT NULL,
    contact_phone VARCHAR(20) NOT NULL,
    relationship VARCHAR(50),
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS emergency_contacts_patient_idx ON emergency_contacts (patient_id, is_default);

CREATE TABLE IF NOT EXISTS crisis_incidents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    triggered_by VARCHAR(20) NOT NULL,
    phq9_q9_score INTEGER,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    resolution_notes TEXT,
    resolved_by UUID REFERENCES users(id),
    doctor_notified_at TIMESTAMPTZ,
    contacts_notified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS crisis_incidents_patient_idx ON crisis_incidents (patient_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS sos_blast_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    crisis_incident_id UUID NOT NULL REFERENCES crisis_incidents(id) ON DELETE CASCADE,
    contact_phone VARCHAR(20) NOT NULL,
    channel VARCHAR(10) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    message_id VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    delivered_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS professional_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    str_number VARCHAR(100),
    sip_number VARCHAR(100),
    sipp_number VARCHAR(100),
    specialization VARCHAR(100) NOT NULL,
    sub_specialties TEXT[],
    hospital_lat DOUBLE PRECISION,
    hospital_lng DOUBLE PRECISION,
    hospital_name VARCHAR(255),
    address_details TEXT,
    is_bpjs_supported BOOLEAN NOT NULL DEFAULT false,
    photo_intro_url VARCHAR(255),
    video_intro_url VARCHAR(255),
    bio TEXT,
    education JSONB NOT NULL DEFAULT '[]'::jsonb,
    verification_status VARCHAR(20) DEFAULT 'PENDING',
    rejection_reason TEXT,
    verified_by UUID,
    verified_at TIMESTAMPTZ,
    document_url TEXT,
    legacy_count INTEGER NOT NULL DEFAULT 0,
    helpfulness_count INTEGER NOT NULL DEFAULT 0,
    review_count INTEGER NOT NULL DEFAULT 0,
    years_experience INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS professional_credentials_user_uidx ON professional_credentials (user_id);

CREATE TABLE IF NOT EXISTS professional_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professional_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    slot_duration_minutes INTEGER NOT NULL DEFAULT 30,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS service_packages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professional_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    package_sessions INTEGER NOT NULL,
    package_duration_days INTEGER NOT NULL,
    price BIGINT NOT NULL,
    label VARCHAR(50),
    is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    professional_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    package_id UUID REFERENCES service_packages(id),
    service_type VARCHAR(20) NOT NULL,
    session_type VARCHAR(10) NOT NULL,
    booking_date DATE NOT NULL,
    slot_time TIME NOT NULL,
    duration_minutes INTEGER NOT NULL DEFAULT 30,
    price BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    payment_method VARCHAR(20) NOT NULL,
    gross_amount BIGINT NOT NULL,
    service_fee_amount BIGINT NOT NULL DEFAULT 2000,
    platform_fee_pct SMALLINT NOT NULL DEFAULT 10,
    platform_fee_amount BIGINT NOT NULL,
    net_amount BIGINT NOT NULL,
    reference VARCHAR(255) NOT NULL UNIQUE,
    external_id VARCHAR(255),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    paid_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS e_prescriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professional_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notes TEXT,
    instructions TEXT,
    signature_data JSONB,
    qr_token VARCHAR(255) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'issued',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS e_prescription_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prescription_id UUID NOT NULL REFERENCES e_prescriptions(id) ON DELETE CASCADE,
    medication_id UUID,
    name VARCHAR(255) NOT NULL,
    form VARCHAR(50),
    dosage VARCHAR(100),
    frequency VARCHAR(50),
    days INTEGER NOT NULL DEFAULT 30,
    units_per_day INTEGER NOT NULL DEFAULT 1,
    unit VARCHAR(20) NOT NULL DEFAULT 'tablet'
);

CREATE TABLE IF NOT EXISTS earnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professional_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    payment_id UUID NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
    gross BIGINT NOT NULL,
    platform_fee BIGINT NOT NULL,
    net BIGINT NOT NULL,
    payout_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    payout_bank VARCHAR(50),
    payout_account VARCHAR(100),
    payout_requested_at TIMESTAMPTZ,
    paid_out_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS doctor_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professional_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    booking_id UUID REFERENCES bookings(id),
    helpfulness_percent INTEGER NOT NULL CHECK (helpfulness_percent BETWEEN 0 AND 100),
    review_text TEXT,
    helpful BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS psychological_tests_catalog (
    id VARCHAR(100) PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    disclaimer TEXT NOT NULL,
    price BIGINT NOT NULL DEFAULT 0,
    banner_image_url VARCHAR(255),
    is_active BOOLEAN NOT NULL DEFAULT true
);

-- Migration 007: Chat Attachment & Privacy Purge
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS attachment_type VARCHAR(20);
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS attachment_url TEXT;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS attachment_meta JSONB;

ALTER TABLE patient_data_consents ADD COLUMN IF NOT EXISTS share_health_record BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE patient_data_consents ADD COLUMN IF NOT EXISTS share_goals BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE patient_data_consents ADD COLUMN IF NOT EXISTS share_diary_checkin BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE patient_data_consents ADD COLUMN IF NOT EXISTS share_medication_checkin BOOLEAN NOT NULL DEFAULT true;

-- Privacy: index untuk purge GPS setelah incident resolved
CREATE INDEX IF NOT EXISTS crisis_incidents_resolved_idx ON crisis_incidents (status, resolved_at) WHERE status = 'resolved';
