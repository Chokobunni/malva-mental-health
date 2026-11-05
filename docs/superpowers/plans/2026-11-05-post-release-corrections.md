# Koreksi setelah pengujian APK — 5 November 2026

User mengizinkan perbaikan, push dan deployment, lalu pengiriman APK dari source yang sama setelah deploy. Pertahankan semua perbaikan tahap pertama.

## Diagnosis dan pendekatan

Backend produksi masih pada `5540c9f` (build 1 November), tertinggal 19 commit dari source APK dasar. Kontrak `attended`, scope sesi berjalan, booking paket dan pembatasan push yang lebih baru belum tersedia di server. Ada bug UI tersendiri pada kartu video profesional dan penerusan auth ke detail pasien.

Radius perubahan: dashboard profesional, jadwal/detail pasien, home pasien, resume paket legacy, dan transport push/background/native cleanup. Ukuran keseluruhan L, memakai handler/store dan komponen yang tersedia; tanpa schema/dependency/DTO HTTP baru. Risiko tertinggi pada pembayaran legacy dan delivery background. Perubahan minimal plus deployment backend dipilih karena perbaikan APK saja tidak menyelaraskan kontrak server.

- [x] Profesional: reproduksi layout 360px, detail pasien berotorisasi dan kontrak Hadir; perbaiki dan uji.
- [x] Pasien: tampilkan Sesi berjalan dan Video call mendatang dengan avatar; isolasi kegagalan scope dan respons akun lama.
- [x] Pending payment: bedakan backend lama dari bug legacy binding, gunakan transaksi yang sama dan relasi paket tepat.
- [ ] Push: gate foreground/background, bersihkan notifikasi OS historis tanpa menghapus riwayat/jadwal valid, retire backlog transport saat deploy.
- [x] Review lintas agent; full Flutter/analyzer, Go+PostgreSQL/build/vet/coverage/API/convention gates.
- [ ] Commit perubahan task, push tanpa force; deploy revision yang sama dengan backup/rollback dan health check.
- [ ] Build APK release sesudah deploy; periksa signature, checksum, manifest dan kecocokan source.
- [ ] Laporkan revision, run deploy, APK dan batas verifikasi live secara akurat.

Satu proses Flutter test pada satu waktu. PostgreSQL lokal sintetis pada55439 dengan database terpisah per workstream. Root memegang deployment/push; agent tidak mengubah produksi.
