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
   | `server_not_configured` | Server belum punya `MALVA_GOOGLE_CLIENT_SECRET` | Hubungi admin/deployment |
   | `ready` | Siap membuat link Meet | — |

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

## Lihat juga

- `docs/GOOGLE_SIGNIN_SETUP.md` — Login dengan Google (identitas, bukan Calendar).
- `docs/API_ROUTES.md` — daftar endpoint (termasuk `meet-status` dan `meet-link`).
