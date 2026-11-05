# Alat profesional di chat sesi

Alat dibuka dari chat profesional dengan pasien dan sesi yang sedang aktif.
Setiap permintaan diperiksa kembali oleh server terhadap akun, pasangan
pasien/profesional, sesi, dan izin berbagi data yang relevan.

| Menu | Perilaku |
|---|---|
| Goals / Habits | Membaca goals aktif dan progres mingguan pasien, membuat goal dengan target 1–7 kali per minggu, serta membagikan goals terpilih ke chat. |
| Assessment | Mengirim permintaan Skrining PHQ-9 / GAD-7, DASS-21, atau WHO-5. Permintaan tidak mengisi asesmen atas nama pasien dan tidak membagikan jawaban pasien secara otomatis. |
| Health Record | Membaca dan memperbarui diagnosis. Pengelolaan obat hanya muncul untuk psikiater terverifikasi; profesional lain tetap dapat membaca data yang diizinkan pasien. |
| Berkas | Memilih JPEG, PNG, WebP, atau PDF hingga 10 MiB melalui penyedia platform dan mengunggahnya ke penyimpanan chat privat. Server memvalidasi isi berkas dan mengotorisasi pengunduhan. |
| Rangkuman sesi | Memilih hingga 20 goals aktif, menambahkan insight yang ditujukan kepada pasien, lalu mengirim kartu rangkuman. Goal baru disimpan terlebih dahulu sebelum ID-nya masuk ke kartu. |

Form obat mendukung tambah, ubah, dan hapus. Pembaruan mempertahankan dosis,
bentuk, jam minum WIB, kaitan makan, stok, batas pengingat stok, dan sumber obat.
Penghapusan memerlukan konfirmasi.
Izin diagnosis dan obat dimuat secara terpisah: penolakan akses diagnosis tidak
menghalangi pengelolaan obat yang sudah diizinkan pasien.

Kegagalan ditampilkan dengan pesan ramah dan aksi mencoba kembali. Selama
permintaan berlangsung, tombol mutasi dinonaktifkan. Pembuatan goal/obat,
pengiriman kartu, dan unggahan mempertahankan identitas intent yang sama saat
retry sehingga respons yang terputus tidak menyebabkan intent baru. Pesan baru
diteruskan ke chat hanya setelah server mengembalikan pesan tersimpan.

Saat akun berubah, alat dari akun sebelumnya tidak ditampilkan dan respons
asinkron lama tidak dapat memperbarui tampilan, meneruskan pesan, atau
menavigasi akun baru. Token yang diperbarui tetap dapat digunakan oleh akun
pemilik yang sama.

Saat batas akhir sesi tercapai menurut jam acuan server, alat yang masih terbuka
menampilkan “Sesi berakhir” dan menyembunyikan aksi. Respons mutasi yang datang
setelah batas ini tidak diteruskan ke chat. Server tetap memeriksa sesi pada
setiap permintaan.

Implementasi UI: `lib/src/screens/chat/professional_chat_tools.dart`.
Regresi widget: `test/professional_chat_tools_test.dart`.
