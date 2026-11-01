# Google Calendar / Meet Setup — Malva

Panduan mengaktifkan **Google Calendar + Google Meet** untuk profesional
(sesi video otomatis punya link Meet) di aplikasi Malva.
Project Google Cloud: **`malva-7084e`**.

> **Ringkas:** error `403: access_denied` saat menekan "Hubungkan Google
> Calendar" **bukan bug aplikasi**. Penyebabnya konfigurasi *OAuth consent
> screen* di Google Cloud Console: aplikasi masih berstatus **Testing** dan/atau
> Gmail profesional belum terdaftar sebagai **Test user**. Ikuti langkah di
> bawah, lalu hubungkan ulang dari dalam aplikasi.

---

## 1. Gejala dan artinya

Saat profesional menekan **Hubungkan Google Calendar**, Google menampilkan:

```
Error 403: access_denied
Malva has not completed the Google verification process. The app is
currently being tested and can only be accessed by developer-approved testers.
```

Artinya:

| Bagian pesan | Arti |
|---|---|
| `has not completed the Google verification process` | Scope yang diminta (`https://www.googleapis.com/auth/calendar.events`) adalah **scope sensitif**. Google mewajibkan verifikasi formal untuk aplikasi yang dipakai publik. |
| `can only be accessed by developer-approved testers` | OAuth consent screen project masih berstatus **Testing**, sehingga hanya akun yang terdaftar sebagai **Test user** yang boleh memberi izin. |
| `403 access_denied` | Permintaan izin ditolak Google **sebelum** aplikasi Malva menerima authorization code. |

Akibat berantai bila dibiarkan:

1. Profesional tidak pernah menyimpan refresh token Calendar.
2. `POST /v1/care-sessions/{id}/meet-link` dan pembuatan Meet otomatis gagal
   dengan `meet_belum_aktif`.
3. **Pasien tetap bisa menjadwalkan sesi video** (sejak perbaikan BUG 2):
   sesi lahir berstatus *menunggu link* dan link dibuat menyusul setelah
   profesional menyelesaikan langkah di dokumen ini.
4. **Profesional tetap bisa menyelenggarakan sesi video lewat fallback manual**
   (`PUT /v1/care-sessions/{id}/meet-link`, lihat bagian 10) — sesi tidak
   pernah buntu hanya karena Google diblokir.

---

## 1a. Kalau profesional diblokir `access_denied` (ringkas)

Google memblokir **sebelum** callback ke backend, jadi tidak ada kode aplikasi
yang bisa mencegah halaman "Access blocked" muncul. Yang bisa dilakukan:

1. **Daftarkan Gmail profesional sebagai Test user** (uji cepat):
   Google Cloud Console → **APIs & Services** → **OAuth consent screen** →
   tab **Audience** → **Test users** → **+ Add users** → masukkan Gmail
   profesional (mis. `andiwijayapsikolog@gmail.com`) → **Save**.
2. **ATAU Publish app** (produksi): OAuth consent screen → **Publish app**.
   Setelah *In production*, semua Gmail boleh memakai (dengan peringatan
   "unverified" sampai verifikasi formal disetujui Google).
3. Dari aplikasi, profesional menekan **Coba lagi** pada dialog
   "Google menolak akses" (Gmail-nya bisa disalin langsung dari dialog).

> **Catatan 7 hari:** selama consent screen masih **Testing**, refresh token
> Google hanya berlaku **7 hari**. Publish app agar tidak perlu menautkan ulang
> tiap minggu (lihat bagian 2b dan 9).

Bila console belum bisa diubah, profesional **tidak buntu**: gunakan
**"Tempel link Meet"** pada kartu sesi video (bagian 10).

---

## 2. Langkah perbaikan di Google Cloud Console

Semua langkah memakai akun pemilik project `malva-7084e`.

### 2a. Uji cepat — daftarkan Gmail profesional sebagai Test user

1. Buka
   <https://console.cloud.google.com/apis/credentials/consent?project=malva-7084e>
2. Pastikan project yang terpilih adalah **malva-7084e**.
3. Pada **OAuth consent screen** → bagian **Test users**, tekan
   **+ ADD USERS**.
4. Tambahkan Gmail profesional yang dipakai Malva, misalnya
   `hafidpsikiater@gmail.com` (dan Gmail profesional lain yang akan memakai
   Google Meet).
5. **SAVE**. Perubahan berlaku dalam hitungan detik.
6. Di aplikasi: profesional membuka **Pengaturan → Akun Google** →
   **Hubungkan Google Calendar** → pilih Gmail yang tadi didaftarkan → izinkan.

> Catatan: Test user maksimal **100 akun**. Cukup untuk uji coba, tidak cukup
> untuk produksi.

### 2b. Publish aplikasi (WAJIB untuk produksi)

1. Masih di **OAuth consent screen**, tekan **PUBLISH APP** → **Confirm**.
2. Status berubah dari *Testing* menjadi *In production*.

**Peringatan penting — batas 7 hari saat status Testing.** Selama consent
screen berstatus *Testing*, Google menerbitkan refresh token yang **hanya
berlaku 7 hari**. Artinya integrasi Calendar akan "kedaluwarsa" setiap minggu
dan profesional harus menautkan ulang terus-menerus. **Inilah penyebab utama
error berulang yang dilaporkan pengguna.** Karena itu publish aplikasi, jangan
berhenti di langkah 2a.

---

## 3. Konsekuensi mem-publish tanpa verifikasi

Mem-publish consent screen **tidak otomatis** membuat aplikasi terverifikasi.
Selama verifikasi formal belum disetujui Google:

| Konsekuensi | Keterangan |
|---|---|
| Layar peringatan | Pengguna melihat **"Google hasn't verified this app"**. Bisa dilewati: **Advanced** → **Go to Malva (unsafe)**. |
| Batas pengguna | Maksimal **100 pengguna** sampai verifikasi disetujui. |
| Scope sensitif | `calendar.events` termasuk scope sensitif, jadi verifikasi formal diperlukan untuk pemakaian publik penuh (butuh penjelasan penggunaan, video demo, dan privacy policy). |
| Refresh token | Berlaku normal (tidak lagi dibatasi 7 hari) — ini yang paling penting untuk Malva. |

Bila verifikasi formal diinginkan: isi form **Verification Center** di Google
Cloud Console dengan justifikasi pemakaian `calendar.events` (membuat event
sesi konsultasi + link Meet di kalender profesional) dan tautan kebijakan
privasi Malva.

---

## 4. Cara memverifikasi berhasil

1. Login aplikasi sebagai **profesional**.
2. Buka **Pengaturan → Akun Google**.
3. Pada bagian **Google Meet**, status harus menunjukkan
   **"Google Meet aktif"** (sebelumnya tombol "Hubungkan Google Calendar").
4. Cek alternatif lewat API:

   ```bash
   curl -s "$MALVA_API_BASE/v1/professionals/<professional_user_id>/meet-status" \
     -H "Authorization: Bearer <access_token_profesional>"
   ```

   Respons sukses:

   ```json
   {"ready": true, "reason": "ready"}
   ```

   Nilai `reason` lain dan artinya:

   | `reason` | Arti | Tindakan |
   |---|---|---|
   | `not_linked` | Akun Malva belum menautkan Gmail | Hubungkan Gmail di kartu Akun Google |
   | `no_calendar_scope` | Gmail tertaut, izin `calendar.events` belum ada | Tekan "Hubungkan Google Calendar" |
   | `token_expired` | Refresh token kosong/ditolak Google (mis. batas 7 hari saat *Testing*) | Hubungkan ulang, lalu publish consent screen |
   | `token_hampir_kedaluwarsa` | Izin **masih berlaku** (link Meet tetap bisa dibuat) tetapi umur refresh token mendekati batas 7 hari | Tekan "Perbarui izin sekarang" agar link Meet sesi berikutnya tidak gagal |
   | `server_not_configured` | Server belum punya `MALVA_GOOGLE_CLIENT_SECRET` | Hubungi admin/deployment |
   | `ready` | Siap membuat link Meet | — |

   Respons kini juga menyertakan `refresh_token_age_days` (umur grant dalam
   hari, `0` bila tak ada token) dan `refresh_token_expires_in_days` (sisa hari,
   `-1` bila tidak diketahui). Keduanya opsional; klien lama tetap jalan.
   Untuk profesional pemilik akun, respons juga memuat `google_email` (email
   akun Google tertaut — tanpa token) dan `hint` (saran tindakan berbahasa
   Indonesia) pada `reason` yang butuh perbaikan akun (`not_linked`,
   `no_calendar_scope`, `token_expired`).

5. Uji akhir: profesional menekan **Create Meeting** di dashboard. Bila muncul
   link `https://meet.google.com/...`, integrasi sudah benar.

---

## 5. Mencabut izin (bila refresh token kosong atau akun salah)

Bila profesional pernah memberi izin dengan akun Google yang salah, cabut dulu
izinnya agar Google menerbitkan refresh token baru:

1. Buka <https://myaccount.google.com/permissions> dengan akun Google tersebut.
2. Pilih **Malva** → **Remove access**.
3. Di aplikasi: **Pengaturan → Akun Google** → **Hubungkan Google Calendar**
   lagi, kali ini pilih Gmail yang benar.

Di sisi server, token yang sudah tidak berlaku dihapus otomatis ketika Google
menolak refresh (`invalid_grant`), sehingga status berubah menjadi
`token_expired` — bukan lagi "aktif" secara bohong.

---

## 6. Checklist cepat

- [ ] Project `malva-7084e` → OAuth consent screen → **Test users** memuat
      Gmail profesional (untuk uji cepat).
- [ ] OAuth consent screen sudah **PUBLISH APP** (agar refresh token tidak
      kedaluwarsa 7 hari).
- [ ] Scope `https://www.googleapis.com/auth/calendar.events` terdaftar di
      consent screen.
- [ ] `MALVA_GOOGLE_CLIENT_ID` & `MALVA_GOOGLE_CLIENT_SECRET` terisi di server.
- [ ] `GET /v1/professionals/{id}/meet-status` mengembalikan `{"ready": true}`.
- [ ] "Create Meeting" menghasilkan link `meet.google.com`.

---

## 7. Branding terverifikasi ≠ selesai

Setelah *branding* OAuth consent screen disetujui Google (nama aplikasi & logo
tampil tanpa peringatan), banyak yang mengira integrasi sudah beres. **Tidak.**
`invalid_grant` / `invalid_client` masih bisa muncul bila konfigurasi di bawah
ini belum lengkap. Bila penukaran authorization code gagal, server kini
membalas kode mesin yang jelas (lihat tabel di bagian 8) — bukan lagi pesan
opaque "gagal menukar authorization code".

Checklist konsol Google Cloud (`malva-7084e`):

1. **Publishing status harus `In production`.** Bila masih `Testing`, refresh
   token hanya berlaku 7 hari. Buka **OAuth consent screen** → **Publish app**.
2. **Data Access wajib memuat scope `https://www.googleapis.com/auth/calendar.events`.**
   Buka **OAuth consent screen** → **Data Access** → **Add or remove scopes**,
   pastikan scope Calendar Events terdaftar. Tanpa ini Google menolak
   memberikan token untuk scope tersebut.
3. **Google Calendar API harus ENABLED.** Buka **APIs & Services → Library** →
   cari **Google Calendar API** → **Enable**. Scope yang diizinkan pengguna
   tetap tidak berguna bila API-nya mati.
4. **Client yang dipakai adalah OAuth client tipe `Web application` yang sama
   dengan `MALVA_GOOGLE_CLIENT_ID`.** Penukaran authorization code memakai
   `client_id` + `client_secret` di server; bila `MALVA_GOOGLE_CLIENT_ID`
   menunjuk ke client Android/iOS (bukan Web), Google membalas
   `invalid_client`/`unauthorized_client`. Cocokkan nilainya di
   **APIs & Services → Credentials**.
5. **Bila muncul `invalid_grant`:** authorization code bersifat **sekali pakai**
   dan berumur pendek. Cabut akses Malva di
   <https://myaccount.google.com/permissions> (**Malva → Remove access**), lalu
   dari aplikasi tekan **"Hubungkan Google Calendar"** lagi. Aplikasi memaksa
   otorisasi baru pada percobaan ulang agar Play Services tidak mengembalikan
   otorisasi lama.

---

## 8. Kode mesin penukaran token

`POST /v1/auth/google-token-exchange` kini membalas `400`/`422` dengan `code`
mesin di bawah ini (plus `google_error`/`google_error_description` dari Google
bila ada). UI Flutter memakai `code` untuk menampilkan pesan actionable.

| `code` | HTTP | Arti | Tindakan |
|---|---|---|---|
| `google_code_kedaluwarsa` | 400 | Google menolak code (`invalid_grant`): sudah dipakai / kedaluwarsa | Cabut akses di myaccount.google.com/permissions lalu hubungkan ulang |
| `google_konfigurasi_server` | 400 | `invalid_client`/`unauthorized_client`: client ID/secret server tidak cocok | Admin: samakan `MALVA_GOOGLE_CLIENT_ID`/`SECRET` dengan OAuth client Web |
| `google_penukaran_gagal` | 400 | Kegagalan lain saat menukar code (termasuk gangguan jaringan) | Coba lagi; bila berulang hubungi admin |
| `google_identitas_gagal` | 422 | Code sudah ditukar tetapi identitas Google tidak bisa dipastikan | Tekan "Hubungkan Google Calendar" lagi (code lama sudah terpakai) |

> Catatan penting: kegagalan setelah code terpakai **tidak pernah** membalas
> `401`. `401` membuat klien mengira access token Malva kedaluwarsa, me-refresh,
> lalu mengirim ulang code yang sama — dijamin `invalid_grant`. Karena itu
> kegagalan identitas memakai `422`.

### Scope yang WAJIB diminta: `openid` + `email` + `profile` + `calendar.events`

Aplikasi Flutter **tidak** boleh hanya meminta `calendar.events`. Saat
mengaktifkan Google Calendar, klien meminta empat scope sekaligus
(`GoogleAuthService.calendarAuthScopes`):

```
openid
email
profile
https://www.googleapis.com/auth/calendar.events
```

Alasannya, setelah authorization code ditukar, server perlu memastikan
**identitas** akun Google (untuk mencocokkan dengan akun Malva yang menautkan):

1. **`openid` adalah syarat `id_token`.** Token endpoint Google hanya
   mengembalikan `id_token` bila scope `openid` ikut diminta. Tanpa `openid`,
   `id_token` selalu kosong sehingga server tidak bisa memvalidasi identitas
   dari token itu.
2. **Endpoint UserInfo mensyaratkan `openid profile`.** Sebagai fallback,
   server memanggil `https://www.googleapis.com/oauth2/v3/userinfo` memakai
   access token hasil penukaran. Dokumentasi OpenID Connect Google menyatakan
   endpoint ini mensyaratkan `openid` + `profile` (klaim `email` opsional lewat
   scope `email`). Access token yang hanya punya `calendar.events` akan
   ditolak `403`, sehingga fallback pun gagal. `profile` dan `email` adalah
   scope **non-sensitif** — tidak menambah proses verifikasi Google.

Akibatnya, bila `openid`/`profile` tidak diminta, kedua jalur identitas
mustahil berhasil dan `POST /v1/auth/google-token-exchange` membalas **`422
google_identitas_gagal`** — meskipun penukaran kode dan pemberian izin Calendar
sendiri sukses. Karena itu `openid`, `email`, dan `profile` **wajib**
disertakan bersama `calendar.events`; jangan menghapusnya dari daftar scope
klien (ada test regresi `test/google_auth_service_scopes_test.dart` yang
menjaganya).

---

## 9. Mode Testing: umur refresh token 7 hari

Pemilik produk memutuskan OAuth consent screen Google **tetap berstatus
*Testing*** agar tidak perlu menempuh verifikasi Google (yang memerlukan
penjelasan scope, video demo, dan privacy policy). Konsekuensinya harus
dikelola, bukan dibiarkan.

### a. Kenapa Testing tetap boleh

- Tidak perlu proses verifikasi Google; cocok selama aplikasi belum butuh
  pemakaian publik penuh.
- Cukup untuk mengoperasikan Malva dengan sejumlah profesional terbatas yang
  terdaftar sebagai **Test user**.

### b. Batas 100 Test user

- Consent screen mode *Testing* hanya mengizinkan maksimal **100 akun Google**
  terdaftar sebagai **Test user** (OAuth consent screen → **Test users**).
- Bila jumlah profesional aktif akan melampaui 100, aplikasi **harus**
  di-*publish* (lihat bagian 2b) — saat itu refresh token tidak lagi dibatasi
  7 hari.

### c. Batas 7 hari + perpanjangan otomatis (mekanisme baru)

Selama *Testing*, Google hanya menerbitkan refresh token berlaku **7 hari**
sejak consent. Sebelumnya aplikasi tidak punya mekanisme apa pun: begitu hari
ke-8, `googleCalendarReady` gagal, link Meet tidak bisa dibuat, dan profesional
baru sadar saat menekan "Hubungkan Google Calendar". Sekarang batas itu
**dikelola**, dan sepenuhnya **senyap bagi pengguna**:

1. **Server mencatat tanggal grant** terpisah dari `updated_at`
   (`google_oauth_tokens.refresh_token_issued_at`). Auto-refresh access token
   jangka pendek **tidak** mereset tanggal ini — hanya penukaran authorization
   code (consent baru) yang memperbaruinya.
2. **`meet-status` memberi tahu lebih awal.** Saat umur grant mencapai
   `TTL-2` hari, `reason` menjadi `token_hampir_kedaluwarsa` (link Meet **masih**
   bisa dibuat), lengkap dengan `refresh_token_expires_in_days`. Ini hanya
   status di layar — **tidak ada** push, banner, atau dialog.
3. **Refresh access token sebelum habis, pemeliharaan setiap 7 hari.** Sweeper
   10 menit menjalankan `RunGoogleTokenRefresh` untuk profesional aktif dengan
   identitas Google yang masih cocok. Access token (biasanya berlaku sekitar
   satu jam) diperbarui bila sisa umurnya ≤15 menit. Jadwal pemeliharaan **7 hari**
   menjadi batas cadangan bagi access token yang berumur lebih panjang, bukan
   pengganti refresh sebelum expiry. `google_oauth_tokens.last_refreshed_at`
   dicatat atomik bersama access token dan expiry; refresh token rotasi ikut
   disimpan. Token `invalid_grant` dihapus agar tidak dicoba tanpa akhir.
   **Tidak ada notifikasi** baru ke pengguna. Migrasi 030 menghapus notifikasi
   `google_calendar_expiring` lama beserta antrean outbox; kegagalan hanya masuk
   log operator tanpa token atau body respons Google.
4. **Satu tombol perpanjangan.** Kartu Akun Google menampilkan tombol
   **"Perbarui izin sekarang"** yang memaksa otorisasi Google **baru** (fresh
   consent), sehingga refresh token diterbitkan ulang dan berlaku 7 hari lagi.

> **Jujur soal batas 7 hari.** Untuk OAuth External dengan scope Calendar,
> status **Testing** membatasi refresh token sampai tujuh hari. **Tidak ada cara
> programatik untuk memperpanjangnya**: refresh hanya menjaga *access token*
> segar dan menangkap rotasi. Status **Production** menghapus batas khusus
> Testing, bukan menjamin token abadi; token masih bisa dicabut atau berakhir
> karena kebijakan Google lain. Publish app (langkah berikut), lalu consent
> ulang bila token Testing lama sudah tidak berlaku.

**Langkah persis mem-publish (menghapus batas 7 hari):**

1. Buka <https://console.cloud.google.com/apis/credentials/consent?project=malva-7084e>
   → pastikan project **malva-7084e** terpilih.
2. Di halaman **OAuth consent screen**, tekan **PUBLISH APP** → **Confirm**.
3. Status berubah dari *Testing* menjadi *In production*. Setelah itu refresh
   token tidak lagi dibatasi 7 hari (pengguna masih melihat peringatan
   "unverified" sampai verifikasi formal Google disetujui — lihat bagian 3).

### d. Mematikan status "hampir kedaluwarsa" saat nanti publish

Setelah consent screen di-*publish* dan refresh token tidak lagi dibatasi 7
hari, matikan status peringatan agar tidak muncul `token_hampir_kedaluwarsa`
palsu:

```bash
# backend/.env
MALVA_GOOGLE_REFRESH_TOKEN_TTL_DAYS=0
```

`0` menonaktifkan pemeriksaan umur (`meet-status` tidak pernah mengembalikan
`token_hampir_kedaluwarsa`). Default adalah `7` selama mode *Testing*. Job
auto-refresh tetap berjalan terlepas dari nilai ini (ia hanya menjaga access
token tetap segar).

---

## 10. Fallback manual — "Tempel link Meet"

Ketika Google Calendar tidak bisa dipakai sama sekali (mis. Gmail belum
terdaftar sebagai Test user dan console belum bisa diubah), profesional **tetap
bisa menyelenggarakan sesi video** dengan menempelkan link Google Meet yang ia
buat sendiri.

**Endpoint:** `PUT /v1/care-sessions/{session_id}/meet-link`

```bash
curl -X PUT "$MALVA_API_BASE/v1/care-sessions/<session_id>/meet-link" \
  -H "Authorization: Bearer <access_token_profesional>" \
  -H "Content-Type: application/json" \
  -d '{"meet_url":"https://meet.google.com/abc-defg-hij"}'
```

Aturan (ditegakkan server, 400 bila dilanggar):

- **Hanya profesional pemilik sesi** yang boleh menempelkan link manual.
- Sesi harus **video** dan berstatus **scheduled**.
- URL wajib **`https`**, host tepat **`meet.google.com`**, panjang ≤ 500
  karakter, path tidak kosong. Provider lain (zoom.us dsb.) belum didukung dan
  ditolak.
- Fallback ini **tidak** melemahkan gerbang booking berbayar: `createBooking`
  tetap menolak `409 meet_belum_aktif` sebelum bayar. Manual link hanya untuk
  sesi yang **sudah ada**.

Di aplikasi: kartu sesi video berstatus "menunggu link" menampilkan tombol
**"Buat link Meet"** (otomatis) dan **"Tempel link Meet"** (manual). Setelah
disimpan, link langsung tampil ke pasien di detail sesi.

---

## Lihat juga

- `docs/GOOGLE_SIGNIN_SETUP.md` — Login dengan Google (identitas, bukan Calendar).
- `docs/API_ROUTES.md` — daftar endpoint (termasuk `meet-status` dan `meet-link`).
