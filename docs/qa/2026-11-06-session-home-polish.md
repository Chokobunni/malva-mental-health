# Validasi Malva 0.1.5+6

## Perubahan yang diverifikasi

- Home pasien dan profesional menampilkan satu sesi video/chat terdekat, dengan dropdown untuk seluruh jadwal. Judul pasien menjadi **Sesi chat mendatang**. Kartu video profesional berisi identitas, jadwal WIB, jenis/durasi dan tombol mengikuti jendela sesi.
- Profesional memiliki navigasi **Messages**. Quick Video Call ikut scroll dalam Jadwal.
- Kartu MyCare Jadwal/Riwayat dan jadwal profesional menampilkan jenis, status, ringkasan, alasan pembatalan serta konteks kuota yang relevan. Judul kehadiran tidak muncul tanpa isi pada sesi yang belum dibuka atau terminal.
- Sesi terjadwal yang lewat durasi ditampilkan pada **Perlu diselesaikan** dengan **Selesaikan sesi**. Status terminal mengalahkan salinan scheduled dari respons scope yang basi; akses chat/Meet tetap tertutup setelah akhir.
- Feed HTTP mengambil semua scheduled sebelum membatasi riwayat terminal, sehingga sesi terdekat atau lama yang perlu diselesaikan tidak hilang pada akun dengan lebih dari 100 sesi. Pemanggil store bounded lama tetap mempertahankan limit/urutan.
- Crisis Log menampilkan flag screening sebagai riwayat. Hitungan unresolved hanya SOS, tetap benar saat limit item diperkecil. SOS dapat dikonfirmasi tanpa mengetik catatan; membuka layar tidak menyelesaikan insiden otomatis.

## Bukti pengujian

- Regresi RED diamati sebelum implementasi untuk dropdown/navigasi/scroll, kartu kehadiran, terminal dari respons scope yang berbeda, dan hitungan/feed PostgreSQL. Regresi GREEN mencakup kedua peran, pergantian akun pasien, 360px dengan teks diperbesar, serta lebih dari 100 sesi dan isolasi pasien.
- Full Flutter suite dengan coverage: **697 tes lulus** pada source akhir. Pengujian sebelumnya menemukan fixture yang memakai satu ID untuk dua jadwal berbeda; fixture kini memakai dua identitas, dengan seluruh assertion status/token tetap dipertahankan.
- Flutter analyze: tidak ada issue, exit 0.
- Go build/vet dan full suite PostgreSQL nyata: lulus dengan `go test -p 1 -count=1 -coverprofile=coverage.out ./...`. Coverage store 16,0%; seluruh paket berambang lulus.
- golangci-lint: 0 issue. Konvensi, env, migrasi, WIB Dart dan isolasi platform lulus; tidak ada pengecualian baru.
- API generator/check: 143 endpoint API + 1 statis sinkron; tidak ada perubahan route, DTO atau migrasi.
- Formatter memeriksa 295 file source Flutter tanpa perubahan. Pemeriksaan `dart format .` pada checkout dengan hasil build Android menemukan path Gradle sementara yang tidak tersedia; pemeriksaan source `lib test` dipakai agar tidak menelusuri hasil build.
- Snapshot widget sintetis dibuat untuk kedua home, Messages, MyCare Jadwal/Riwayat dan Crisis Log. Font test tidak sepenuhnya menyerupai perangkat; assertion layout tidak menemukan overflow pada viewport kecil.
- Review independen menemukan dua masalah batas feed yang kemudian direproduksi dan diperbaiki. Review ulang menyetujui perbaikan tanpa P1/P2 baru.

Log dan snapshot operasional: `D:/Project/Malva/2026-07-09/_qa_2026_11_06_home_polish/`. Backup binary sebelum deploy diverifikasi checksum yang sama dengan versi 0.1.4+5. Tidak ada perubahan skema atau mutasi data untuk fitur tampilan ini.

## Gate rilis

Analyzer, CI, revision server, waktu build APK sesudah deploy, versi 0.1.5+6, sertifikat release, ABI ARM64, konfigurasi API/Google dan checksum unduhan dicatat pada manifest operasional setelah revision final diketahui. Manifest harus diverifikasi sebelum APK diserahkan.

Pengujian fisik dua akun, panggilan Meet nyata, pembayaran sandbox interaktif baru dan pengantaran FCM fisik tidak dilakukan pada batch ini. Scope pembayaran dan notifikasi sebelumnya dipertahankan; suite regresinya dijalankan kembali.
