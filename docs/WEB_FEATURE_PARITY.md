# Malva — Inventaris Fitur Android & Kesiapan Web

| Field | Nilai |
|---|---|
| Basis kode | `main` @ `2fcfde4` + T01–T02 selesai, T03 + lanjutan (login Google `renderButton`) selesai |
| Metode | Penelusuran langsung `lib/src/screens/**` (53 berkas, 58 layar), `lib/src/services/**` (13 berkas), `lib/src/widgets/**` (14 berkas), dan 123 endpoint di `lib/src/services/malva_api_client.dart` |
| Sifat | Inventaris status. **Bukan** desain baru — desain ada di `docs/WEB_ARCHITECTURE.md` |

## Cara membaca status

| Status | Arti |
|---|---|
| **Siap** | Berfungsi penuh di browser setelah T01–T03 selesai. Tidak ada pekerjaan tersisa. |
| **Perlu kerja** | Berfungsi sebagian, atau menunggu T04 (routing/URL) / T05 (deploy) / pengujian nyata di browser. |
| **Tidak tersedia** | Tidak mungkin atau tidak diaktifkan di browser fase 1; UI wajib menampilkan catatan, bukan tombol mati. |
| **Belum pasti** | Tidak dapat dipastikan dari kode saat ini; butuh pengujian atau keputusan. |

**Penting:** kolom status menjawab *"apakah fitur ini berfungsi di `app.malva.web.id`"*, bukan *"apakah fitur ini boleh dipakai di web"*. Beberapa fitur berstatus **Siap** tetapi secara produk mungkin tidak ingin diekspos ke browser (lihat §5).

## Ringkasan per modul (untuk pemilik aplikasi)

| Modul | Fitur | Siap | Perlu kerja | Tidak tersedia | Belum pasti | Kesimpulan satu baris |
|---|---|---|---|---|---|---|
| Autentikasi & Akun | 15 | 15 | 0 | 0 | 0 | Jalan penuh, termasuk login Google (`renderButton`) |
| Onboarding & Consent Awal | 3 | 3 | 0 | 0 | 0 | Jalan penuh |
| Home & Check-in Harian | 7 | 7 | 0 | 0 | 0 | Jalan penuh |
| Mood, Diary, Goals | 7 | 7 | 0 | 0 | 0 | Jalan penuh |
| Skrining & Asesmen | 8 | 8 | 0 | 0 | 0 | Jalan penuh |
| Terapi Mandiri (10 modul) | 15 | 15 | 0 | 0 | 0 | Jalan penuh, termasuk unduh worksheet |
| Obat (Medication) | 9 | 4 | 0 | 5 | 0 | Catat obat jalan; semua bentuk pengingat tidak ada di browser |
| Chat & Realtime | 4 | 4 | 0 | 0 | 0 | Jalan penuh |
| Booking & Pembayaran | 9 | 8 | 1 | 0 | 0 | Jalan; jarak GPS belum diuji |
| My Care (Paket & Sesi) | 8 | 8 | 0 | 0 | 0 | Jalan penuh |
| Safety / SOS | 8 | 6 | 2 | 0 | 0 | SOS jalan; menelepon butuh fallback, GPS belum diuji |
| Notifikasi & Push | 4 | 1 | 0 | 3 | 0 | Daftar notifikasi jalan; push belum ada |
| Profesional (Portal) | 16 | 13 | 1 | 1 | 1 | Hampir penuh; consent Calendar/Meet menunggu backend |
| Admin | 4 | 4 | 0 | 0 | 0 | Jalan (keputusan eksposur) |
| Data, Privasi, Sinkronisasi | 8 | 7 | 0 | 1 | 0 | Ekspor jalan; PWA offline belum |
| Lintas-modul (URL, rilis) | 5 | 0 | 5 | 0 | 0 | Menunggu T04 & T05 |
| **Total** | **130** | **110** | **9** | **10** | **1** | **85% fitur langsung berfungsi; sisanya jelas dan terencana** |

---

## 1. Autentikasi & Akun

| Fitur | Peran | Layar / berkas utama | Status web | Catatan |
|---|---|---|---|---|
| Pilih peran (Pasien / Profesional) | semua | `login_screen.dart` | **Siap** | Tanpa API platform |
| Daftar pasien (email, nama, password) | pasien | `patient_login_screen.dart`, `auth_widgets.dart` | **Siap** | Validasi password selaras `password_policy.go` |
| Login pasien (email + password) | pasien | `patient_login_screen.dart` | **Siap** | `POST /v1/auth/login` |
| Daftar profesional (nama, STR, SIP, spesialisasi, email, password) | profesional | `professional_login_screen.dart` | **Siap** | `POST /v1/auth/register` |
| Login profesional (STR/SIP 16 digit + password) | profesional | `professional_login_screen.dart` | **Siap** | |
| Login/daftar via Google | pasien & profesional | `platform/web/google_sign_in_web.dart`, `screens/auth_widgets.dart:399`, `services/google_auth_service.dart` | **Siap** | **Diimplementasi (T03-lanjut):** web memakai `renderButton` resmi + `authenticationEvents` → ID token → `POST /v1/auth/google` (backend & `aud` tidak berubah); mobile tetap `authenticate()`. Port `GoogleSignInPort` (`usesButtonWidget`) memisahkan kedua jalur tanpa `kIsWeb` di UI. **Syarat non-kode di T05:** daftarkan JS origin `app.malva.web.id` + isi `MALVA_GOOGLE_CLIENT_ID` saat build; E2E di browser belum diuji |
| Pelengkapan data profesional pasca-Google (STR/SIP wajib) | profesional | `professional_completion_screen.dart` | **Siap** | `POST /v1/auth/complete-professional`; back ditahan dialog |
| Pulihkan sesi setelah tutup/refresh | semua | `malva_store_provider.dart`, `SecureStore` port | **Siap** | T02: `SecureStore` sudah dipakai |
| Refresh token otomatis | semua | `malva_api_client.dart` (`_handleTokenRefresh`) | **Siap** | |
| Logout (termasuk hapus sesi lokal) | semua | `settings_screens.dart`, `malva_store_provider.dart` | **Siap** | |
| Ganti password | semua | `settings_screens.dart` → `SecurityScreen` | **Siap** | `POST /v1/auth/change-password` |
| Edit profil (nama, tanggal lahir) | semua | `settings_screens.dart` → `ProfileScreen` | **Siap** | `PUT /v1/me` |
| Tautkan / lepaskan akun Gmail | semua | `google_account_screen.dart`, `google_account_card.dart` | **Siap** | `bind-google`/`unbind-google` memakai **ID token** — didukung browser |
| Bantuan, Syarat & Kebijakan, Laporkan masalah | semua | `settings_screens.dart` | **Siap** | Membuka URL eksternal (`launchUrl`) |
| Panel admin (pengguna, dokter, verifikasi kredensial) | admin | `admin/admin_panel_screen.dart`, `admin/doctor_form_screen.dart` | **Siap** (secara teknis) | Tanpa API platform. **Keputusan produk:** apakah panel admin boleh dibuka dari browser publik |

## 2. Onboarding & Consent Awal

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Persetujuan skrining awal (setuju / lewati) | pasien | `initial_screening_consent_screen.dart` | **Siap** | Status disimpan per akun di `SecureStore` |
| Consent berbagi data 7 kategori ke profesional | pasien | `booking/consent_request_sheet.dart` | **Siap** | `POST /v1/privacy/consents` |
| Kelola consent (screening, mood/diary, obat, timeline, health record, goals) | pasien | `consent_management_screen.dart` | **Siap** | |

## 3. Home & Check-in Harian

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Beranda (kartu sesi aktif, banner check-in, grid menu, notifikasi) | pasien | `home_screen.dart` | **Siap** | |
| Banner sesi video mendatang + tombol gabung | pasien | `home_screen.dart` (`_JoinMeetingBanner`), `widgets/meet_join_button.dart` | **Siap** | `launchUrl` ke Meet — tab baru |
| Check-in harian 4 langkah (Mood → Obat → Tidur → Energi) | pasien | `widgets/daily_checkin_flow.dart`, `mood_medication_checkin_screen.dart` | **Siap** | |
| Streak check-in beruntun | pasien | `widgets/daily_checkin_flow.dart` | **Siap** | Dihitung dari data server |
| Notifikasi dalam aplikasi (daftar + tandai baca) | semua | `notifications_screen.dart` | **Siap** | `GET /v1/notifications`, `read-all` |
| Indikator status sinkronisasi (online/offline, antrean tertunda) | semua | `widgets/sync_status.dart` | **Siap** | |
| Tombol SOS mengambang di semua rute pasien | pasien | `widgets/sos_fab.dart` | **Siap** | |

## 4. Mood, Diary, Goals

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Catat mood (skor, tidur, energi, kecemasan, mudah tersinggung, catatan) | pasien | `mood_screen.dart` | **Siap** | `POST /v1/mood-checkins` |
| Riwayat mood (kalender + daftar) | pasien | `history_log_screen.dart`, `mood_screen.dart` | **Siap** | |
| Tulis diary (mood, judul, isi) | pasien | `diary_screen.dart` | **Siap** | `POST /v1/diary-entries` |
| Riwayat diary + pencarian + pengelompokan tanggal | pasien | `diary_history_screen.dart` | **Siap** | |
| Umpan balik profesional atas diary | profesional | `diary_history_screen.dart` → `POST /v1/diary-entries/{id}/feedback` | **Siap** | |
| Goals & habits (target, progres, log kebiasaan) | pasien | `goals_screen.dart` | **Siap** | `GET/POST /v1/goals`, `/v1/habit-logs` |
| Ringkasan 14 hari (mood, tidur, kepatuhan obat) + bagikan ke profesional | pasien & profesional | `services/weekly_summary_service.dart`, `widgets/mini_summary.dart` | **Siap** | Sumber utama server, fallback lokal |

## 5. Skrining & Asesmen

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Skrining PHQ-9 + GAD-7 (16 pertanyaan) + kirim | pasien | `assessment_screen.dart` | **Siap** | `POST /v1/screenings`; mendukung mode offline (antrean) |
| Hasil skrining (skor, level, flag krisis, rekomendasi modul) | pasien | `assessment_screen.dart`, `assessment_result_screen` (di `assessment_screen.dart`) | **Siap** | |
| Riwayat asesmen (screening + worksheet DASS-21/WHO-5) | pasien | `assessment_history_screen.dart` | **Siap** | |
| Daftar asesmen tersedia | pasien | `assessment_list_screen.dart` | **Siap** | |
| Katalog tes psikologi dari server (`psychological_tests_catalog`) | pasien | `tests_marketplace_screen.dart` | **Siap** | Bug `pushNamed('/assessment')` diperbaiki di T04 |
| Review skrining oleh profesional | profesional | `pro_patient_detail_screen.dart`, `POST /v1/screenings/{id}/review` | **Siap** | |
| Flag krisis otomatis (trigger Crisis Alert) | pasien & profesional | `providers/data/crisis_provider.dart` | **Siap** | |
| Penyimpanan lokal riwayat asesmen per akun | pasien | `services/assessment_database_service.dart` | **Siap** | T02: memakai `SecureStore` |

## 6. Terapi Mandiri (10 modul worksheet)

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Perpustakaan terapi (10 modul) | pasien | `widgets/therapy_library.dart` | **Siap** | |
| DASS-21 (21 item) | pasien | `therapy_library.dart` (id `dass21`) | **Siap** | |
| WHO-5 (5 item) | pasien | `therapy_library.dart` (id `who5`) | **Siap** | |
| Restrukturisasi kognitif ABCDE | pasien | `abcde_cbt_screen.dart`, `therapy_library.dart` (id `abcde`) | **Siap** | |
| Identifikasi distorsi kognitif (Thinking Traps) | pasien | `therapy_library.dart` (id `thinking_traps`) | **Siap** | |
| Behavioral Activation / Goals | pasien | `therapy_library.dart` (id `behavioral_activation`) | **Siap** | |
| Grounding 5-4-3-2-1 (DBT) | pasien | `therapy_library.dart` (id `grounding`) | **Siap** | |
| TIPP & pernapasan teratur | pasien | `therapy_library.dart` (id `tipp`) | **Siap** | |
| Latihan pernapasan teratur | pasien | `therapy_library.dart` (id `breathing`) | **Siap** | |
| Relaksasi otot progresif | pasien | `therapy_library.dart` (id `pmr`) | **Siap** | |
| Psikoedukasi terstruktur | pasien | `therapy_library.dart` (id `psychoeducation`) | **Siap** | |
| Simpan kiriman worksheet + riwayat | pasien | `POST /v1/therapy-submissions` | **Siap** | |
| Bagikan worksheet ke profesional | pasien | `POST /v1/therapy-submissions/{id}/share` | **Siap** | |
| Unduh/bagikan worksheet sebagai berkas .txt | pasien | `therapy_library.dart` → `fileExporterProvider` | **Siap** | T03: unduhan `Blob` + `<a download>` di browser; Android tetap lembar bagikan |
| Pratinjau & skor worksheet | profesional | `pro_patient_detail_screen.dart` | **Siap** | |

## 7. Obat (Medication)

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Daftar obat + sisa stok + kepatuhan hari ini | pasien | `medication_screen.dart` | **Siap** | |
| Tambah / ubah / hapus obat (dosis, jadwal, stok) | pasien | `medication_screen.dart`, `providers/malva_store_provider.dart` | **Siap** | `GET/POST/PUT/DELETE /v1/medications` |
| Catat minum obat (Taken / Skipped / Missed / Partial) | pasien | `medication_screen.dart` → `POST /v1/medication-logs` | **Siap** | |
| Riwayat konsumsi obat | pasien | `medication_screen.dart` | **Siap** | |
| **Pengingat obat terjadwal (notifikasi OS)** | pasien | `services/medication_reminder_service.dart` | **Tidak tersedia** | Tidak ada penjadwal lokal di browser. UI: banner "kelola dari aplikasi" |
| **Pengingat saat aplikasi/tab terbuka** | pasien | `lib/src/platform/web/reminder_scheduler_web.dart` | **Tidak tersedia** | Tidak ada penjadwal in-app di fase 1 (`inAppDueReminders` = `Stream.empty()`); `MedicationReminderService(enabled: false)` no-op di web sehingga `zonedSchedule` tidak pernah dipanggil. Banner jujur di `medication_screen.dart:372` |
| Notifikasi uji pengingat | pasien | `medication_screen.dart` → `showTestNotification()` | **Tidak tersedia** | Bergantung pengingat OS |
| Izin notifikasi (Android 13+) | pasien | `medication_screen.dart` | **Tidak tersedia** | Tidak ada izin notifikasi OS di browser fase 1 |
| Kirim pengingat obat lewat push web | pasien | — | **Tidak tersedia** | Fase 2 (butuh service worker + VAPID) |

## 8. Chat & Realtime

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Daftar percakapan | pasien & profesional | `messages_list_screen.dart` | **Siap** | `GET /v1/messages` |
| Chat realtime (WebSocket) | pasien & profesional | `chat_screen.dart`, `services/chat_service.dart` | **Siap** | WS + `?access_token=` hanya di `/v1/realtime/ws` (`server.go:1799`) |
| Izin chat (teks hanya saat sesi / paket aktif) | pasien | `chat_screen.dart`, `GET /v1/chat-permission` | **Siap** | |
| Event realtime non-chat (profil profesional diperbarui, dsb.) | semua | `services/realtime_service.dart` | **Siap** | |

## 9. Booking & Pembayaran

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Cari profesional (filter, urut, trust signals) | pasien | `booking/doctor_discovery_screen.dart` | **Siap** | `GET /v1/doctors/search` |
| Jarak faskes (km) berbasis GPS | pasien | `providers/location_provider.dart` | **Perlu kerja** | `geolocator_web` butuh HTTPS + izin; bila ditolak, jarak tidak tampil. Belum diuji di browser |
| Profil profesional (harga, faskes, jadwal, ulasan, BPJS, intro video) | pasien | `booking/doctor_profile_screen.dart` | **Siap** | Video hanya bila profesional mengisi URL (diputar lewat URL eksternal) |
| Pilih slot & buat booking quick consult | pasien | `booking/booking_detail_screen.dart` | **Siap** | `GET /v1/doctors/{id}/slots`, `POST /v1/bookings` |
| Beli paket Continuous 4 sesi / 6 minggu | pasien | `booking/package_booking_screen.dart` | **Siap** | `POST /v1/care-packages` |
| Pembayaran mode simulasi (dev) | pasien | `booking/payment_screen.dart` | **Siap** | `POST /v1/payments/mark-paid` |
| Pembayaran gateway Midtrans (buka `redirect_url`) | pasien | `booking/payment_screen.dart` | **Siap** | `launchUrl` → tab baru; status dipantau via `GET /v1/payments/{ref}` |
| Halaman sukses pembayaran + langkah lanjut | pasien | `booking/payment_success_screen.dart` | **Siap** | |
| Batalkan booking | pasien | `booking_detail_screen.dart` → `POST /v1/bookings/{id}/cancel` | **Siap** | |

## 10. My Care (Paket, Sesi, Jadwal)

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Daftar paket aktif + sisa sesi + aturan hangus | pasien | `care_package_screen.dart`, `my_care_screen.dart` | **Siap** | |
| Daftar sesi (akan datang / riwayat) + filter status | pasien | `my_care_screen.dart` | **Siap** | |
| Jadwalkan sesi dari sisa paket | pasien | `care_package_screen.dart` | **Siap** | |
| Reschedule sesi (≥24 jam) | pasien | `care_package_screen.dart` → `POST /v1/care-sessions/{id}/reschedule` | **Siap** | |
| Batalkan sesi | pasien | `care_package_screen.dart` → `POST /v1/care-sessions/{id}/cancel` | **Siap** | |
| Ajukan refund sesi | pasien | `POST /v1/care-sessions/{id}/refund`, `/v1/care-refunds` | **Siap** | |
| Daftar profesional tertaut (sharing) | pasien | `my_care_screen.dart` | **Siap** | |
| Gabung sesi video (Google Meet) | pasien & profesional | `widgets/meet_join_button.dart` | **Siap** | Buka tautan Meet di tab baru |

## 11. Safety / SOS

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Dashboard darurat (hotline 119 ext 8, kontak, grounding) | pasien | `safety/emergency_dashboard_screen.dart` | **Siap** | |
| **Menelepon hotline / kontak via `tel:`** | pasien | `providers/data/crisis_provider.dart`, `safety/*` | **Perlu kerja** | Browser desktop tidak punya penangan `tel:`. T03: lembar fallback (nomor + salin + WhatsApp) |
| Kontak darurat CRUD (nama, nomor, relasi) | pasien | `safety/emergency_contacts_screen.dart` | **Siap** | `GET/POST/PUT/DELETE /v1/emergency-contacts` |
| Silent SOS (blast WhatsApp ke kontak via server/Fonnte) | pasien | `safety/sos_confirmation_screen.dart` → `POST /v1/crisis-alerts` | **Siap** | Pengiriman di sisi server; klien hanya memicu |
| Status pengiriman SOS per kontak | pasien | `GET /v1/sos-blast-status` | **Siap** | |
| Lampiran lokasi GPS pada SOS | pasien | `safety/emergency_dashboard_screen.dart:330` | **Perlu kerja** | Butuh izin lokasi browser; bila ditolak alur tetap lanjut tanpa koordinat. Belum diuji |
| Guided grounding (napas 4-7-8 + 5-4-3-2-1) | pasien | `safety/guided_grounding_screen.dart` | **Siap** | |
| Log insiden krisis untuk profesional (read-only + tandai ditangani) | profesional | `portal/crisis_incident_log_screen.dart` | **Siap** | `GET /v1/crisis-incident-log`, `POST /v1/crisis-incidents/{id}/resolve` |

## 12. Notifikasi & Push

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Daftar notifikasi + tandai baca / baca semua | semua | `notifications_screen.dart` | **Siap** | |
| **Push notification (FCM) latar depan & latar belakang** | semua | `services/push_notification_service.dart` | **Tidak tersedia** (fase 1) | `web/firebase-messaging-sw.js` belum ada + butuh VAPID. `canRegisterPush: false` |
| Daftar follow-up dari tim care | pasien | `GET /v1/follow-ups` | **Tidak tersedia** | Bergantung push untuk pemberitahuan; daftar in-app tetap bisa dibuka |
| Tap notifikasi membuka layar tertentu | semua | `push_notification_service.dart` → `_routeForType` | **Tidak tersedia** | Bergantung push |

## 13. Profesional (Portal)

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Dashboard (ringkasan pasien, krisis, sesi video mendatang) | profesional | `professional_dashboard_screen.dart` (tab Dashboard) | **Siap** | |
| Jadwal: sesi hari ini/mendatang, hadir/tidak hadir, batal, reschedule, ringkasan | profesional | `pro_schedule_screen.dart` (tab Jadwal) | **Siap** | |
| Ketersediaan mingguan (aktif/nonaktif per baris) + time-off | profesional | `pro_schedule_screen.dart` | **Siap** | `GET/POST /v1/professional/schedules`, `/time-off` |
| Harga layanan (quick chat, quick video, paket 4 sesi) | profesional | `pro_pricing_screen.dart` | **Siap** | `PUT /v1/professional/pricing` |
| Daftar pasien tertaut + pencarian pasien | profesional | `professional_dashboard_screen.dart` (tab Pasien) | **Siap** | |
| Detail pasien (paket & sesi, skrining, worksheet, goals, mood/diary read-only, health record, catatan sesi) | profesional | `pro_patient_detail_screen.dart` | **Siap** | |
| Catatan sesi profesional | profesional | `POST /v1/professional-notes` | **Siap** | |
| Buat tautan Google Meet untuk sesi | profesional | `professional_dashboard_screen.dart` → `POST /v1/meet/quick` | **Belum pasti** | Klien hanya POST ber-Bearer (tidak butuh consent Calendar dari browser). Bergantung dua hal di luar kode klien: (a) kredensial Google di server **produksi**, (b) profesional sudah menghubungkan Calendar. Bila belum, server membalas `meet_belum_aktif` dan UI menawarkan "Hubungkan" — yang **kemungkinan tidak bisa diselesaikan dari web** (lihat baris berikut) |
| Unggah foto profil | profesional | `professional_profile_editor_screen.dart` | **Siap** | T02: unggah berbasis byte + `Image.memory` |
| Unggah video perkenalan (≤20 MB) | profesional | `professional_profile_editor_screen.dart` | **Perlu kerja** | Tetap tersedia di web (picker web mendukung video, unggah berbasis byte — tidak dimatikan lewat capability). Risikonya memori tab pada 20 MB; **belum diuji** di browser |
| Editor profil (bio, sub-spesialisasi, pendidikan, pengalaman, faskes, alamat, avatar AI) | profesional | `professional_profile_editor_screen.dart` | **Siap** | |
| Verifikasi STR/SIP (unggah nomor, status menunggu) | profesional | `booking/credential_screens.dart` | **Siap** | Hanya nomor teks — tidak ada unggah berkas |
| Earnings + pencairan (payout) | profesional | `portal/earnings_screen.dart` | **Siap** | `GET /v1/earnings`, `POST /v1/earnings/payout` |
| E-Prescription (buat, detail, verifikasi) — psikiater | profesional | `portal/e_prescription_screen.dart` | **Siap** | `POST /v1/e-prescriptions`, `/verify`. **Keputusan produk:** eksposur di web |
| **Aktivasi Google Meet / Calendar (consent OAuth)** | profesional | `widgets/google_account_card.dart` → `signInWithCalendarScope` | **Tidak tersedia** (fase 1) | **Tiga penghalang, bukan satu:** (1) alur code-flow web butuh `RedirectURL` di backend (`handlers_auth.go:241-249`); (2) `google_sign_in` web tidak mendukung `authenticate()` sama sekali — butuh `renderButton`/GIS; (3) `authorizeScopes` (scope tambahan) juga tidak tersedia di jalur web. `canBindGoogleCalendar: false`. Konsekuensi produk: profesional **harus** menghubungkan Calendar dari Android lebih dulu |
| Audit & ekspor ringkasan pasien | profesional | `professional_dashboard_screen.dart` (`_AuditAndExportSection` → `_openExportSummary`) | **Siap** | Menampilkan ringkasan teks yang bisa disalin (bukan berkas) — berperilaku sama di Android |

## 14. Admin

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Kelola pengguna (cari, nonaktifkan) | admin | `admin/admin_panel_screen.dart` | **Siap** | `GET /v1/admin/users`, `PUT /v1/admin/users/{id}` |
| Kelola dokter (tambah/ubah, jadwal, paket harga) | admin | `admin/doctor_form_screen.dart` | **Siap** | |
| Verifikasi kredensial profesional (setujui/tolak) | admin | `admin/admin_panel_screen.dart` (`_VerifyTab`) | **Siap** | `GET /v1/admin/credentials/pending` |
| Audit log | admin | `GET /v1/audit-logs` | **Siap** | |

## 15. Data, Privasi, Sinkronisasi

| Fitur | Peran | Layar / berkas | Status web | Catatan |
|---|---|---|---|---|
| Health record (diagnosis, catatan klinis, riwayat) | pasien & profesional | `record_screen.dart` | **Siap** | `GET/PUT /v1/health-record` |
| Tambah record dengan label berkas (PDF/IMAGE/DOC) | pasien | `record_screen.dart:536` (`FilePicker.platform.pickFiles`) | **Siap** | Hanya **nama berkas** untuk label tombol (`result.files.single.name`) — tidak disimpan ke `HealthRecord`, tidak diunggah, tidak membaca byte/path. Aman di web (plugin hanya mengembalikan `.name`). Bukan risiko; bukan kandidat perapian karena merutekannya lewat port justru akan membaca byte yang tak terpakai |
| Timeline aktivitas | pasien & profesional | `GET /v1/timeline` | **Siap** | |
| Ekspor mood / screening / obat / diary (CSV) | pasien | `more_screen.dart`, `services/export_service.dart` | **Siap** | T03: pembentuk CSV murni + `FileExporter` web (`Blob`). Tile tampil karena `canExportFiles: true` |
| Ekspor seluruh data (JSON) | pasien | `more_screen.dart`, `export_provider.dart` | **Siap** | Idem — unduhan `malva_full_export.json` |
| Antrean sinkronisasi offline (mood, obat, skrining) | pasien | `services/offline_sync_service.dart`, `widgets/sync_status.dart` | **Siap** | T02: memakai `SecureStore` |
| Aplikasi tetap bisa dibuka saat offline (PWA) | semua | — | **Tidak tersedia** | Belum ada service worker fase 1 |
| Jam acuan server (koreksi jam perangkat) | semua | `services/server_clock.dart` | **Siap** | T02: memakai `SecureStore` |

## 16. Lintas-modul (bukan fitur pengguna, tapi penentu kesiapan)

| Item | Status web | Catatan |
|---|---|---|
| URL berubah per layar + tombol back browser | **Perlu kerja** | T04. Sebelum T04, URL tetap `/` dan back tidak berfungsi |
| Deep link ke layar tertentu | **Perlu kerja** | T04: hanya 8 rute bernama |
| Rilis di `app.malva.web.id` | **Perlu kerja** | T05: Caddy + workflow + `MALVA_ALLOWED_ORIGINS` |
| CORS produksi untuk origin app | **Perlu kerja** | Wajib sebelum rilis, kalau tidak seluruh API diblokir browser |
| Login Google di produksi | **Perlu kerja** | Kode siap (`renderButton`). Sisa non-kode: daftarkan JS origin `app.malva.web.id`, isi `MALVA_GOOGLE_CLIENT_ID` saat build, lalu uji E2E dengan akun Google sungguhan |

Catatan kesiapan isolasi (bukan fitur, tapi menentukan risiko regresi): setelah T03, **`dart:io` di kode bersama = 0**; tersisa 9 pengecualian `--strict` yang semuanya berupa impor plugin di luar lapisan platform (`geolocator`, `file_picker`, `share_plus`, `google_sign_in`, `flutter_local_notifications`, `firebase_messaging`). Semuanya berjalan di web, tetapi belum terisolasi penuh — kandidat perapian di T05 atau setelahnya.

### 16.1 Cacat web yang diketahui (harus diputuskan sebelum rilis)

| # | Cacat | Bukti | Status |
|---|---|---|---|
| D1 | Login Google mati di web — `authenticate()` melempar `UnimplementedError` | `google_sign_in_web-1.1.3/lib/google_sign_in_web.dart:160-170` | **SELESAI (T03-lanjut).** Diganti jalur `renderButton` + `authenticationEvents` di `lib/src/platform/web/google_sign_in_web.dart`; UI memilih lewat `GoogleSignInPort.usesButtonWidget`. Test: `test/google_sign_in_web_login_test.dart` |
| D2 | Build DEBUG web kena `assert(params.serverClientId == null)` | `google_sign_in_web.dart:122-127` | **SELESAI.** `createGoogleClientConfig()` web tidak lagi mengirim `serverClientId` (hanya `clientId`); build web debug hijau |

Catatan yang tetap berlaku: **"Hubungkan Google Calendar dari web" tidak didukung** — `google_sign_in` web tidak menyediakan `authorizeScopes`. Ini fitur Calendar (bukan login), tetap perlu keputusan produk (§18 butir 3).

---

## 17. Ringkasan angka

| Status | Jumlah fitur |
|---|---|
| **Siap** | 110 |
| **Perlu kerja** | 9 |
| **Tidak tersedia** | 10 |
| **Belum pasti** | 1 |
| **Total** | **130 fitur di 16 modul** |

**Perlu kerja (9):** jarak faskes berbasis GPS · menelepon via `tel:` (fallback sheet) · lokasi GPS pada SOS · unggah video perkenalan · URL & tombol back browser (T04) · deep link (T04) · rilis `app.malva.web.id` (T05) · CORS produksi · login Google di produksi (JS origin + uji E2E).

**Tidak tersedia (10):** pengingat obat terjadwal OS · pengingat obat in-app saat tab terbuka · notifikasi uji pengingat · izin notifikasi OS · pengingat obat lewat push web · push notification FCM · daftar follow-up dari tim care · tap notifikasi membuka layar · consent Google Calendar/Meet · aplikasi bisa dibuka saat offline (PWA).

**Belum pasti (1):** pembuatan tautan Google Meet dari dashboard profesional (bergantung kredensial Google di server).

---

## 18. Fitur yang menunggu keputusan produk

| # | Keputusan | Pilihan yang tersedia | Dampak bila salah pilih |
|---|---|---|---|
| 1 | **Pengingat obat di web** | (a) tetap mobile-only + banner (kondisi sekarang, sudah jujur); (b) tambah pengingat in-app saat tab terbuka; (c) push web fase 2 | (b) tanpa (c) berisiko: pengguna mengira pengingat berbunyi padahal hanya saat tab dibuka → risiko klinis |
| 2 | **Penyimpanan token web** | (a) `flutter_secure_storage` = localStorage (sekarang); (b) cookie httpOnly + CSRF (butuh kerja backend: `internal/security/csrf.go` belum dipanggil) | (a) token dapat dicuri via XSS; (b) menambah 1–2 tugas backend |
| 3 | **Alur consent Google Calendar/Meet** | (a) matikan di web fase 1 (kondisi sekarang); (b) tambahkan `RedirectURL` + code-flow di backend **dan** ganti mekanisme di klien web (GIS auth-code, karena `google_sign_in` web tidak mendukung scope tambahan) | (b) membuka pembuatan Meet dari browser, tapi butuh 2 perubahan (backend + klien), bukan 1. Sementara ini profesional harus menghubungkan Calendar dari Android |
| 4 | **Ekspor data di web** | (a) biarkan aktif (sudah jalan lewat unduhan `Blob`); (b) sembunyikan dan arahkan ke aplikasi | Sudah aktif di kode. Bila tidak ingin diekspos, cukup set `canExportFiles: false` di `lib/src/platform/web/web_capabilities.dart` — satu baris |
| 5 | **Unggah video perkenalan di web** | (a) matikan; (b) aktifkan dengan batas 20 MB | 20 MB di memori tab berisiko pada perangkat rendah |
| 6 | **Eksposur panel admin & e-prescription di web** | (a) boleh dari browser; (b) batasi ke jaringan internal/VPN | Data sangat sensitif; web memperluas permukaan serangan |
| 7 | **Lokasi GPS pada SOS** | (a) wajib; (b) opsional dengan fallback manual | (a) memblokir SOS saat izin ditolak = berbahaya; (b) aman |
| 8 | **Push web (service worker + VAPID)** | (a) fase 2; (b) tidak pernah | Tanpa push, nilai web turun untuk profesional (notifikasi sesi baru) |
| 9 | **Gerbang rilis: login Google sudah berfungsi di kode, belum diuji E2E** | (a) rilis hanya setelah E2E Google lulus (butuh akun uji + JS origin terdaftar); (b) rilis tanpa menunggu E2E, dengan pemantauan error login | Risiko sudah turun drastis: `renderButton` sudah diimplementasi (D1 §16.1 selesai) dan 445 test lulus. Sisa risiko = konfigurasi origin di Google Console, bukan kode |

---

## 19. Hal yang perlu diverifikasi (bukan asumsi)

| # | Pertanyaan | Cara memastikan |
|---|---|---|
| 1 | Apakah ekspor Blob benar-benar mengunduh berkas di browser? | Sudah diimplementasi (`file_exporter_web.dart` memakai `Blob` + `<a download>`, `canExportFiles: true`). Yang belum: uji klik nyata di Chrome setelah T05 |
| 2 | Apakah pengingat in-app web berjalan? | **Sudah dikonfirmasi tidak ada** (T03): `inAppDueReminders` = `Stream.empty()`, `MedicationReminderService(enabled: false)` no-op di web. Tidak perlu diuji — statusnya "Tidak tersedia" |
| 3 | Apakah unggah video 20 MB berhasil di Chrome? | Uji manual di `app.malva.web.id` (butuh T05) |
| 4 | Apakah `geolocator_web` memberi posisi di produksi? | Uji di HTTPS dengan izin diberikan dan ditolak |
| 5 | Apakah pembuatan tautan Meet berfungsi dari web? | Bergantung (a) kredensial Google di server **produksi** dan (b) Calendar profesional sudah terhubung (kemungkinan hanya bisa dari Android). Uji `POST /v1/meet/quick` dengan akun profesional yang menautkan Google dari Android. Bila keduanya tersedia, statusnya bisa naik ke **Siap** |
| 6 | Apakah semua endpoint mengirim header CORS yang benar untuk `app.malva.web.id`? | `curl -H 'Origin: https://app.malva.web.id' -I https://api.malva.web.id/v1/me` setelah env diperbarui |
| 7 | ~~Apakah `FilePicker` di `record_screen` tetap memberi nama berkas di web?~~ | **Sudah dijawab:** ya. Hanya `.name` dipakai sebagai label; tidak ada byte yang dibaca. Tidak perlu diuji |
| 8 | Apakah login Google berhasil end-to-end di browser? | Kode sudah siap (`renderButton` + `authenticationEvents`, `test/google_sign_in_web_login_test.dart` lulus). Yang belum: uji nyata dengan akun Google setelah JS origin `app.malva.web.id` terdaftar. Otomasi headless tidak bisa menyelesaikan OAuth — harus manual |

---

## 20. Catatan metode & keterbatasan

- 58 layar dan 13 service dibaca langsung; status ditentukan dari kode, bukan dari ingatan.
- Status "Siap" berarti **tidak ada API khusus platform** yang tersisa di jalur fitur tersebut setelah T01–T03. Itu **bukan** jaminan sudah diuji di browser — pengujian nyata baru terjadi di T05 (lihat §19).
- Fitur yang tidak ada di Android tidak dicantumkan (mis. lampiran gambar di chat), agar dokumen ini tetap menjadi *paritas*, bukan daftar keinginan.

## 21. Koreksi tertunda untuk `docs/WEB_ARCHITECTURE.md` (dikerjakan di T05)

Dokumen arsitektur ditulis **sebelum** T03 selesai, jadi beberapa bagiannya kini tidak akurat. Sengaja tidak disunting sekarang agar tidak berbenturan dengan penyuntingan T05. Daftar periksa:

| Bagian `WEB_ARCHITECTURE.md` | Kondisi sekarang | Fakta yang benar |
|---|---|---|
| §5 matriks fitur — baris ekspor CSV/JSON & worksheet | Ditulis "fase 2 / tidak tersedia" | **Sudah berfungsi**: `FileExporter` web = `Blob` + `<a download>`; `canExportFiles: true` di `lib/src/platform/web/web_capabilities.dart` |
| §7.2 langkah Google Console + klaim "login Google berhasil setelah config" | Menyiratkan cukup `clientId` + origin | **Butuh `renderButton`** — `google_sign_in` web tidak punya `authenticate()`. Sudah diimplementasi lewat `GoogleSignInPort` (`platform/web/google_sign_in_web.dart`) |
| §2.3 contoh `createGoogleClientConfig()` (io & web identik) | Mengirim `clientId` + `serverClientId` | **Web hanya `clientId`** (`serverClientId: null`) — plugin meng-`assert` null di web; build debug akan gagal bila dikirim |
| §2.1 daftar port | Belum ada `GoogleSignInPort` | Port ke-9: `usesButtonWidget` / `signInIdToken` / `buildButton`; provider `googleSignInProvider` |
| AC T03 ("login Google berhasil di web dengan `MALVA_GOOGLE_CLIENT_ID`") | Menyiratkan cukup env | Perlu ditambah: jalur `renderButton`, `GoogleSignInPort`, dan bahwa **E2E belum diuji** |
| §9.1 batas fase 1 | Menyebut ekspor & pengingat in-app sebagai fase 2 | Ekspor **naik ke fase 1**; pengingat in-app web **tidak diimplementasi** (tetap "tidak tersedia") |
| §2.2 tabel pemetaan — baris `PushRegistrar`/`ReminderScheduler` web | Menyebut "stub fase 1" | Tetap stub, tapi tulis eksplisit: `canRegisterPush: false`, `canScheduleOsReminders: false`, `inAppDueReminders` = `Stream.empty()` |

Fakta kode yang **tidak boleh** salah ditulis saat menyunting dokumen itu:

1. Web: `renderButton` + `authenticationEvents` → `idToken`; `initialize(clientId)` saja.
2. Mobile: `authenticate()` lewat `GoogleSignInPort.signInIdToken` (impl `io/`), tidak berubah.
3. UI memilih tombol lewat `GoogleSignInPort.usesButtonWidget` — **tanpa `kIsWeb`**.
4. "Hubungkan Google Calendar/Meet dari web" **tetap tidak didukung** (`authorizeScopes` tidak ada di jalur web) — fitur Calendar, **jangan digabung** statusnya dengan login.
