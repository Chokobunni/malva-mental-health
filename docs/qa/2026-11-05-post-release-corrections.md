# Validasi source Malva 0.1.3+4

Laporan ini melanjutkan perbaikan tahap pertama pada `2026-11-05-patient-flow-repairs.md`. APK tahap pertama belum menyelaraskan backend produksi. User mengizinkan push/deploy langsung, kemudian APK baru setelah deploy. Bukti operasional deployment dan checksum artefak dicatat pada manifest rilis setelah revision final diketahui.

## Perubahan dan penyebab

- Backend produksi sebelum rilis tertinggal 19 commit dari source APK masukan. Kontrak kehadiran `attended`, booking paket dan pembatasan notifikasi belum tersedia. Deploy backend diperlukan agar APK dan server memakai kontrak yang sama.
- Profesional: kartu video tidak lagi menyempit akibat lebar minimum tombol global; kedua jalur Detail pasien meneruskan sesi/API profesional aktif. Regresi memakai lebar 360px; tes kehadiran memastikan marker tidak menutup sesi atau menggandakan earnings.
- Pasien: home menampilkan Sesi berjalan dan Video call mendatang beserta foto profesional. Kedua scope memiliki status kosong/error/retry sendiri. Respons akun sebelumnya tidak dapat menimpa akun aktif. Pasien memakai link Meet yang sudah ada.
- Resume pembayaran mengikat paket legacy yang dipilih melalui endpoint booking yang tersedia, menghindari kandidat milik paket lain. Retry memakai token hasil refresh. Refresh ditolak tidak menunggu dirinya sendiri; rotasi token dipersistensikan dan respons akun lama tidak dapat mengubah akun baru. Logout web segera membersihkan auth sebelum menunggu revoke server.
- FCM memakai data-only dengan TTL nol. Validasi foreground/background memeriksa pemilik, peran, sesi aktif dan jam server. Android memblokir auto-display payload lama, menonaktifkan delegation, serta membersihkan notifikasi shade historis pada upgrade/start/pergantian akun. Alarm goals/obat dan riwayat in-app dipertahankan.
- `retire_notification_backlog.sql` menghentikan pengiriman transport historis memakai cutoff WIB setelah seluruh worker berhenti. Tidak ada penghapusan paket, transaksi, chat atau riwayat notifikasi.
- Seluruh perbaikan tahap pertama dipertahankan: transaksi idempoten, filter paket, rekonsiliasi Midtrans, callback sandbox, berbagi Therapy Record dan penjelasan CF 68%.

## Verifikasi source

| Pemeriksaan | Hasil |
| --- | --- |
| Full Flutter suite | 645 tes lulus, exit 0 |
| Flutter analyzer | Tidak ada issue, exit 0 |
| Full Go suite dengan PostgreSQL lokal nyata | Lulus, termasuk server/store |
| Go build/vet/golangci-lint | Lulus; lint 0 issue |
| API documentation check | 141 endpoint + 1 static sinkron |
| Env/migration/convention/coverage gates | Lulus; 19 env, 31 migrasi |
| Dart WIB/platform isolation | Lulus tanpa pengecualian baru |
| Native notification transport regression | Lulus |
| Android release x64 + instalasi emulator API 36 | Lulus, versi 0.1.3+4; sertifikat sama dengan APK masukan |
| Broadcast sintetis legacy + chat tanpa akun/sesi sah | Diterima receiver native/background; tidak ada notifikasi Malva diposting atau fatal exception |
| Review lintas agent | Temuan diperbaiki dan diuji sebelum source dibekukan |

Coverage paket berambang: auth 69,0%; clock 100%; config 97,0%; inference 92,7%; logging 70,0%; notify 62,3%; payment 88,5%; screening 90,0%; security 24,7%.

Full suite mengungkap override API tiruan web yang belum menerima durasi dan fixture sesi mendatang bertanggal tetap yang sudah lewat. Keduanya diselaraskan tanpa mengurangi assertion; suite lengkap kemudian lulus. Analyzer juga dibersihkan dari import/assertion berlebih pada tes cold notification tap.

Build native pertama mengungkap Firebase superclass tersembunyi dari compile classpath aplikasi oleh dependency `implementation` FlutterFire. `compileOnly` mengekspos versi messaging 25.1.0 yang sudah dipakai runtime, tanpa menambah artefak/versi runtime. Pin kompilasi wajib mengikuti versi SDK FlutterFire saat upgrade. Build ulang lulus. Manifest hasil merge memakai hanya service Malva untuk MESSAGING_EVENT, directBootAware=true, cleanup receiver dan delegation=false. Stock SDK fallback dihapus agar tidak melewati gate sebelum unlock pertama setelah reboot.

Log lokal: `D:/Project/Malva/2026-07-09/_qa_2026_11_05/flutter_release_gate.log`, `analyze_release_gate.log`, `go_postrelease_final.log`. Pengujian x64 emulator adalah validasi Android; APK distribusi arm64 harus dihasilkan setelah push dan backend deploy.

## Batas dan pemeriksaan operasional

Tidak ada skema, endpoint, DTO HTTP atau dependency baru. Nilai parameter API tiruan mengikuti kontrak yang sudah ada. Tidak ada bulk delete transaksi/paket legacy. Perubahan token dan retry harus mempertahankan identitas akun dan intent pembayaran yang sama.

Go race dijalankan oleh CI Linux karena host Windows ini tidak menyediakan toolchain CGO. Delivery FCM perangkat fisik, transaksi Midtrans sandbox nyata dan akun pengguna tidak dipakai untuk pengujian lokal. Pengujian sintetis tidak membuktikan jalur end-to-end perangkat fisik.

Push aktif hanya chat dalam sesi aktif untuk kedua peran. Goals harian dan waktu minum obat dijadwalkan lokal bagi pasien. Rekomendasi berikutnya tetap belum diaktifkan: hasil pembayaran/refund, perubahan jadwal sesi, serta keamanan akun.
