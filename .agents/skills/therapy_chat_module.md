# Therapy Record di chat

- UI pasien: `lib/src/screens/chat_screen.dart` → “Therapy Record” → pilih satu worksheet dari `isTherapyRecordSubmission`. DASS-21 dan WHO-5 tetap di Assessment Record.
- `POST /v1/therapy-submissions/{submission_id}/share` memakai `professional_id` yang dipilih. Server memeriksa pemilik worksheet dan paket aktif; izin kategori tidak otomatis diaktifkan oleh UI ini.
- Endpoint share sudah membuat pesan `worksheet`; jangan lanjut `POST /v1/messages` untuk record yang sama. Muat riwayat untuk menampilkan pesan tersimpan dan bedakan sukses share dari kegagalan konfirmasi chat.
- Kartu dibuka lewat `GET /v1/therapy-submissions/{submission_id}`. Profesional hanya membaca record yang dibagikan kepadanya; pasien hanya miliknya sendiri. Jangan mengirim jawaban privat ke push atau metadata chat.
- Pemilihan dapat dibatalkan; daftar kosong dan gangguan jaringan harus memiliki umpan balik. Kunci aksi selama request dan periksa kembali akun setelah operasi async.
- Pengujian: `test/chat_therapy_share_test.dart`, `backend/internal/server/therapy_chat_flow_test.go` dan test consent yang ada.
