# Email Bisnis Gratis untuk Domain malva.web.id

Perbandingan provider email kustom **benar-benar gratis (tanpa langganan)**
untuk domain `malva.web.id` (DNS dikelola idwebhost).

Diperbarui: Oktober 2026.

---

## Ringkasan cepat

| Provider | Gratis selamanya? | Kuota gratis | Webmail/HP | IMAP/SMTP | Alias | Catatan |
|---|---|---|---|---|---|---|
| **Zoho Mail** | ✅ Ya (Forever Free) | 1 domain, **5 user**, 5 GB/user | ✅ | ❌ (tidak termasuk) | ✅ 1 alias/domain + catch-all | Data center pilihan; IMAP/POP hanya di paket berbayar |
| **ImprovMX** | ✅ Ya | Unlimited alias, forwarding | ❌ (forward saja) | ❌ | ✅ | Hanya meneruskan ke Gmail pribadi; kirim-balik via SMTP opsional |
| **Cloudflare Email Routing** | ✅ Ya | Unlimited alias, forwarding | ❌ (forward saja) | ❌ | ✅ | Butuh DNS di Cloudflare; meneruskan ke inbox mana pun |
| **Mailgun** | ⚠️ Terbatas | Trial 30 hari → bayar | ❌ | API | — | Untuk transaksional, bukan inbox staf |
| **Yandex Mail 360** | ⚠️ Per-region | 1 domain, 1.000 user (kadang ditutup untuk pendaftaran baru) | ✅ | ✅ | ✅ | Ketersediaan pendaftaran berubah-ubah |
| **Google Workspace** | ❌ | — | ✅ | ✅ | ✅ | Berbayar (bukan opsi) |
| **Microsoft 365** | ❌ | — | ✅ | ✅ | ✅ | Berbayar (bukan opsi) |

**Rekomendasi utama:**

1. **Zoho Mail (Forever Free)** — pilihan terbaik bila kamu mau mailbox
   sungguhan (login webmail + aplikasi HP) dengan alamat
   `nama@malva.web.id`, hingga 5 akun. Gratis permanen, tanpa kartu kredit.
2. **ImprovMX / Cloudflare Email Routing** — bila cukup **meneruskan** email
   `nama@malva.web.id` ke Gmail pribadi (gratis, setup 5 menit).

Boleh dikombinasikan:

- Zoho untuk staf utama (mis. `halo@`, `dr.ayu@`)
- ImprovMX catch-all untuk sisanya → Gmail pribadi

---

## Opsi 1 — Zoho Mail Forever Free (REKOMENDASI)

Kelebihan: mailbox penuh (webmail + aplikasi Android/iOS), 5 user, 5 GB/user,
1 domain, calendar. Kekurangan: tanpa IMAP/POP (cukup lewat webmail/app).

### Langkah setup

1. **Daftar organisasi** di https://workplace.zoho.com/signup?type=org&plan=free
   (pilih **Forever Free Plan**). Gunakan akun Zoho (bisa masuk dengan Google
   `amiradiandra73@gmail.com`).
2. Masukkan **domain**: `malva.web.id` (jangan pilih "beli domain baru").
3. **Verifikasi kepemilikan domain** — pilih cara **CNAME**:
   - Tambahkan di panel DNS idwebhost sebuah record:
     ```
     Tipe:  CNAME
     Nama:  zb<kode-unik-dari-zoho>      (contoh: zb12345678)
     Nilai: zmverify.zoho.com
     TTL:   3600 (default)
     ```
   - Klik Verify di Zoho (bisa sampai 30 menit propagasi).
4. **Aktifkan Zoho Mail (MX records)** — tambahkan **3 record MX** di
   idwebhost, GANTI record MX lama milik idwebhost:

   | Prioritas | Nilai |
   |---|---|
   | 10 | `mx.zoho.com` |
   | 20 | `mx2.zoho.com` |
   | 50 | `mx3.zoho.com` |

   Lalu tambahkan **SPF** (TXT):
   ```
   Nama:  @
   Nilai: v=spf1 include:zoho.com ~all
   ```
   (Opsional, dianjurkan) DKIM: Zoho memberi record TXT `zoho._domainkey`
   → tambahkan di DNS.

5. **Buat user mailbox** di Zoho Admin:
   - `halo@malva.web.id` (kontak umum)
   - `amiradiandra73@malva.web.id` (pemilik/admin)
   - dst (maks 5 user).
6. **Uji**: kirim email dari Gmail → `halo@malva.web.id`, lalu balas dari
   webmail Zoho. Pastikan SPF pass (buka menu "Show original").

> Catatan: record MX harus dikelola lewat **idwebhost DNS panel**, jangan
> hapus record `A` / `CNAME` lain (api, www) saat menambahkan MX.

---

## Opsi 2 — ImprovMX (penerusan Gratis)

Kelebihan: gratis tanpa batas alias, setup hanya 1 MX + 1 SPF.
Kekurangan: hanya menerima & meneruskan (bukan mailbox penuh); balasan
dikirim dari Gmail pribadi (kecuali set SMTP).

1. Daftar https://improvmx.com dengan `amiradiandra73@gmail.com`.
2. Tambah domain `malva.web.id`.
3. ImprovMX menampilkan 2 record MX + 1 TXT SPF. Tambahkan di idwebhost:

   | Tipe | Nama | Nilai | Prioritas |
   |---|---|---|---|
   | MX | `@` | `mx1.improvmx.com` | 10 |
   | MX | `@` | `mx2.improvmx.com` | 20 |
   | TXT | `@` | `v=spf1 include:spf.improvmx.com ~all` | — |

4. Buat alias: `halo@malva.web.id → amiradiandra73@gmail.com`, dst.
5. Uji kirim dari luar.

---

## Opsi 3 — Cloudflare Email Routing

Bila nanti DNS dipindah ke Cloudflare (gratis), Email Routing meneruskan
`apa pun@malva.web.id` ke Gmail dengan 1 klik. Tidak untuk saat ini karena
DNS masih di idwebhost.

---

## Rekomendasi konkret untuk Malva

1. Pakai **Zoho Mail Forever Free** untuk `halo@malva.web.id` dan akun
   profesional (maks 5 akun) — gratis permanen, tanpa langganan.
2. Gunakan alamat itu untuk:
   - Registrasi layanan pihak ketiga (Firebase/Zoho/partnership)
   - Kontak resmi aplikasi & consent form
   - Login profesional (opsional di masa depan)
3. Bila ada lebih banyak alias (mis. email masing-masing dokter > 5),
   gunakan **ImprovMX** catch-all yang diteruskan ke Gmail.

## Data yang perlu disiapkan dari idwebhost

Saat menambahkan record di atas, jangan menimpa:

```
A     @     -> (nanti: IP VM, bila mau landing page di root domain)
A     api   -> 48.193.44.179   (SUDAH ADA — jangan dihapus)
A     www   -> 48.193.44.179   (opsional, agar www.malva.web.id juga live)
```

Hanya **MX** dan **TXT (SPF)** yang ditambahkan/diganti untuk email.
