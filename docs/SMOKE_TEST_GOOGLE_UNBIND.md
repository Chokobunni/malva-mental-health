# Smoke Test — Lepas Tautan Google (Unbind)

Checklist uji manual end-to-end untuk fitur **Akun Google → Lepas Gmail**
(`POST /v1/auth/unbind-google`). Tiap langkah punya hasil yang diharapkan.

- Lingkup: pasien & profesional (admin tidak diizinkan).
- Status verifikasi yang dipakai:
  - **VERIFIED (otomatis)** — dibuktikan oleh test Go/Flutter di repo pada mesin QA.
  - **NOT-VERIFIED (butuh perangkat)** — perlu HP + akun Google asli, tidak bisa dijalankan di mesin QA.
  - **FAIL** — perilaku tidak sesuai harapan (ditemukan cacat).
- Nama test otomatis yang dirujuk ada di
  `backend/internal/server/google_unbind_test.go`,
  `backend/internal/server/google_unbind_qa_test.go`,
  `test/google_account_card_test.dart`.

## Prasyarat

1. Backend berjalan dengan `MALVA_GOOGLE_CLIENT_SECRET` terisi (Meet aktif).
2. Aplikasi Flutter terpasang di perangkat dengan akun Google uji siap pakai.
3. Tersedia 3 akun uji: **pasien** (`pasien@...`), **profesional** (punya STR/SIP),
   dan **admin**.
4. Untuk skenario DB langsung, gunakan DB uji yang sudah punya migrasi 021
   (`sso_email`). Jangan memakai DB produksi.

---

## Skenario

### 1. Pasien: bind → unbind dengan password baru → login dengan password
1. Login sebagai **pasien**.
2. Buka **Pengaturan → Akun Google**, tekan **Hubungkan Gmail**, selesaikan login Google.
   - Harapan: kartu berubah jadi **"Gmail tertaut"** + menampilkan email Gmail + pill **"Terhubung"**.
3. Tekan **Lepas Gmail**, konfirmasi **Lepas**.
   - Harapan: muncul dialog **"Tetapkan password baru"** (akun belum tentu punya password terpakai).
4. Isi password baru yang kuat (mis. `NewPassword123!`), tekan **Simpan & Lepas**.
   - Harapan: kartu berubah ke mode **"Hubungkan Gmail"**, muncul snackbar **"Gmail berhasil dilepas."**
5. Logout, lalu login lagi memakai **email akun + password baru**.
   - Harapan: login berhasil (HTTP 200, token terbit).
- **Status:** backend VERIFIED otomatis (`TestUnbindGoogleWithNewPassword`). Langkah sign-in Google asli **NOT-VERIFIED (butuh perangkat)**.

### 2. Pasien: unbind tanpa kredensial → 409 `perlu_password`
1. Login sebagai pasien yang **sudah tertaut** Gmail.
2. Panggil `POST /v1/auth/unbind-google` dengan body kosong `{}` (atau lewat UI tanpa mengisi dialog).
   - Harapan: HTTP **409**, body `{"code":"perlu_password", ...}`.
3. Periksa status tautan tetap ada (`GET /v1/auth/google-identity` → `linked:true`).
- **Status:** VERIFIED otomatis (`TestUnbindGoogleRequiresPassword`).

### 3. Profesional placeholder: bind → unbind → email TETAP Gmail
1. Siapkan profesional dengan email placeholder `<professional_id>@professional.malva.local`.
2. Login, **Hubungkan Gmail**.
   - Harapan: email akun naik menjadi Gmail (placeholder di-upgrade), `linked:true`.
3. **Lepas Gmail** dengan password baru.
   - Harapan: email akun **tetap Gmail** hasil bind (TIDAK dikembalikan ke placeholder).
   - Catatan: ini keputusan sadar — setelah unbind akun tetap ada dan Gmail itu
     memang email kontaknya; placeholder fiktif justru memutus notifikasi.
- **Status:** VERIFIED otomatis (`TestUnbindGoogleKeepsGmailForProfessional`).

### 4. Profesional dengan email ASLI: bind → unbind → email TIDAK berubah
1. Daftarkan profesional **mandiri** memakai email asli (mis. `dr.asli@gmail.com`) + password.
2. Login, **Hubungkan Gmail** memakai **akun Google yang sama** (`dr.asli@gmail.com`).
3. **Lepas Gmail** dengan password baru.
   - **Harapan:** email akun **tetap** `dr.asli@gmail.com` (tidak diganti placeholder).
- **Status:** VERIFIED otomatis (`TestUnbindGoogleKeepsRealEmailForSelfRegisteredProfessional`).
  Dulu FAIL (bug P1); kini email asli dipertahankan karena logika pemulihan
  placeholder dihapus.

### 5. Unbind dua kali → 409 `google_belum_tertaut`
1. Lakukan unbind sukses (skenario 1).
2. Panggil `POST /v1/auth/unbind-google` sekali lagi.
   - Harapan: HTTP **409**, `{"code":"google_belum_tertaut"}`.
- **Status:** VERIFIED otomatis (`TestUnbindGoogleFreesGmailForAnotherPatient` langkah 5, dan `TestUnbindGoogleNotLinked`).

### 6. Admin: unbind → 403
1. Login sebagai **admin**.
2. Panggil `POST /v1/auth/unbind-google`.
   - Harapan: HTTP **403** (hanya pasien/profesional).
- **Status:** VERIFIED otomatis (`TestUnbindGoogleRejectsAdmin`).

### 7. `current_password` salah → 401 `password_salah`
1. Login sebagai pasien tertaut yang punya password.
2. Panggil unbind dengan `{"current_password":"SalahBanget123!"}`.
   - Harapan: HTTP **401**, `{"code":"password_salah"}`, tautan **tetap ada**.
- **Status:** VERIFIED otomatis (`TestUnbindGoogleWrongCurrentPassword`).

### 8. Google Meet nonaktif setelah unbind
1. Sebagai profesional, tautkan Gmail lalu **Aktifkan Google Meet** (connected).
   - Harapan: status "Google Meet aktif".
2. **Lepas Gmail**.
   - Harapan: status Meet kembali ke **belum terhubung**; `GET /v1/google/status` →
     `connected:false`, `identity_bound:false` (bukan error 500); token OAuth terhapus.
- **Status:** backend VERIFIED otomatis (`TestUnbindGoogleDeletesOAuthTokens`, `TestGoogleStatusSeparatesIdentityAndCalendar`). Tampilan Meet di perangkat **NOT-VERIFIED (butuh perangkat)**.

### 9. Bind ulang setelah unbind berhasil
1. Setelah unbind sukses (skenario 1), tekan **Hubungkan Gmail** lagi dan selesaikan login Google.
   - Harapan: tautan berhasil lagi (`linked:true`), tidak ada error "sudah tertaut".
- **Status:** backend VERIFIED otomatis (`TestUnbindGoogleFreesGmailForAnotherPatient` langkah 9). Sign-in Google asli **NOT-VERIFIED (butuh perangkat)**.

### 10. Pasien lain BISA memakai Gmail yang sudah dilepas
1. Pasien A tautkan `shared@gmail.com`, lalu **Lepas** Gmail tersebut.
2. Login sebagai **pasien B** (akun berbeda), **Hubungkan Gmail** memakai `shared@gmail.com`.
   - Harapan: berhasil (`linked:true`) — Gmail benar-benar bebas, bukan terkunci ke A.
- **Status:** VERIFIED otomatis (`TestUnbindGoogleFreesGmailForAnotherPatient` langkah 10).

### 11. Tampilan kartu sebelum vs sesudah unbind
1. Sebelum tertaut: kartu berjudul **"Hubungkan Gmail"**, ada tombol **Hubungkan Gmail**, tidak ada tombol Lepas.
2. Sesudah tertaut: judul **"Gmail tertaut"**, pill **"Terhubung"**, email tampil, ada tombol **Lepas Gmail**.
3. Setelah unbind sukses: kembali ke **"Hubungkan Gmail"** (bukan hanya snackbar) — tombol **Lepas Gmail** hilang.
- **Status:** VERIFIED otomatis (`test/google_account_card_test.dart`). Rendering visual di perangkat **NOT-VERIFIED (butuh perangkat)**.

### 12. Tombol "Lepas Gmail" tidak muncul saat belum tertaut
1. Login sebagai akun yang **belum** menautkan Gmail.
2. Buka kartu Akun Google.
   - Harapan: hanya ada tombol **Hubungkan Gmail**; **tidak ada** tombol **Lepas Gmail**.
- **Status:** VERIFIED otomatis (`test/google_account_card_test.dart`; setelah unbind `Lepas Gmail` = `findsNothing`).

---

## Ringkasan Status

| # | Skenario | Status |
|---|----------|--------|
| 1 | Pasien bind→unbind→login password | VERIFIED (backend) / NOT-VERIFIED (perangkat, sign-in Google) |
| 2 | Pasien unbind tanpa kredensial → 409 `perlu_password` | VERIFIED |
| 3 | Profesional placeholder → email tetap Gmail | VERIFIED |
| 4 | Profesional email asli → email tidak berubah | VERIFIED |
| 5 | Unbind dua kali → 409 `google_belum_tertaut` | VERIFIED |
| 6 | Admin → 403 | VERIFIED |
| 7 | `current_password` salah → 401 `password_salah` | VERIFIED |
| 8 | Meet nonaktif setelah unbind | VERIFIED (backend) / NOT-VERIFIED (perangkat) |
| 9 | Bind ulang setelah unbind | VERIFIED (backend) / NOT-VERIFIED (perangkat) |
| 10 | Pasien lain bisa pakai Gmail yang dilepas | VERIFIED |
| 11 | Tampilan kartu sebelum/sesudah | VERIFIED (widget) / NOT-VERIFIED (perangkat) |
| 12 | Tombol "Lepas Gmail" tidak muncul saat belum tertaut | VERIFIED |

**Catatan:** Skenario yang menyentuh sign-in Google asli dan rendering visual di HP
tidak dapat dijalankan di mesin QA (tidak ada perangkat/akun Google) dan ditandai
**NOT-VERIFIED (butuh perangkat)** — bukan PASS. Skenario **4** (bug P1 email asli
dirusak) sudah **DIPERBAIKI**: logika pemulihan placeholder dihapus, sehingga email
akun (placeholder yang sudah di-upgrade maupun email asli) **tidak diubah** saat
unbind.
