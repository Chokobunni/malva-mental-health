# Ringkasan jadwal kartu Sub-Tugas

Permintaan: kartu Sub-Tugas menampilkan ringkasan jadwal yang sama seperti
Ya/Tidak pada tiga gambar terbaru, sebelum panel Daftar Langkah.

- Pilih Hari Tertentu: tujuh tile hari, hari terpilih efektif pada minggu/tanggal
  yang dilihat, marker selesai dari `completed_weekdays`, dan status aktual.
- Target Frekuensi: tujuh segmen, `done_this_week` dan `details.weekly_target`
  aktual; target nol tetap tanpa kuota. Angka contoh screenshot bukan data pasien.
- Daftar Langkah tetap checklist dengan ID stabil. Batas tanggal, koreksi hanya
  untuk log yang sudah ada di luar jadwal, isolasi akun dan posisi scroll tetap.
- Riwayat mingguan yang belum tersedia tetap dilabeli belum dapat dimuat.

Pendekatan: gunakan `_habitSchedule(BackendGoal)` yang sudah dipakai metode
lain. Duplikasi layout akan membuat gaya dan interpretasi data mudah berbeda;
mengubah API tidak diperlukan karena semua data sudah tersedia.

Dampak S: satu kondisi render Flutter, tes regresi dan dokumentasi. Kompatibel
dengan data/server lama, tanpa field/DTO/migrasi/dependency baru. Tinggi kartu
Sub-Tugas bertambah sesuai ringkasan yang diminta. Rilis web/APK mengikuti gate.
