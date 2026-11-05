# Verifikasi perbaikan alur pasien — 5 November 2026

## Dasar pemeriksaan

- APK masukan: `Malva-release-2026-11-04-e5395cb-arm64-v8a.apk`.
- Source dasar: `e5395cb`; branch kerja `codex/fix-patient-booking-chat-notifications`.
- Package Android: `id.malva.app`, versi `0.1.2+3`.
- SHA-256 APK masukan: `A7988A3D004C376C42A335667266160360D3EEE5EB7079C19E2CB2BCE9EBE27E`.
- Tiga agent menangani booking/payment, notifikasi, dan screening; hasilnya direview lintas agent. Root mengerjakan Therapy Record dan verifikasi integrasi.
- Tidak ada migrasi, dependency, endpoint HTTP, atau field DTO HTTP baru. Callback Snap mengikuti kontrak provider yang sudah tersedia.

## Perubahan dan perilaku

| Area | Hasil perubahan |
| --- | --- |
| Booking profesional | Request paket menyelesaikan profesional dari paket yang sah; `care_packages.booking_id` mengikat booking yang tepat. Retry/concurrent request dengan intent pending yang sama memakai paket, booking dan pembayaran yang sama. |
| Payment/resume | Referensi pending dipertahankan setelah gangguan gateway. Lanjut bayar memakai relasi booking yang tepat; fallback legacy hanya untuk kecocokan tunggal yang sah. Pembayaran lunas diprioritaskan daripada duplikat pending legacy. |
| Rekonsiliasi | Tombol cek status, polling, dan lifecycle refresh membaca status backend yang memeriksa Midtrans beserta nominal. Parameter status pada deep link tidak dapat melunasi transaksi. Aktivasi, pembatalan dan replay tetap idempoten. |
| Kembali dari sandbox | Checkout Android dimiliki aplikasi, termasuk popup simulator. Status lunas yang terverifikasi menutup checkout. Callback memakai referensi; alur kembali mengambil alih polling lama dan mempertahankan/memulihkan konteks paket. |
| MyCare Paket | Filter `pending_payment`, `active`, `cancelled`; melanjutkan pembayaran menargetkan paket yang dipilih. |
| Screening | Formula CF diuji terhadap nilai aktual, batas PHQ/GAD, AND/minCF, kombinasi evidence dan rule sekali jalan. Label “Pasti” diganti dengan `CF 68%` dan penjelasan dukungan rule. |
| Therapy Record | Pasien memilih record terapi lalu memakai endpoint share yang sudah berotorisasi. Tidak ada pengiriman pesan chat kedua. Profesional membuka detail melalui endpoint read berotorisasi. UI memeriksa pesan tersimpan sebelum melaporkan sukses. |
| Notifikasi pasien | Hanya chat sesi aktif melalui FCM, reminder goals harian dan waktu obat secara lokal. |
| Notifikasi profesional | Hanya chat sesi aktif melalui FCM. |
| Pengulangan notifikasi | Dispatch memeriksa eligibility lagi, menekan job lama yang dilarang, membatasi retry, dan memakai identitas tray stabil. Jadwal lokal, restore sesi dan registrasi FCM dilindungi dari respons akun lama serta pergantian A→B→A. Alarm obat usang juga direkonsiliasi setelah restart. |

Angka mild sebelumnya benar secara aritmetika: `0,72 × min(0,95; 0,95) = 0,684`, dibulatkan menjadi **CF 68%**. Bobot CF merupakan bobot rule internal yang belum dikalibrasi menjadi probabilitas klinis; angka ini tidak membuktikan diagnosis 68% pasti. Cutoff instrumen, tingkat gejala dan penanganan crisis flag dipertahankan.

## Verifikasi lokal

Seluruh pengujian database memakai PostgreSQL 18 lokal berisi fixture sintetis dan semua 31 migrasi, tanpa DSN produksi. Paket Go dijalankan serial agar fixture antarpaket tidak bertabrakan.

| Pemeriksaan | Hasil |
| --- | --- |
| Flutter seluruh suite, `scripts/flutter_test.ps1 --no-pub --reporter expanded` | **616 tes lulus**, exit 0 |
| Go seluruh suite, `go test -p 1 -count=1 -coverprofile=coverage.out ./...` | **Lulus**, termasuk integrasi PostgreSQL |
| `go build ./...`, `go vet ./...` | **Lulus** |
| Generator API `-check` | **Lulus**, 141 endpoint + 1 static |
| Konvensi Go/WIB, sinkronisasi env, migrasi, coverage | **Lulus**; 19 env dan 31 migrasi |
| Review independen | Temuan booking, return callback, Therapy Record dan lifecycle akun diperbaiki beserta regresinya |
| Flutter analyzer | **Lulus**, tidak ada issue |
| Gate WIB Dart dan `git diff --check` | **Lulus** |
| Build Android release target arm64 | **Lulus**, `scripts/build_release_apk.ps1`, 107,5 detik Gradle |
| Pemeriksaan signature/ABI/hash APK baru | **Lulus**, signature sama dengan APK masukan; Flutter `libapp.so` dan `libflutter.so` untuk arm64 |

Coverage paket dengan ambang proyek: auth 69,0%; clock 100%; config 97,0%; inference 92,7%; logging 70,0%; notify 61,4%; payment 88,5%; screening 90,0%; security 24,7%. Semua memenuhi ambang masing-masing.

Log verifikasi tersedia di `D:/Project/Malva/2026-07-09/_qa_2026_11_05/`, terutama `flutter_full_final.log`, `flutter_analyze_final.log` dan `go_full_final.log`. Setelah full suite, satu import test yang berlebih dihapus berdasarkan analyzer; keempat test registrasi FCM dijalankan ulang dan lulus. Tidak ada source runtime berubah setelah full suite. Log RED terdahulu adalah bukti reproduksi/harness yang kemudian diperbaiki; gunakan log final untuk hasil akhir.

## Firebase dan batas verifikasi

Konfigurasi lokal cocok dengan metadata Firebase yang diperiksa secara read-only: project `malva-7084e`, sender `910496426601`, Android app `1:910496426601:android:aa5c7b5ac0dbcdbdd290f8`, package `id.malva.app`.

Credential provider backend lokal tidak disediakan; pemeriksaan ini tidak membuktikan credential, versi backend produksi, campaign Firebase Console, atau delivery perangkat. Tidak ada perangkat Android terhubung pada pemeriksaan awal. Transaksi sandbox nyata dan pengiriman FCM di perangkat fisik belum diuji end-to-end. `go test -race` tidak dijalankan pada host ini.

FCM TTL nol sengaja mencegah push chat lama muncul setelah perangkat kembali online; pesan tetap tersedia dalam riwayat chat. Push yang sudah diterima FCM/OS sebelum pembaruan tidak bisa ditarik kembali oleh filter aplikasi.

Jika gateway menerima order tetapi respons Snap hilang, aplikasi mempertahankan referensi yang sama dan menyediakan pemeriksaan status/petunjuk pemulihan. Aplikasi tidak membuat order baru diam-diam; provider tidak menyediakan API pemulihan token Snap dari referensi pada kontrak yang digunakan.

## Penerapan

Perubahan source dan APK belum men-deploy backend produksi. Deploy backend yang berisi perbaikan transaksi dan worker notifikasi, lalu pasang APK baru; APK saja tidak mengganti perilaku server lama. Tidak diperlukan migrasi baru. Verifikasi staging/perangkat mengikuti `docs/FCM_TESTING.md` dan skenario pembayaran nyata dengan akun sintetis.

Tidak ada transaksi/paket legacy produksi yang dihapus atau digabung secara massal. Status/refund legacy yang memerlukan rekonsiliasi tetap memakai jalur pemeriksaan yang sudah ada.

Rekomendasi push berikutnya, **belum diaktifkan**: konfirmasi hasil pembayaran/refund, pengingat atau perubahan jadwal sesi, dan pemberitahuan keamanan akun. Ketiganya perlu keputusan produk mengenai waktu, penerima, serta deduplikasi sebelum diterapkan.

## Artefak baru

- APK: `D:/Project/Malva/2026-07-09/_apk_download/Malva-release-2026-11-05-patient-fixes-arm64-v8a.apk`.
- Ukuran: 29.201.684 byte (27,8 MiB), build 5 November 2026 pukul 09:05 WIB.
- SHA-256: `E5E75A807C8F72CB60B48246934FCE9E7766D0773A1CC7412383D2A761C3C329`.
- Sertifikat SHA-256: `965f7430ec7f67a44b7a99e83f155e601116ff16c18fa8db57a4e79de4f2d300`, sama dengan APK masukan.
- Package/versi tetap `id.malva.app`, `0.1.2+3`; min SDK 24, target SDK 36.
- Target Flutter arm64-v8a. `aapt` juga mencantumkan armeabi-v7a/x86_64 karena dependency membawa `libdartjni.so` dan `libdatastore_shared_counter.so`; kedua ABI itu tidak membawa engine/aplikasi Flutter dan bukan target APK ini.
- Manifest hasil build memuat Activity sandbox privat dan intent `malva://payment/return`.
- APK masukan tidak ditimpa. Salinan build juga tersedia di Desktop sesuai skrip release proyek.
