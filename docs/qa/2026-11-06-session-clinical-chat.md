# Validasi source Malva 0.1.4+5

Rilis ini melanjutkan seluruh perbaikan 0.1.3+4. User mengizinkan push dan deploy langsung, kemudian APK baru dari revision yang sama setelah deploy. Hasil deployment, rekonsiliasi gateway nyata, signature dan checksum APK dicatat terpisah di manifest rilis setelah commit final diketahui.

## Perubahan

- Kehadiran pasien dan profesional dicatat sendiri melalui **Hadir** dan **Tidak hadir**. Pasien tidak hadir menjadi no-show dengan kuota terpakai; profesional tidak hadir mengembalikan kuota secara idempoten. Migrasi 032 menambah empat field kehadiran, tanpa mengarang kehadiran historis dari marker lama.
- **Sesi selesai** hanya tersedia untuk profesional setelah jadwal berakhir. Status terminal tidak dapat dibuka kembali, riwayat dan ringkasan tetap terbaca, serta pendapatan diakui atomik dengan penyelesaian. Chat dan Meet ditutup pada batas akhir eksklusif menurut jam server, termasuk ketika layar tetap terbuka.
- Status Midtrans melalui GET terautentikasi tidak lagi ditolak karena tidak memiliki signature webhook. Order wajib sama persis; nominal dan fraud diperiksa, dan webhook masuk tetap memerlukan signature. Retry rekonsiliasi tidak membuat sesi atau transaksi tambahan.
- Lima alat chat profesional: goals/habit pasien dan homework baru; permintaan assessment; diagnosis dan medication; gambar/PDF privat; serta rangkuman berisi homework dan insight. Pengelolaan obat dibatasi ke psikiater terverifikasi. Mutasi klinis mengikuti izin berbagi pasien dan sesi aktif.
- Perubahan medication menyegarkan check-in pasien melalui event dalam aplikasi, dengan pemulihan saat reconnect/resume. Notifikasi push tetap terbatas pada chat sesi aktif; pengingat goals harian dan obat pasien tetap memakai penjadwalan lokal yang sudah ada.
- Unggahan privat diperiksa isinya dan hanya dapat diunduh peserta percakapan. Retry pesan, unggahan, goals dan medication mempertahankan identitas intent. Respons akun/permintaan lama tidak dapat menimpa akun atau homework terbaru; pesan realtime disaring untuk pasangan percakapan yang tepat.

## Gate lokal

| Pemeriksaan | Hasil |
| --- | --- |
| Full Flutter suite dengan coverage | 680 tes lulus, exit 0 |
| Flutter analyze | Tidak ada issue, exit 0 |
| Dart format | 294 file, tidak ada perubahan |
| Go build dan vet | Lulus |
| Full Go suite, PostgreSQL nyata, tanpa cache | Lulus, `go test -p 1 -count=1 -coverprofile=coverage.out ./...` |
| golangci-lint | 0 issue |
| API documentation | 143 endpoint + 1 static sinkron |
| Env, migrasi, convention, coverage | Lulus; 19 env dan 32 migrasi |
| Dart WIB dan isolasi platform | Lulus; tidak ada pengecualian baru |
| Review lintas agent | Temuan auth, lifecycle, retry dan respons lama ditangani; review akhir tidak menemukan P1/P2 baru |

Coverage paket berambang: auth 69,0%; clock 100%; config 97,0%; inference 92,7%; logging 70,0%; notify 62,3%; payment 88,4%; screening 90,0%; security 24,7%.

Suite penuh menemukan dua ekspektasi lama yang masih mengizinkan Join untuk sesi completed. Regresi kini membuktikan terminal menutup aksi sambil mempertahankan riwayat/ringkasan; kasus positif scheduled+attended membuktikan Hadir tetap mengizinkan chat. Tidak ada perubahan produksi yang dibuat untuk meloloskan ekspektasi lama. Lima temuan lint diperbaiki dengan cleanup defer eksplisit dan validasi UUID ekuivalen.

Percobaan Go pertama salah diurai PowerShell menjadi argumen `-coverprofile=coverage .out`. Gate diulang dengan argumen dikutip: semua paket dan ambang coverage lulus. Berkas coverage percobaan tersebut dipindah ke folder QA, tidak masuk source.

Log lokal berada di `D:/Project/Malva/2026-07-09/_qa_2026_11_06/`: `flutter_final.log`, `flutter_analyze_final.log`, `dart_format_final.log`, dan `go_final_quoted.log`. Database sintetis berada di loopback port 15439; tidak menggunakan database produksi untuk tes.

## Deployment dan batas verifikasi

Backup binary dan dump database produksi diverifikasi sebelum deployment; folder attachment privat terpisah dari uploads publik, mode 0700 milik service. Rilis menerapkan migrasi 032 sebelum restart. Pembayaran pending yang sudah ada diperiksa setelah deploy melalui endpoint rekonsiliasi aplikasi, tanpa menetapkan paid melalui SQL atau mempercayai callback klien.

Pengujian perangkat fisik dua akun, pembayaran sandbox interaktif baru, dan pengantaran FCM fisik belum dilakukan oleh suite lokal. CI Linux menyediakan race detector. Build APK release, pengecekan revision server, signature yang sama dengan versi terdahulu, versi 0.1.4+5 dan checksum unduhan harus terverifikasi pada manifest operasional rilis sebelum APK diserahkan.
