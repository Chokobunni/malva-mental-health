
# Screening, scoring dan<br/>Forward Chaining


**WHO-5 · GAD-7 · PHQ-9 · DASS-21**

Dokumen tinjauan profesional - 7 November 2026, WIB. Implementasi APK Malva 0.1.6 (build 7), berdasarkan kode APK sebelumnya cee2492 dan perubahan skrining WHO-5 pada worktree who5-forward-screening.


> <b>Keputusan utama:</b> skrining awal dimulai dari WHO-5. PHQ-9 dan GAD-7 hanya diaktifkan bila total WHO-5 rendah atau ada item 0-1. DASS-21 tetap tersedia untuk asesmen mandiri dan permintaan profesional.



## Tiga keluaran yang harus dibedakan


| Keluaran | Makna |
| --- | --- |

| Skor instrumen | Penjumlahan baku jawaban, dengan pengali khusus WHO-5/DASS-21. Menentukan kategori skor. |

| Forward Chaining | Aturan berbasis fakta menentukan tahapan tes berikutnya dan fakta hasil. |

| Certainty Factor (CF) | Bobot dukungan aturan model untuk hasil/triage. Tidak mengubah skor baku dan bukan probabilitas diagnosis. |

Dokumen ini menjelaskan implementasi komputasi dan bahan tinjauan klinis. Kesesuaian aritmetika tidak membuktikan validitas klinis bobot CF, terjemahan item, atau aturan triage lokal. Keputusan diagnosis dan tindak lanjut berada pada profesional.


## Panduan isi


02 Alur awal · 03 WHO-5 · 04 PHQ-9 · 05 GAD-7 · 06 DASS-21 · 07 Rumus CF · 08 Rule CF PHQ/GAD · 09 CF WHO/DASS · 10 Contoh lengkap · 11 Penyimpanan & verifikasi · 12 Referensi dan agenda meeting.


# Alur Forward Chaining awal


| Tahap | Fakta / aturan | Tindakan |
| --- | --- | --- |

| Persetujuan | Pasien menekan Saya setuju. | Buka WHO-5; Skip tetap tersedia sebelum tes. |

| Fakta awal | Lima item lengkap; tiap nilai integer 0-5. R = jumlah; P = 4R; L = ada item <=1. | Jawaban belum lengkap/invalid tidak boleh menghasilkan kesimpulan. |

| Rule 2 - prioritas | IF P < 50 OR L THEN status = Butuh Skrining Lanjutan. | Tampilkan pesan pengantar, lalu aktifkan PHQ-9 & GAD-7. |

| Rule 1 | IF P >= 50 AND NOT L THEN hasil = Kondisi Mental Sangat Baik. | Kesimpulan Symptoms Assessment; pasien dapat masuk Home. |

| Rule 3 | IF status = Butuh Skrining Lanjutan THEN aktifkan dua instrumen. | Setelah 9+7 jawaban lengkap, hitung skor baku dan inferensi CF. |


> <b>Prioritas konflik:</b> nilai total tinggi tidak membatalkan jawaban WHO-5 0-1. Contoh [1,5,5,5,5] = 21/25 = 84%, tetapi tetap lanjut PHQ-9/GAD-7. Ini membuat Rule 1 dan Rule 2 saling eksklusif.



## Pesan yang terlihat oleh pasien


**Cabang stabil:** "Kondisi psikologis Anda stabil dan luar biasa minggu ini!"

**Cabang lanjut:** "Kami mendeteksi kondisi emosional anda sedang kurang baik. Mohon lanjut mengisi asesmen berikut untuk analisis lebih dalam."

Pesan minggu ini mengikuti permintaan produk. Instruksi menjawab WHO-5 tetap mengenai **2 minggu terakhir**. Judul hasil stabil adalah label alur produk, bukan jaminan bebas gangguan mental.

DASS-21 tidak menjadi pemicu/tahap wajib dalam alur ini. Profesional tetap dapat meminta WHO-5, DASS-21, dan PHQ-9/GAD-7 melalui fitur yang sudah tersedia.


# WHO-5: kesejahteraan psikologis


Lima pernyataan positif mengenai **2 minggu terakhir**. Skor lebih tinggi berarti kesejahteraan yang dilaporkan lebih baik. Semua item wajib dijawab.

| Nilai | Keterangan jawaban |
| --- | --- |

| 0 | Tidak pernah |

| 1 | Jarang |

| 2 | Kurang dari setengah waktu |

| 3 | Lebih dari setengah waktu |

| 4 | Sebagian besar waktu |

| 5 | Selalu |


> <b>Rumus:</b> R = q1 + q2 + q3 + q4 + q5 (0-25).<br/>P = R × 4 (0-100%). Tidak ada pembalikan item dan tidak ada rata-rata CF dalam skor WHO-5.


| Raw | Persentase yang mungkin | Label tampilan Malva |
| --- | --- | --- |

| 0-7 | 0-28% | Sangat rendah; perlu tinjauan / skrining lanjutan |

| 8-12 | 32-48% | Rendah |

| 13-19 | 52-76% | Cukup |

| 20-25 | 80-100% | Baik |

**Aturan lanjut:** P &lt; 50% (setara raw &lt;13) **atau** satu item bernilai 0-1. Karena persentase selalu kelipatan 4, skor tepat 50% tidak dapat dihasilkan: batas terdekat adalah 48% dan 52%.

Contoh [2,2,3,3,3]: R=13, P=52%, semua item >=2, sehingga berhenti pada kesimpulan stabil. Contoh [2,2,2,3,3]: R=12, P=48%, sehingga lanjut.

Pembagian Cukup/Baik dan ambang sangat rendah <=28% adalah label/aturan interpretasi yang dipakai aplikasi. Poin utama untuk gerbang alur adalah raw <13 atau item 0-1. CF dibahas terpisah pada halaman 09.


# PHQ-9: gejala depresi


Sembilan pertanyaan mengenai frekuensi gejala depresi selama **2 minggu terakhir**. Tiap item bernilai 0-3; jumlah seluruhnya adalah skor baku 0-27.

| Nilai | Keterangan jawaban |
| --- | --- |

| 0 | Tidak sama sekali |

| 1 | Beberapa hari |

| 2 | Lebih dari separuh hari |

| 3 | Hampir setiap hari |

| Total | Kategori | CF band tanpa indikator keselamatan |
| --- | --- | --- |

| 0-4 | Minimal | 0.60 × 0.95 = 0.570 |

| 5-9 | Ringan (mild) | 0.72 × 0.95 = 0.684 |

| 10-14 | Sedang (moderate) | 0.84 × 0.95 = 0.798 |

| 15-19 | Cukup berat (moderately_severe) | 0.90 × 0.95 = 0.855 |

| 20-27 | Berat (severe) | 0.95 × 0.95 = 0.9025 |


> <b>Item 9 >0:</b> nyalakan indikator keselamatan terpisah dan arahkan perhatian profesional. Kategori skor tidak berubah. Contoh hanya item 9=1: total 1/27 tetap Minimal, crisis_flag=true, CF hasil=0.95 sesuai aturan model.



## Contoh perhitungan


[1,1,1,1,1,0,0,0,0] → total 5/27 → Ringan. CF band = 0.72 × min(0.95,0.95) = 0.684 (68.4%; tampilan bulat 68%). Dua batas total pada rule yang sama bukan dua bukti independen.

CF tidak mengalikan atau mengurangi angka 5/27. Angka 68.4% juga tidak berarti peluang pasien mengalami depresi sebesar 68.4%.

Aplikasi membedakan level instrumen, indikator keselamatan, dan overall_level bundel. overall_level dapat menjadi crisis untuk prioritas tindakan, sementara label PHQ-9 tetap mengikuti jumlah skor.


# GAD-7: gejala kecemasan


Tujuh pertanyaan mengenai frekuensi gejala kecemasan selama **2 minggu terakhir**. Semua item dijawab 0-3 menggunakan keterangan yang sama dengan PHQ-9.

| Nilai | Keterangan jawaban |
| --- | --- |

| 0 | Tidak sama sekali |

| 1 | Beberapa hari |

| 2 | Lebih dari separuh hari |

| 3 | Hampir setiap hari |


> <b>Rumus:</b> S = q1 + q2 + q3 + q4 + q5 + q6 + q7, dengan rentang 0-21. Tidak ada item dibalik dan CF tidak menjadi pengali skor.


| Total | Kategori | CF band |
| --- | --- | --- |

| 0-4 | Minimal | 0.60 × 0.95 = 0.570 |

| 5-9 | Ringan | 0.72 × 0.95 = 0.684 |

| 10-14 | Sedang | 0.84 × 0.95 = 0.798 |

| 15-21 | Berat | 0.90 × 0.95 = 0.855 |


## Contoh perhitungan


[2,2,2,2,2,0,0] → total 10/21 → Sedang. CF = 0.84 × min(0.95,0.95) = 0.798 (79.8%; pembulatan persen bulat 80%).

Dua jawaban worry/control yang masing-masing >=2 dapat memicu fakta pola ruminasi. Fakta pola tersebut memiliki CF sendiri dalam jejak aturan, tetapi tidak ditambahkan ke CF kategori kecemasan karena kesimpulannya berbeda.

GAD-7 tidak memiliki item keselamatan diri seperti PHQ-9 item 9. Hasil GAD-7 tinggi memerlukan tinjauan profesional, tetapi bukan bukti otomatis adanya keadaan darurat.


# DASS-21: tiga subskala


Dua puluh satu pernyataan mengenai **1 minggu terakhir**. Setiap jawaban 0-3. Tiap item hanya masuk satu subskala, masing-masing berisi 7 item.

| Nilai | Keterangan ringkas aplikasi |
| --- | --- |

| 0 | Tidak pernah / tidak berlaku |

| 1 | Kadang-kadang |

| 2 | Sering |

| 3 | Hampir selalu |

| Subskala | Nomor item (1-based) | Rumus |
| --- | --- | --- |

| Depresi | 3, 5, 10, 13, 16, 17, 21 | 2 × jumlah 7 item |

| Kecemasan | 2, 4, 7, 9, 15, 19, 20 | 2 × jumlah 7 item |

| Stres | 1, 6, 8, 11, 12, 14, 18 | 2 × jumlah 7 item |

| Kategori | Depresi | Kecemasan | Stres |
| --- | --- | --- | --- |

| Normal | 0-9 | 0-7 | 0-14 |

| Ringan | 10-13 | 8-9 | 15-18 |

| Sedang | 14-20 | 10-14 | 19-25 |

| Berat | 21-27 | 15-19 | 26-33 |

| Sangat berat | 28-42 | 20-42 | 34-42 |

Contoh semua jawaban=1: tiap subskala = 7 × 1 × 2 = 14. Hasil: depresi Sedang, kecemasan Sedang, stres Normal. Tidak ada satu skor total 0-42 untuk keseluruhan DASS-21; masing-masing subskala memiliki maksimum 42.

Karena pengali 2, skor baru selalu genap; angka ganjil pada tabel tetap batas rentang baku. CF triage tidak mengubah ketiga skor tersebut. DASS-21 bersifat dimensional dan tidak menetapkan diagnosis atau risiko bunuh diri secara langsung.


# CF: rumus yang benar-benar dipakai


CF merupakan lapisan sistem pakar. Angka bobot berikut berasal dari model Malva yang sudah ada; tidak berasal dari validasi probabilitas WHO-5, PHQ-9, GAD-7 atau DASS-21.

| Operasi | Rumus / perilaku |
| --- | --- |

| Fakta gejala PHQ/GAD | Jawaban 0 → 0.0; 1 → 0.3; 2 → 0.6; 3 → 0.9. Total skor memakai bobot model 0.95. |

| Item keselamatan | PHQ-9 item 9>0: bobot bukti minimum 0.95; rule keselamatan 1.0. |

| AND dalam satu rule | CF kondisi = min(CF fakta yang memenuhi kondisi). Ada kondisi gagal → rule tidak menembak. |

| Dukungan kesimpulan | CF hasil rule = bobot rule × CF kondisi. Tidak dikalikan lagi dengan field cf pada deklarasi kesimpulan lama. |

| Dua dukungan positif | CF gabungan = a + b × (1-a). Hanya untuk kesimpulan sama; jangan menumpuk ulang rule yang sama. |

| Dua dukungan negatif | CF gabungan = a + b × (1+a). |

| Dukungan berlawanan | CF gabungan = (a+b) / (1-min(|a|,|b|)); kasus +1 dan -1 diperlakukan sebagai 0 dalam implementasi. |


## Pencegahan kesalahan penalaran


Setiap ID rule PHQ/GAD menembak paling banyak sekali per inferensi. Batas bawah dan atas total skor adalah kondisi pada fakta yang sama, sehingga memakai minimum, bukan penjumlahan bukti. Rule pola gejala menulis fakta tersendiri; CF-nya tidak menambah CF band keparahan.

Untuk tampilan hasil positif digunakan CF mentah 0-1 ×100. Transformasi (CF+1)/2 tidak digunakan untuk mempercantik persentase. Nilai 0.684 harus dibaca sebagai 68.4%, bukan 84.2%.

CF WHO/DASS menggunakan bobot triage langsung dari kategori skor; jawaban WHO-5 tidak dipaksa masuk pemetaan gejala PHQ/GAD karena arah skornya berbeda.


# Rule CF PHQ-9 dan GAD-7


Versi rule PHQ/GAD: **2026.1.FC**. Band skor dan bobot CF utama tercantum pada halaman 04-05. Berikut seluruh rule pola gejala tambahan yang dapat muncul pada trace.

| Rule | Pemicu | Bobot rule | CF jika item=2 / 3 |
| --- | --- | --- | --- |

| PHQ9_MOTOR_RETARDATION | item 8 >=2 | 0.80 | 0.48 / 0.72 |

| PHQ9_SLEEP_DISRUPTION | item 3 >=2 | 0.85 | 0.51 / 0.765 |

| PHQ9_APPETITE_CHANGE | item 5 >=2 | 0.80 | 0.48 / 0.72 |

| PHQ9_CONCENTRATION_ISSUE | item 7 >=2 | 0.80 | 0.48 / 0.72 |

| PHQ9_SELF_WORTH_ISSUE | item 6 >=2 | 0.85 | 0.51 / 0.765 |

| GAD7_WORRY_RUMINATION | item 2 & 3 >=2 | 0.85 | 0.51 / 0.765 |

| GAD7_RESTLESSNESS | item 4 & 5 >=2 | 0.85 | 0.51 / 0.765 |

| GAD7_FEAR_ANSWER | item 7 >=2 | 0.80 | 0.48 / 0.72 |

Bila dua item memiliki jawaban berbeda, gunakan CF yang lebih kecil. Contoh GAD item 2=2 dan item 3=3: min(0.6,0.9) × 0.85 = 0.51.


## Keselamatan diri dan ringkasan hasil


PHQ9_CRISIS_SELF_HARM: item 9>0 → CF bukti 0.95 × rule 1.0 = 0.95. crisis_flag=true, tetapi kategori instrumen tetap sesuai total skor. CF utama hasil memakai maksimum CF band dan CF keselamatan, bukan kombinasi paralel keduanya.

Contoh seluruh PHQ=3: 27/27, Berat, CF band 0.9025, CF hasil 0.95 karena item 9 positif. Seluruh GAD=3: 21/21, Berat, CF 0.855. Trace API diringkas maksimum 5 rule; trace pendek bukan bukti hanya 5 rule dievaluasi.


# CF interpretasi WHO-5 dan DASS-21


Lapisan ini memilih tingkat triage tertinggi yang terpenuhi (Rendah &lt; Sedang &lt; Tinggi &lt; Krisis). CF rule yang berada pada tingkat terpilih saja digabungkan. Label ini adalah prioritas internal aplikasi, terpisah dari kategori instrumen.

| Kondisi | Triage model | CF |
| --- | --- | --- |

| Ketiga subskala DASS sangat berat | Krisis | 0.90 |

| Depresi ATAU kecemasan DASS sangat berat | Tinggi | 0.86 |

| Depresi DASS berat | Tinggi | 0.78 |

| Kecemasan DASS berat | Tinggi | 0.70 |

| WHO-5 <=28% | Tinggi | 0.74 |

| WHO-5 rendah + depresi DASS sedang ke atas | Tinggi | 0.72; tidak terjangkau pada API satu instrumen |

| Depresi ATAU kecemasan DASS sedang | Sedang | 0.60 |

| Stres DASS berat / sangat berat | Sedang | 0.58 |

| WHO-5 <50% ATAU ada item 0-1 | Sedang | 0.55; satu rule, tanpa hitung ganda |

| Tidak ada rule lebih tinggi | Rendah | 0.40 |

Contoh DASS depresi=22 (Berat), kecemasan=16 (Berat), stres=0: dua rule Tinggi menembak. CF = 0.78 + 0.70 × (1-0.78) = **0.934**. Angka 93.4% adalah dukungan model gabungan, bukan peluang diagnosis.


> <b>Untuk persetujuan profesional:</b> bobot tersebut adalah heuristik internal yang belum dikalibrasi klinis. Termasuk label Krisis untuk tiga subskala sangat berat dan prioritas Sedang untuk stres berat. Label tersebut tidak membuktikan kegawatdaruratan; penilaian langsung dan konteks klinis tetap diperlukan.


WHO-5 total tinggi dengan item 0-1 tetap mendapat alasan tindak lanjut. Versi interpretasi: dass21-who5-v2; gerbang awal: who5-entry-v1. CF tidak menentukan berhenti/lanjut; fakta jawaban dan skorlah yang menentukan.


# Contoh end-to-end untuk meeting


| Skenario | Perhitungan | Keluaran yang diharapkan |
| --- | --- | --- |

| A - WHO baik | [5,5,5,5,5] → raw25 →100%; semua >=2. | Rule 1; kesimpulan stabil; Home; PHQ/GAD tidak diisi dan tidak dibuatkan skor 0. |

| B - WHO rendah | [2,2,2,3,3] → raw12 →48%. | Rule 2 → status Butuh Skrining Lanjutan; CF triage WHO0.55. |

| B - PHQ lanjutan | [1,1,1,1,1,0,0,0,0] →5/27. | Ringan; CF0.684; item9=0 sehingga tidak ada flag keselamatan. |

| B - GAD lanjutan | [2,2,2,2,2,0,0] →10/21. | Sedang; CF0.798. Overall bundel Sedang. |

| C - konflik WHO | [1,5,5,5,5] →raw21 →84%; item1=1. | Rule 2 tetap menang; lanjut PHQ/GAD; tidak diberi kesimpulan stabil. |

| D - WHO sangat rendah | [1,1,1,1,1] →raw5 →20%. | Rule 2; triage WHO Tinggi CF0.74; lanjut PHQ/GAD. |

| E - keselamatan | WHO rendah, PHQ hanya item9=1; GAD semua0. | PHQ1/27 Minimal dengan flag keselamatan; CF PHQ0.95; overall crisis. |


## Contoh DASS terpisah dari gerbang


Pasien memilih DASS-21 sewaktu dibutuhkan. Semua 21 jawaban=1 → depresi14, kecemasan14, stres14. Kategori Sedang/Sedang/Normal. Satu rule OR untuk depresi/kecemasan Sedang memberi CF0.60. Bukan dua bukti terpisah yang menaikkan CF menjadi0.84.

Data contoh bersifat sintetis. Tidak ada identitas atau hasil pasien nyata dalam dokumen ini.


# Penyimpanan, tampilan dan verifikasi



## Kontrak data yang dipertahankan


WHO-5 dan DASS-21 disimpan melalui submission assessment/worksheet yang sudah ada, dengan scale_version=2, scale_min=0 dan scale_max=5 atau3. PHQ/GAD tetap memakai endpoint screening dan dihitung ulang di server. Tidak ada migrasi tabel atau perubahan DTO untuk alur baru.

Hasil WHO disimpan sebelum perpindahan tahap. Kegagalan simpan harus terlihat dan dapat dicoba ulang. Penyelesaian awal WHO sehat tidak membuat bundel PHQ/GAD palsu. Akses profesional tetap memerlukan relasi/consent dan mekanisme berbagi yang berlaku.


## Data lama


Submission tanpa scale_version mempertahankan rumus legacy: DASS skala1-3 memakai (jawaban-1) ×3 per subskala; WHO skala1-5 memakai (jawaban-1), lalu dipetakan ke raw0-25. Data lama dengan nilai0 dibaca sebagai versi0-based. Tanpa metadata historis, heuristik tidak dapat membedakan semua pola dengan pasti; hasil legacy perlu konteks tanggal/versi.


## Cakupan pemeriksaan


**Hasil verifikasi:** 728 tes Flutter lulus; analyzer tanpa masalah. Build, vet dan tes Go lulus; pemeriksaan API, WIB, environment dan migrasi lulus. Sesudah koreksi judul katalog, 19 tes terkait dan analyzer ulang lulus; APK rilis dibangun ulang. Codex Security meninjau 18/18 file sumber pada snapshot sebelum koreksi judul, tanpa temuan; perubahan judul diverifikasi terpisah.

Cakupan skor meliputi batas kategori, pemetaan item DASS, WHO raw/persen, CF, fire-once, flag keselamatan, WHO48/52, total84 dengan item rendah, input invalid/tidak lengkap, kegagalan simpan dan tampilan gabungan.

Build/analyzer dan tes otomatis memeriksa konsistensi implementasi. Uji widget dan emulator mendukung pemeriksaan tampilan. Ini tidak menggantikan uji klinis, uji perangkat fisik dua akun, atau validasi psikometrik terjemahan Indonesia.


## Tampilan profesional


Health Record & Obat → Pemantauan harian → Screening WHO-5, GAD-7, PHQ-9, DASS-21. Skor/CF/penjelasan disatukan dalam kartu putih. Bagian tren duplikat dihapus; kegagalan suatu bagian tidak boleh tampak sebagai skor normal atau hasil nol.


## Keseragaman hasil (10 November 2026)

PHQ/GAD memakai renderer detail record yang sama pada hasil langsung, riwayat pasien/profesional, detail klinis dan chat. PHQ-9 dan GAD-7 selalu memiliki kartu CF terpisah meskipun nilainya sama. CF tersimpan yang hilang atau invalid tetap belum tersedia; nilai gabungan historis tidak dianggap sebagai nilai masing-masing instrumen. Jawaban dan gejala aktual profesional tetap tersedia di bawah ringkasan.

WHO-5 dan DASS-21 menampilkan CF triage dari model interpretasi yang sudah ada, termasuk kesimpulan WHO awal. Label menjelaskan dukungan aturan model, bukan probabilitas diagnosis atau tingkat keparahan. Jawaban parsial tidak menghasilkan skor atau CF. Tidak ada perubahan rumus, bobot atau versi model.

Detail submission profesional menerima pembagian individual atau consent kategori therapy_records pada pasangan yang sama, mengikuti izin daftar. Jendela akses sesi/paket dan relasi tetap diperiksa; 403/404 bukan alasan membuka snapshot privat sebagai fallback.


# Referensi dan agenda tinjauan profesional


**1.** WHO (2024). The World Health Organization-Five Well-Being Index (WHO-5).

<link href="https://www.who.int/publications/m/item/WHO-UCN-MSD-MHE-2024.01" color="#6D3484">https://www.who.int/publications/m/item/WHO-UCN-MSD-MHE-2024.01</link>

**2.** Kroenke K, Spitzer RL, Williams JBW (2001). The PHQ-9: Validity of a Brief Depression Severity Measure. J Gen Intern Med 16:606-613.

<link href="https://pmc.ncbi.nlm.nih.gov/articles/PMC1495268/" color="#6D3484">https://pmc.ncbi.nlm.nih.gov/articles/PMC1495268/</link>

**3.** Spitzer RL, Kroenke K, Williams JBW, Lowe B (2006). A Brief Measure for Assessing Generalized Anxiety Disorder: The GAD-7. Arch Intern Med 166:1092-1097.

<link href="https://doi.org/10.1001/archinte.166.10.1092" color="#6D3484">https://doi.org/10.1001/archinte.166.10.1092</link>

**4.** Lovibond & Lovibond / UNSW. DASS official FAQ: scoring, severity labels and interpretation.

<link href="https://www2.psy.unsw.edu.au/dass/DASSFAQ.htm" color="#6D3484">https://www2.psy.unsw.edu.au/dass/DASSFAQ.htm</link>

**5.** Shortliffe EH, Buchanan BG (1975). A Model of Inexact Reasoning in Medicine. Mathematical Biosciences 23:351-379.

<link href="https://doi.org/10.1016/0025-5564(75)90047-4" color="#6D3484">https://doi.org/10.1016/0025-5564(75)90047-4</link>


## Yang perlu disepakati dalam meeting


1. Persetujuan alur WHO-5 dan prioritas item0-1 meskipun total tinggi.
2. Kesesuaian terjemahan item, label jawaban dan rentang waktu instrumen.
3. Penggunaan label hasil positif agar tetap suportif dan tidak menjadi diagnosis.
4. Validasi pakar atas bobot CF dan kategori triage lokal; jangan menyebutnya probabilitas diagnosis.
5. Prosedur respons saat indikator keselamatan positif dan saat hasil perlu penilaian lanjutan.


## Jejak sumber implementasi


Klien: ai/initial_screening.dart, ai/assessment_scoring.dart, ai/assessment_interpretation.dart, ai/knowledge_base.dart, ai/forward_chaining_engine.dart, assessment_engine.dart. Server PHQ/GAD: internal/screening dan internal/inference. Hasil DASS/WHO menggunakan helper klien; backend menyimpan jawaban submission sesuai kontrak yang sudah ada.

Rujukan instrumen mendasari isi/skor baku dan ambang interpretasi. Rujukan teori CF mendasari formula kombinasi, bukan validasi bobot numerik Malva. Dokumen ini merekam desain komputasi yang diimplementasikan, dengan keterbatasan tersebut dinyatakan terbuka.