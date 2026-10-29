# Smoke Test — Assessment Record, Therapy Record & Health Record

Checklist pengujian manual di perangkat/emulator untuk perubahan:
- `bdb1f40` — pemisahan hasil asesmen vs hasil terapi + sinkronisasi Health Record
- `e98f4bf` — rename label menjadi "Therapy Record" / "Assessment Record"

Gunakan akun **pasien** yang sudah punya riwayat: minimal 1 screening PHQ-9/GAD-7,
1 worksheet DASS-21 atau WHO-5 tersimpan, dan 1 worksheet terapi (mis. ABCDE)
tersimpan. Kalau datanya belum ada, isi dulu di aplikasi sebelum mulai.

Build:
```powershell
scripts\build_release_apk.ps1
```
(Pakai selalu skrip itu supaya `MALVA_GOOGLE_CLIENT_ID` ikut terpasang.)

Tandai setiap langkah LULUS / GAGAL. Kalau GAGAL, catat: langkah, yang terjadi,
yang seharusnya terjadi, plus screenshot.

---

## A. Halaman Assessment → Assessment Record

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| A1 | Buka menu **Assessment** dari Home | Judul halaman tetap "Assessment", ada section baru **"Assessment Record"** di bawah "Assessment Lanjutan" |
| A2 | Lihat section Assessment Record | Muncul maksimal 3 hasil terbaru (DASS-21/WHO-5 dan/atau screening PHQ-9 + GAD-7), plus tombol **"Lihat semua"** |
| A3 | Tap salah satu kartu | Bottom sheet terbuka: judul + tanggal, kartu skor (DASS-21 tiga subskala / WHO-5 skor 0–25, atau PHQ-9 & GAD-7), dan catatan "Skor assessment adalah alat bantu screening, bukan diagnosis." |
| A4 | Scroll bottom sheet A3 sampai bawah | Isi bisa di-scroll penuh, tidak terpotong; tutup dengan swipe ke bawah |
| A5 | Tap **"Lihat semua"** | Halaman "Assessment Record" terbuka dengan judul dan **SEMUA** riwayat, urut paling baru di atas |
| A6 | Tarik-tarik daftar A5 ke bawah (pull-to-refresh) | Daftar termuat ulang, indikator refresh muncul |
| A7 | Pastikan di halaman A5 **tidak ada** worksheet terapi | Tidak ada entri ABCDE/latihan napas/thought record di daftar ini |

## B. Therapy Record (dulu "Folder Therapy")

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| B1 | Buka menu **More** | Tile tertulis **"Therapy Record"** (bukan "Folder Therapy") |
| B2 | Tap tile tersebut | Judul halaman "Therapy Record" |
| B3 | Lihat daftar | **Hanya** worksheet terapi. WHO-5 dan DASS-21 **tidak boleh** muncul |
| B4 | Tap salah satu worksheet | Detail bisa dibuka (ringkasan + jawaban) |
| B5 | Tap **Bagikan** pada satu worksheet | Muncul daftar profesional yang punya paket sesi aktif; setelah memilih, muncul snackbar "Worksheet dibagikan ke profesional." |
| B6 | Tap **Hapus** pada satu worksheet | Dialog konfirmasi muncul; setelah hapus, item hilang dari daftar |
| B7 | Isi satu worksheet terapi lalu tap **"Simpan ke Therapy Record"** | Snackbar menyebut "tersimpan di Therapy Record"; item muncul di daftar B3 |
| B8 | Hapus semua worksheet terapi | Muncul empty state "Belum ada therapy record" (bukan "Belum ada worksheet") |

## C. Health Record

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| C1 | Buka menu **More → Health Record** | Bagian **Diagnosis** dan **Medication** tampil seperti sebelumnya (tidak berubah) |
| C2 | Scroll ke bagian **Record** | Muncul dokumen unggahan + hasil asesmen + hasil terapi dalam **satu daftar**, urut terbaru di atas |
| C3 | Periksa kartu dokumen | Keterangan memuat tipe file, mis. "Dokumen • PDF • 20/10/2026 09:15" |
| C4 | Periksa kartu asesmen | Keterangan memuat ringkasan skor, mis. "Assessment • WHO-5 5/25 (20%) • ..." |
| C5 | Tap chip filter **Assessment** | Hanya entri asesmen yang tersisa; dokumen dan terapi hilang |
| C6 | Tap chip filter **Therapy** | Hanya entri terapi yang tersisa |
| C7 | Tap chip filter **Dokumen** | Chip tipe file (Semua/PDF/IMAGE/DOC/OTHER) **muncul**; entri asesmen & terapi hilang |
| C8 | Pilih chip **PDF** | Hanya dokumen PDF yang tersisa |
| C9 | Kembali ke chip **Semua** | Semua entri muncul lagi, chip tipe file hilang |
| C10 | Ketik di kolom **Search** sebagian judul salah satu entri | Hanya entri yang cocok yang tersisa (pencarian berlaku lintas jenis) |
| C11 | Ketik kata yang tidak ada | Muncul "Tidak ada yang cocok" (bukan "Belum ada record") |
| C12 | Tap entri asesmen/terapi | Bottom sheet detail yang sama seperti A3 |
| C13 | Saat halaman baru dibuka (jaringan lambat) | Muncul baris kecil "Memuat assessment & therapy record…" di atas chip filter, **tanpa** spinner besar yang menahan layar |
| C14 | Nyalakan mode pesawat lalu buka Health Record | Diagnosis/Medication tetap tampil bila sudah pernah dimuat; bila gagal, hanya ada keterangan kecil "Therapy record belum termuat" / "Assessment record belum termuat" dan dokumen tetap terlihat |
| C15 | Tap **Add File**, unggah dokumen | Dokumen baru langsung muncul di daftar Record |

## D. Worksheet DASS-21 / WHO-5 (legenda skala)

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| D1 | Buka **Assessment → DASS-21** | Di setiap pertanyaan ada SATU baris penjelasan arti angka di ATAS tombol, mis. "0 = Tidak pernah", "1 = Jarang", "2 = Kurang dari setengah waktu", "3 = Hampir selalu" |
| D2 | Lihat deretan tombol angka | Tombol hanya berisi angka (0–3), **tanpa** teks arti di bawah angka |
| D3 | Cek bawah deretan tombol | Tidak ada teks "Ketuk salah satu pilihan untuk menjawab." |
| D4 | Tap salah satu angka | Tombol terpilih (berwarna penuh); **tidak** muncul chip "Skor: 1 — Jarang" di bawahnya |
| D5 | Ulangi D1–D4 untuk **WHO-5** | Sama: satu baris legenda di atas, tombol hanya angka 0–5, tanpa teks di bawah |
| D6 | Aktifkan TalkBack/VoiceOver, fokus ke satu tombol angka | Yang diumumkan adalah "1 — Jarang" (angka + arti), bukan angka diulang dua kali |

## E. Kondisi khusus

| # | Langkah | Hasil yang diharapkan |
|---|---|---|
| E1 | Akun pasien yang belum pernah mengisi apa pun | Section "Assessment Record" menampilkan kartu ajakan "Belum ada assessment record…"; halaman riwayat menampilkan empty state |
| E2 | Akun pasien tanpa worksheet terapi | Therapy Record menampilkan empty state "Belum ada therapy record" |
| E3 | Health Record tanpa dokumen/asesmen/terapi sama sekali | Empty state menyebut "Upload dokumen, isi assessment, atau simpan worksheet therapy" |
| E4 | Layar kecil (mis. 360dp / font scaling besar) | Tidak ada teks terpotong di chip legenda, kartu Record, atau bottom sheet detail |

---

## Ringkasan hasil

| Bagian | Jumlah langkah | Lulus | Gagal | Catatan |
|---|---|---|---|---|
| A. Assessment Record | 7 | | | |
| B. Therapy Record | 8 | | | |
| C. Health Record | 15 | | | |
| D. Legenda DASS/WHO-5 | 6 | | | |
| E. Kondisi khusus | 4 | | | |
| **Total** | **40** | | | |

Kalau ada langkah GAGAL, laporkan ke pengembang dengan format: `Bagian/langkah — yang terjadi — yang diharapkan — screenshot`.
