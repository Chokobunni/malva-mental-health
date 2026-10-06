# 🗄️ Database Admin Access - Malva Mental Health

Panduan lengkap untuk mengakses, memantau, dan mengelola database PostgreSQL 18 Malva.

---

## 🔐 **Koneksi Database**

### **Method 1: psql Command Line (Recommended)**

```powershell
# Di PowerShell, jalankan:
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U malva -d malva

# Password: malva_dev_password
```

**Setelah connect, prompt akan berubah jadi:**
```
malva=#
```

### **Method 2: pgAdmin (GUI)**

1. Buka pgAdmin (sudah terinstall dengan PostgreSQL 18)
2. Klik kanan **Servers** → **Register** → **Server**
3. **General** tab:
   - Name: `Malva Local`
4. **Connection** tab:
   - Host: `localhost`
   - Port: `5432`
   - Database: `malva`
   - Username: `malva`
   - Password: `malva_dev_password`
5. Klik **Save**

---

## 📊 **Quick Reference Commands**

### **Inside psql:**

```sql
-- List semua tabel
\dt

-- Describe struktur tabel
\d users
\d professional_profiles
\d emergency_contacts

-- List semua database
\l

-- Quit psql
\q

-- Execute SQL file
\i manage_emergency_contacts.sql
```

---

## 📋 **Common Admin Tasks**

### **1. Emergency Contacts Management**

```powershell
# Di PowerShell, jalankan SQL script:
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U malva -d malva -f "D:\Project\Malva\2026-07-09\say\outputs\malva\backend\admin_scripts\manage_emergency_contacts.sql"
```

**Atau copy-paste query dari file `manage_emergency_contacts.sql` langsung ke psql.**

**Contoh: View semua kontak darurat untuk patient tertentu:**
```sql
SELECT
    id,
    contact_name,
    contact_phone,
    relationship,
    is_default
FROM emergency_contacts
WHERE patient_id = (
    SELECT id FROM users WHERE email = 'preview_pasien@malva.app'
);
```

### **2. Doctors Management**

```powershell
# Di PowerShell, jalankan SQL script:
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U malva -d malva -f "D:\Project\Malva\2026-07-09\say\outputs\malva\backend\admin_scripts\manage_doctors.sql"
```

**Contoh: View semua dokter aktif:**
```sql
SELECT
    u.display_name,
    pc.specialization,
    pc.hospital_name,
    pc.price_from,
    pc.verification_status
FROM users u
JOIN professional_credentials pc ON pc.user_id = u.id
WHERE u.role = 'professional' AND u.disabled_at IS NULL
ORDER BY u.display_name;
```

> Kolom penting: status nonaktif = `disabled_at IS NOT NULL` (bukan `disabled`),
> detail klinis profesional ada di `professional_credentials`, bukan
> `professional_profiles` (yang hanya menyimpan kode 16 digit).

---

## 🔍 **Data Monitoring Queries**

### **Total Users by Role**
```sql
SELECT role, COUNT(*) AS total,
       COUNT(CASE WHEN disabled_at IS NULL THEN 1 END) AS active
FROM users
GROUP BY role;
```

### **Recent Registrations (Last 7 Days)**
```sql
SELECT email, display_name, role, created_at
FROM users
WHERE created_at >= NOW() - INTERVAL '7 days'
ORDER BY created_at DESC;
```

### **Total Bookings**
```sql
SELECT COUNT(*) AS total_bookings,
       COUNT(CASE WHEN status = 'confirmed' THEN 1 END) AS confirmed,
       COUNT(CASE WHEN status = 'pending' THEN 1 END) AS pending
FROM bookings;
```

### **Total Screening Assessments**
```sql
SELECT COUNT(*) AS total_screenings,
       AVG(phq9_score) AS avg_phq9,
       AVG(gad7_score) AS avg_gad7
FROM screening_results;
```

---

## ⚠️ **IMPORTANT: Data Safety**

### **Backup Database (Before Major Changes)**
```powershell
# Di PowerShell:
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
& "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -U malva -F c -b -v -f "D:\Project\Malva\backups\malva_backup_$timestamp.backup" malva
```

### **Restore Database**
```powershell
# WARNING: Ini akan overwrite database!
& "C:\Program Files\PostgreSQL\18\bin\pg_restore.exe" -U malva -d malva -v "D:\Project\Malva\backups\malva_backup_TIMESTAMP.backup"
```

---

## 🛠️ **Troubleshooting**

### **"psql: error: connection refused"**
- Backend API mungkin belum jalan. Start dengan:
  ```powershell
  cd "D:\Project\Malva\2026-07-09\say\outputs\malva\backend"
  $env:MALVA_DATABASE_URL = "postgres://malva:malva_dev_password@localhost:5432/malva?sslmode=disable"
  $env:MALVA_JWT_SECRET = "2dbccb5cccd0497f9ccf0323735ac2302ade3544c49fdfefd4a1feb09f693474"
  .\api.exe
  ```

### **"password authentication failed"**
- Pastikan password: `malva_dev_password`
- Jika lupa, reset via `pg_hba.conf` atau reinstall PostgreSQL

### **"permission denied for table"**
- User `malva` harus punya privileges. Grant dengan:
  ```sql
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO malva;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO malva;
  ```

---

## 📁 **File Locations**

- **SQL Scripts**: `D:\Project\Malva\2026-07-09\say\outputs\malva\backend\admin_scripts\`
- **Migrations**: `D:\Project\Malva\2026-07-09\say\outputs\malva\backend\migrations\`
- **Backups**: `D:\Project\Malva\backups\` (create folder if needed)

---

## 🎯 **Next Steps**

1. ✅ Connect ke database dengan psql atau pgAdmin
2. ✅ Run `manage_emergency_contacts.sql` dan `manage_doctors.sql` untuk explore data
3. ✅ Bookmark query-query yang sering dipakai
4. ✅ Setup backup schedule (manual atau automated)

**Full control sekarang ada di tangan Anda! 🚀**
