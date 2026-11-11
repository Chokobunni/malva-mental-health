# Therapy Record di chat

- UI pasien: `lib/src/screens/chat_screen.dart` → “Therapy Record” → pilih satu worksheet dari `isTherapyRecordSubmission`. DASS-21 dan WHO-5 tetap di Assessment Record.
- `POST /v1/therapy-submissions/{submission_id}/share` memakai `professional_id` yang dipilih. Server memeriksa pemilik worksheet dan paket aktif; izin kategori tidak otomatis diaktifkan oleh UI ini.
- Endpoint share sudah membuat pesan `worksheet`; jangan lanjut `POST /v1/messages` untuk record yang sama. Muat riwayat untuk menampilkan pesan tersimpan dan bedakan sukses share dari kegagalan konfirmasi chat.
- Kartu dibuka lewat `GET /v1/therapy-submissions/{submission_id}`. Profesional membaca record yang dibagikan individual kepadanya atau melalui consent kategori `therapy_records` untuk pasangan pasien/profesional yang sama; pasien hanya miliknya sendiri. Detail dan daftar memakai pilihan izin yang sama, tetap dengan relasi serta jendela akses sesi/paket aktif. Jangan mengirim jawaban privat ke push atau metadata chat.
- Pemilihan dapat dibatalkan; daftar kosong dan gangguan jaringan harus memiliki umpan balik. Kunci aksi selama request dan periksa kembali akun setelah operasi async.
- Pengujian: `test/chat_therapy_share_test.dart`, `backend/internal/server/therapy_chat_flow_test.go` dan test consent yang ada.
- Chat kedua peserta menampilkan diary lengkap, obat, goals/habits, ringkasan,
  screening dan assessment langsung di percakapan, tanpa popup/dropdown detail.
  Worksheet terapi non-assessment tetap membuka detail. DASS/WHO memakai share
  endpoint yang sama tanpa duplikasi pesan; detail berizin dibaca otomatis untuk
  kartu inline, dan penolakan ID submission tidak boleh memakai fallback jawaban.
- Portal Data Pasien Dibagikan memisahkan WHO-5/DASS-21 ke tab Screening bersama PHQ-9/GAD-7; tab Terapi memakai `isTherapyRecordSubmission` dan tetap memuat worksheet legacy non-assessment. Pemisahan tampilan tidak mengubah endpoint maupun consent `therapy_records` WHO/DASS.
- Semua ringkasan chat dan Mini Summary memakai tujuh hari kalender WIB. Snapshot
  historis 14 hari dihitung ulang dari data berizin untuk tujuh hari berakhir pada
  tanggal pesan; angka 14 hari tidak boleh hanya diganti labelnya. PHQ/GAD lama
  (flat/nested/bundle) memakai cutoff valid yang sama; CF hilang dipulihkan dari
  fakta tersimpan melalui aturan kanonis bila memungkinkan. Skor/CF invalid tetap
  belum tersedia, dan indikator keselamatan positif tetap terpisah.
- Kartu PHQ/GAD/WHO/DASS memakai pola nama, skor/maksimum, tingkat gejala dan CF
  aktual tanpa penjelasan atau jawaban per item. DASS mempertahankan tiga subskala
  /42 dan satu CF triage instrumen. Foto berbentuk persegi membulat; tanggapan
  profesional memakai foto dan peran Psikiater/Psikolog dari kredensial aktual.

## Alat klinis profesional selama sesi

- Profesional terverifikasi hanya memakai alat klinis saat `ChatAccessFor` menyatakan sesi aktif; pasangan wajib mempunyai link aktif. Menambah goal membutuhkan consent `goals`; perubahan diagnosis membutuhkan `health_record`; seluruh CRUD obat profesional hanya psikiater dengan consent `medications`. Pasien tetap mengisi habit, log obat, dan jawaban asesmennya sendiri.
- REST dan WebSocket memakai validator kartu yang sama: `assessment_request` dengan metadata `{session_id,module_id}` (`screening`, `dass21`, `who5`); `goals` dengan `{session_id,goal_ids}`; `session_summary` dengan `{session_id,goal_ids,insight}`. Maksimal 20 ID goal aktif milik pasien, insight maksimal 2000 byte; field lain termasuk `private_note` ditolak. Permintaan asesmen membuka formulir yang sudah ada, tanpa assignment subsystem atau berbagi jawaban otomatis.
- Simpan goal sebelum mengirim kartu. `POST /v1/goals` dan `POST /v1/medications` menerima `Idempotency-Key` opsional (maksimal 128 karakter ASCII tanpa spasi); REST/WS pesan menerima `client_message_id` UUID opsional. Retry dengan kunci/payload sama mengembalikan ID tersimpan, payload berbeda ditolak.
- Server menambahkan snapshot otoritatif `goals:[{id,title,target_per_week}]` pada kartu goals/ringkasan, berdasarkan ID yang divalidasi. Klien tidak boleh mengirim field snapshot ini. Retry membandingkan field permintaan dan mempertahankan snapshot pertama walau judul goal berubah kemudian.
- Lampiran profesional hanya melalui `POST /v1/chat-attachments` multipart `recipient_id`, `file`, dan `client_message_id` UUID opsional. JPEG/PNG/WebP/PDF maksimal 10 MiB divalidasi berdasarkan isi; handler membuat pesan `attachment` dan metadata `{session_id,attachment_id,filename,mime,size,content_sha256}`. Jangan lanjut mengirim pesan kedua atau menerima URL lampiran dari metadata klien.
- Composer profesional menyediakan tombol lampiran langsung bagi psikolog dan
  psikiater selama sesi berizin; tetap periksa ulang sesi/akun sebelum upload.
- `GET /v1/chat-attachments/{attachment_id}` membutuhkan token Authorization dan peserta pasangan pesan; riwayat tetap dapat dibaca setelah sesi/link berakhir. Berkas disimpan di sibling `UploadDir + '-chat-private'`, tidak di static `/uploads/`; operator wajib memberi akses tulis privat kepada akun service dan melindungi backup. Lampiran resep manual bukan penerbitan E-Rx atau tanda tangan elektronik.
- Mutasi goals/obat/diagnosis mengirim event realtime `clinical_data_changed` dengan `{patient_id,resource}` (`goals`, `medications`, `health_record`) agar klien memuat ulang store bersama. Event/kartu ini tidak menambah OS push; kebijakan push sesi-chat dan pengingat lokal pasien tetap berlaku.
- Pengujian backend: `backend/internal/server/clinical_chat_test.go` mencakup REST/WS, izin, idempotensi, validasi/riwayat lampiran privat, dan refresh realtime tanpa outbox push.

## Kompatibilitas detail assessment (2026-11-10)

- Presence chat hanya satu label/dot untuk peer terpilih. Filter event menurut ID peer, abaikan ID diri/pengguna lain. Connected socket bukan peer Online; disconnect/reconnect membersihkan status lama. Header/patient cards tanpa sumber presence menampilkan unknown, bukan hijau buatan. Semua guard composer, lampiran, sesi dan riwayat tetap berlaku.

- ID submission WHO/DASS/worksheet dibuka melalui GET berotorisasi; 403/404 tidak membuka fallback jawaban snapshot. Snapshot inline legacy tanpa ID tetap dapat ditampilkan dari pesan chat berizin.
- WHO/DASS mempertahankan hasil dari jawaban lengkap yang tersimpan beserta CF triage aktual. PHQ/GAD memakai dua kartu CF terpisah. Kesalahan membuka assessment memakai label assessment, dan respons tertunda tidak boleh tampil setelah pergantian pemilik akun.

## Koreksi record/presence (2026-11-11)

- Snapshot awal presence mengirim true/false untuk seluruh peer berelasi aktif. Penutupan salah satu socket pemilik tidak mengirim Offline bila socket lain masih aktif; status dibaca menurut membership saat dikirim. Klien menunggu handshake, memfilter boolean peer terpilih dan membuang callback channel lama. Refresh token pemilik sama mengganti transport dan menghapus presence lama.
- Preview tiga record memakai presenter detail berizin dengan objek record tepat yang dipilih; judul sama bukan ID sama. Header Lihat semua mempertahankan halaman riwayat. Pergantian akun membuang respons/popup lama. Halaman Asesmen tidak memuat footer therapy/worksheet.
- Kartu Rangkuman Sesi memakai snapshot goal dan insight penuh secara inline, tanpa aksi detail. Target hanya integer1–7 yang tersimpan; kosong/invalid tampil belum tercatat. Goal IDs historis tanpa snapshot hanya menunjukkan jumlah yang diketahui.
- ID screening PHQ/GAD juga memerlukan detail berizin; penolakan/missing ID tidak membuka fallback snapshot, sama seperti WHO/DASS.
