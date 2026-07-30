# Roadmap fitur profesional Malva

Dokumen ini menjadi backlog resmi sisi profesional. Tujuan sisi profesional
bukan sekadar menampilkan data pasien, tetapi membantu profesional menentukan
prioritas klinis dengan aman dan cepat.

## Phase 1 - wajib untuk real app

1. Dashboard prioritas pasien
   - Alasan: profesional perlu tahu pasien mana yang harus dibuka dulu.
   - Sinyal: crisis flag, screening terbaru, pasien belum direview, relasi baru.

2. Daftar pasien terhubung
   - Alasan: backend sudah punya `patient_professional_links`; UI perlu
     menampilkan pasien yang benar-benar memberi akses.
   - Data utama: nama pasien, patient id, status relasi, tanggal relasi.

3. Detail pasien
   - Alasan: hasil screening tidak cukup tanpa konteks pasien.
   - Awal: nama pasien, patient id, status relasi, ringkasan data lokal/demo.

4. Histori PHQ-9/GAD-7
   - Alasan: profesional perlu melihat tren, bukan hanya skor terakhir.
   - Endpoint: `GET /v1/screenings?patient_id=...`.

5. Crisis alert
   - Alasan: PHQ-9 item self-harm harus naik prioritas review.
   - Awal: alert dari `crisis_flag` screening.

6. Review screening
   - Alasan: screening adalah alat bantu, bukan diagnosis final; profesional
     perlu menandai dan mencatat review.
   - Awal: dialog review lokal; backend review status bisa ditambahkan nanti.

## Phase 2 - sangat penting

7. Timeline pasien
   - Alasan: profesional berpikir dari urutan kejadian.
   - Isi awal: screening + mood/diary/demo event.

8. Mood/diary review
   - Alasan: pola harian sering memberi sinyal yang tidak muncul di screening.
   - Harus menghormati privasi pasien; pasien perlu kontrol data yang dibagikan.

9. Monitoring obat
   - Alasan: kepatuhan obat dan stok rendah bisa memengaruhi risiko relapse.

10. Catatan profesional
    - Alasan: profesional butuh catatan internal dan feedback terpisah.
    - Catatan internal tidak otomatis terlihat pasien.

11. Manajemen relasi pasien-profesional
    - Alasan: akses data pasien harus eksplisit dan bisa dikelola.

## Phase 3 - lanjutan

12. Follow-up message
    - Alasan: setelah review, pasien butuh arahan yang jelas.

13. Audit log UI
    - Alasan: data kesehatan mental sensitif; akses dan perubahan perlu jejak.

14. Filter/search lanjut
    - Alasan: daftar pasien akan membesar.

15. Export ringkasan
    - Alasan: profesional perlu ringkasan untuk sesi konsultasi atau review.

## Status implementasi saat ini

- Phase 1 sudah memiliki pondasi backend:
  - link pasien-profesional;
  - histori screening;
  - refresh token/session;
  - realtime notification outbox.
- UI profesional mulai membaca data backend jika session online tersedia.
- Fitur catatan/follow-up/export masih UI-local sampai backend khususnya dibuat.

