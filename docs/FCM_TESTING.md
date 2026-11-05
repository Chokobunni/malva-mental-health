# Pengujian notifikasi Malva

## Kebijakan yang diuji

| Penerima | Notifikasi OS yang diizinkan |
| --- | --- |
| Pasien | Chat saat sesi aktif; pengingat goals harian dan jam obat lokal |
| Profesional | Chat saat sesi aktif |
| Admin / role lain | Tidak ada push |

Screening direview, health record, terapi, pembayaran, sesi, dan event lainnya
boleh tetap tercatat di riwayat dalam aplikasi. Event tersebut tidak memicu FCM.
`POST /v1/notifications/test` hanya membuat riwayat dalam aplikasi; endpoint itu
bukan pemicu uji push.

## Pengujian otomatis

Gunakan PostgreSQL terisolasi dengan seluruh migrasi terpasang. Set
`MALVA_TEST_DATABASE_URL` khusus database uji, bukan database aplikasi/produksi.
Pengujian baru di paket notify tidak menggunakan fallback DSN aplikasi.

```bash
cd backend
go test -p 1 ./internal/notify ./internal/store -run 'TestOutbox|TestChatPush' -count=1
cd ..
flutter test test/push_delivery_policy_test.dart test/reminder_account_lifecycle_test.dart test/goal_reminder_test.dart test/push_unregister_token_test.dart test/wib_notification_schedule_test.dart
flutter test test/account_async_isolation_test.dart test/push_registration_account_race_test.dart test/medication_pending_alarm_sync_test.dart
flutter test test/background_chat_delivery_test.dart
flutter test test/push_initial_navigation_test.dart
powershell -File scripts/test_notification_transport.ps1
```

Kasus regresi yang harus tetap lolos:

- Outbox lama untuk screening/health record dihentikan tanpa menghapus riwayat.
- Chat hanya dikirim untuk role penerima dan pasangan pasien/profesional yang
  sesuai dengan ID sesi tersimpan, dalam jendela sesi yang masih berlaku.
- Sesi batal, sesi lewat, sesi belum aktif, ID sesi kosong, perubahan role,
  pengirim di luar pasangan, dan job yang sudah diproses tidak mengirim push.
- Kegagalan terminal tidak pernah diambil untuk percobaan keenam.
- Payload FCM memakai TTL Android nol dan APNs expiration nol: perangkat yang
  tidak dapat menerima segera tidak mendapat chat basi saat kembali online.
- FCM hanya data, TTL nol, prioritas Android tinggi, dan collapse ID per sesi.
- Background/terminated hanya menampilkan chat setelah akun secure storage dan
  sesi `scope=ongoing` di server sesuai; expired/future/cancelled tetap senyap.
- Pemeriksaan jendela waktu memakai `ServerClock.now()` yang dikoreksi header
  HTTP Date, sehingga jam perangkat meleset tidak menghilangkan chat aktif.
- SDK Android tidak otomatis menampilkan payload notification lama, tetapi
  event token refresh tetap ditangani. Delegasi Play Services dinonaktifkan.
- Tap chat data-only pada cold start menunggu restore akun dan navigator siap.
  Payload akun lain/jenis lama dibuang, bukan diputar ulang setelah login lain.
- Foreground menolak seluruh jenis remote selain chat dan menolak akun/pasangan
  yang tidak sesuai. Chat yang sedang dibuka tidak menampilkan notifikasi lokal.
- Pengingat goals/obat hanya dijadwalkan untuk pasien. Daftar obat yang baru
  selesai dimuat setelah login dijadwalkan; pergantian akun membatalkannya.
- Respons goals yang selesai setelah logout tidak membuat pengingat baru.
- Penjadwalan dan pembatalan diserialkan agar operasi lama tidak membatalkan
  atau menghidupkan kembali jadwal akun berikutnya.
- Respons obat, restore secure storage, dan refresh sesi akun A tidak mengubah
  akun B atau sesi yang sudah logout. Sesi aktif sebelum restore dipertahankan.
- Rotasi access token akun yang sama tetap menerima hidrasi yang sudah berjalan.
- Registrasi/token refresh/pencabutan FCM diserialkan; token terakhir dimiliki
  akun aktif, termasuk A → B → A ketika penyimpanan B masih berjalan.
- Alarm obat yang tersisa setelah proses berhenti dibersihkan saat cold start
  tanpa sesi dan saat sinkronisasi daftar obat; pruning tidak menghapus chat/goals.

## Uji perangkat dengan akun sintetis

1. Gunakan backend staging dengan provider FCM aktif, proyek Firebase yang sama
   dengan APK, dan dua akun sintetis (pasien dan profesional).
2. Buat sesi chat sintetis dalam jendela aktif. Penerima harus tidak terhubung
   ke WebSocket: penerima online sengaja tidak mendapat push.
3. Kirim teks dari lawan bicara. Verifikasi satu notifikasi OS di background
   dan pembukaan percakapan yang benar setelah tap. Kartu share tidak push.
4. Ulangi saat foreground dengan percakapan lain terbuka, lalu saat percakapan
   pengirim sedang dibuka. Kasus terakhir harus senyap.
5. Ulangi setelah durasi sesi habis atau sesi dibatalkan: tidak ada push.
6. Ubah screening/health record sintetis: hanya riwayat dalam aplikasi berubah.
7. Putuskan jaringan perangkat lalu kirim chat. Sambungkan kembali: chat yang
   tidak terkirim segera tidak muncul sebagai push tertunda.
8. Login sebagai pasien, atur jam obat dan goals WIB, lalu verifikasi pengingat
   lokal. Logout atau ganti ke profesional: kedua pengingat harus berhenti.
9. Uji izin notifikasi ditolak dan izin alarm presisi ditolak. UI tetap berjalan;
   pengingat obat memakai fallback inexact bila alarm presisi tidak tersedia.
10. Setelah logout, hentikan proses dan buka ulang tanpa sesi tersimpan:
    pengingat obat/goals akun lama tidak boleh muncul. Uji juga pergantian cepat
    A → B → A dengan jaringan lambat: chat berikutnya hanya untuk akun aktif.
11. Kirim payload sintetis lama `screening_reviewed`, `health_record_updated`,
    `medication_added`, `session_meet_ready`, dan `session_reminder` dengan bagian
    FCM notification saat background/terminated: tidak boleh ada alert OS.
12. Pasang APK sebagai upgrade dan buka ulang. Alert OS lama dibersihkan;
    alarm goals/obat mendatang tetap ada. Verifikasi merged manifest memakai
    `MalvaFirebaseMessagingService`, receiver cleanup, dan delegasi `false`.
13. Ganti akun/logout tanpa menutup Activity: alert OS akun sebelumnya harus
    dibersihkan melalui kanal native `malva/notifications`, tanpa membatalkan
    alarm goals/obat masa depan lewat `FlutterLocalNotificationsPlugin.cancelAll`.

## Cutover backlog saat deploy

1. Hentikan seluruh instance API/worker lama agar tidak ada pengiriman paralel.
2. Catat cutoff WIB setelah seluruh worker berhenti. Jangan menampilkan DSN,
   credential atau baris notifikasi; tampilkan hanya jumlah agregat.
3. Jalankan dari lingkungan server yang sudah memiliki DSN:

   ```bash
   psql "$MALVA_DATABASE_URL" -v cutoff='<cutoff WIB dengan +07:00>' \
     -f backend/deploy/scripts/retire_notification_backlog.sql
   ```

4. Pastikan `remaining_older_transport_jobs = 0`. Riwayat `notifications` tidak
   dihapus/diubah; hanya outbox lama ditandai selesai transportnya.
5. Aktifkan backend baru, lalu distribusikan APK baru. Tanpa upgrade APK,
   payload notification yang sudah berada di antrean FCM versi lama masih
   dapat ditampilkan oleh SDK lama. APK baru menghentikan jalur otomatis itu.

Jangan mencetak token perangkat, credential, isi chat pasien, atau baris data
pasien untuk debugging. Gunakan fixture sintetis dan jumlah/status agregat.
Registrasi saat ini mempertahankan satu token aktif per pengguna/platform;
login pada Android kedua menonaktifkan token Android sebelumnya.

## Batas verifikasi

Metadata proyek dan registrasi aplikasi Firebase dapat diperiksa secara
read-only melalui CLI. Ini belum membuktikan credential backend produksi,
versi server/APK terpasang, campaign console, atau pengiriman perangkat.
Payload notification yang sudah diterima FCM tidak dapat ditarik dari server;
APK baru menahan display otomatis dan membersihkan alert OS saat upgrade/start.
Perangkat dengan APK lama tetap memerlukan upgrade. Pengujian perangkat tetap diperlukan
setelah rilis backend dan APK; jangan menyatakan end-to-end berhasil hanya dari
unit test atau metadata proyek.
