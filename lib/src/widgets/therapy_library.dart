import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import 'friendly_error.dart';
import 'malva_components.dart';

// ============================================================
// TERAPI LIBRARY — konten edukasi dengan penjelasan singkat
// dan langkah-langkah (tutorial) untuk setiap modul:
//   - Assessment tambahan: DASS-21, WHO-5
//   - Terapi Kognitif Perilaku (CBT): ABCDE, Thinking Traps,
//     Behavioral Activation
//   - Terapi Kognitif (DBT): Grounding 5-4-3-2-1, TIPP & Pernapasan
//   - Terapi Relaksasi & Regulasi Somatik: Pernapasan Teratur,
//     Relaksasi Otot Progresif
//   - Terapi Psikoedukasi Terstruktur
// ============================================================

class TherapyModule {
  const TherapyModule({
    required this.title,
    required this.description,
    required this.steps,
    this.id = '',
    this.icon,
    this.color,
    this.category,
    this.worksheetFields = const [],
  });

  final String title;
  final String description;
  final List<String> steps;

  /// Identifier modul untuk submission server (mis. 'abcde').
  final String id;
  final IconData? icon;
  final Color? color;
  final String? category;

  /// Field worksheet yang bisa diisi pasien lalu disimpan/dibagikan.
  final List<TherapyWorksheetField> worksheetFields;
}

/// Satu pertanyaan/isian pada worksheet modul terapi.
class TherapyWorksheetField {
  const TherapyWorksheetField({
    required this.id,
    required this.label,
    this.hint = '',
    this.multiline = true,
  });

  final String id;
  final String label;
  final String hint;
  final bool multiline;
}

const dass21Module = TherapyModule(
  id: 'dass21',
  title: 'DASS-21 (Depression Anxiety Stress Scales)',
  description:
      'Kuesioner 21 pertanyaan untuk mengukur tiga aspek: depresi, kecemasan, '
      'dan stres. Setiap aspek dinilai 7 pertanyaan dengan skala 0-3 '
      '(0 = tidak sama sekali, 3 = sangat sering) selama minggu terakhir. '
      'Hasil membantu memahami tingkat gejala dan memantau perkembangan.',
  icon: Icons.assignment_rounded,
  color: MalvaColors.seed,
  category: 'Assessment',
  worksheetFields: dass21WorksheetFields,
  steps: [
    'Cari tempat tenang dan luangkan waktu ± 10 menit.',
    'Jawab 21 pernyataan sesuai kondisi minggu terakhir (0-3).',
    'Jawab berdasarkan pengalaman nyata, bukan yang "seharusnya".',
    'Lihat hasil per kategori: Depresi, Kecemasan, Stres.',
    'Simpan hasilnya untuk dibagikan ke profesional saat konsultasi.',
    'Ulangi setiap 2-4 minggu untuk memantau tren, bukan hari per hari.',
  ],
);

/// Field worksheet DASS-21 (21 item, skala 0-3).
const dass21WorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'q1',
    label: '1. Saya merasa sulit untuk menenangkan diri',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q2',
    label: '2. Saya menyadari mulut saya terasa kering',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q3',
    label: '3. Saya tidak dapat merasakan perasaan positif sama sekali',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q4',
    label: '4. Saya mengalami kesulitan bernapas',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q5',
    label: '5. Saya merasa sulit berinisiatif mengerjakan sesuatu',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q6',
    label: '6. Saya cenderung bereaksi berlebihan terhadap situasi',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q7',
    label: '7. Saya mengalami gemetar (mis. di tangan)',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q8',
    label: '8. Saya merasa banyak menggunakan energi untuk cemas',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q9',
    label: '9. Saya khawatir akan situasi di mana saya panik',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q10',
    label: '10. Saya merasa tidak ada hal yang dapat saya nantikan',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q11',
    label: '11. Saya merasa gelisah',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q12',
    label: '12. Saya sulit untuk rileks',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q13',
    label: '13. Saya merasa sedih dan tertekan',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q14',
    label: '14. Saya tidak sabar terhadap hal yang menghalangi pekerjaan',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q15',
    label: '15. Saya merasa hampir panik',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q16',
    label: '16. Saya tidak bisa menjadi antusias terhadap apa pun',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q17',
    label: '17. Saya merasa tidak berharga',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q18',
    label: '18. Saya merasa mudah tersinggung',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q19',
    label: '19. Saya menyadari perubahan detak jantung saat cemas',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q20',
    label: '20. Saya merasa takut tanpa alasan yang jelas',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
  TherapyWorksheetField(
    id: 'q21',
    label: '21. Saya merasa hidup tidak berarti',
    hint: '0 = tidak sama sekali … 3 = sangat sering',
  ),
];

const who5Module = TherapyModule(
  id: 'who5',
  title: 'WHO-5 (Well-Being Index)',
  description:
      'Kuesioner singkat 5 pertanyaan untuk mengukur kesejahteraan psikologis '
      'dua minggu terakhir. Skor 0-5 per item (total 0-25); skor di bawah 13 '
      'menandakan kesejahteraan rendah dan disarankan screening lanjutan. '
      'Cepat, mudah, dan cocok untuk pemantauan rutin.',
  icon: Icons.favorite_rounded,
  color: MalvaColors.mint,
  category: 'Assessment',
  worksheetFields: who5WorksheetFields,
  steps: [
    'Siapkan diri di kondisi tenang (± 3 menit).',
    'Ingat dua minggu terakhir, bukan hanya hari ini.',
    'Nilai 5 pernyataan (contoh: "Saya merasa cerah dan bersemangat") '
        'dari 0 (tidak pernah) sampai 5 (setiap saat).',
    'Jumlahkan skor: 0-25. Di bawah 13 = pertimbangkan konsultasi.',
    'Ulangi rutin untuk melihat arah perubahan.',
  ],
);

/// Field worksheet WHO-5 (5 item, skala 0-5).
const who5WorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'q1',
    label: '1. Saya merasa cerah dan bersemangat',
    hint: '0 = tidak pernah … 5 = setiap saat',
  ),
  TherapyWorksheetField(
    id: 'q2',
    label: '2. Saya merasa tenang dan rileks',
    hint: '0 = tidak pernah … 5 = setiap saat',
  ),
  TherapyWorksheetField(
    id: 'q3',
    label: '3. Saya merasa aktif dan penuh energi',
    hint: '0 = tidak pernah … 5 = setiap saat',
  ),
  TherapyWorksheetField(
    id: 'q4',
    label: '4. Saya bangun dengan perasaan segar',
    hint: '0 = tidak pernah … 5 = setiap saat',
  ),
  TherapyWorksheetField(
    id: 'q5',
    label: '5. Hidup saya dipenuhi hal-hal yang menarik',
    hint: '0 = tidak pernah … 5 = setiap saat',
  ),
];

const abcdeModule = TherapyModule(
  id: 'abcde',
  title: 'Restrukturisasi Kognitif (ABCDE)',
  description:
      'Teknik inti CBT untuk mengidentifikasi dan mengubah pola pikir negatif. '
      'ABCDE = Activating event (kejadian pemicu), Belief (pikiran/interpretasi), '
      'Consequence (perasaan & perilaku), Dispute (mempertanyakan pikiran), '
      'Effective new belief (pikiran baru yang seimbang).',
  icon: Icons.psychology_alt_rounded,
  color: MalvaColors.orchid,
  category: 'CBT',
  worksheetFields: abcdeWorksheetFields,
  steps: [
    'A — Tulis kejadian pemicu secara faktual ("Presentasi ditolak bos").',
    'B — Catat pikiran otomatis yang muncul ("Saya gagal total").',
    'C — Kenali perasaan & perilaku yang muncul (malu, menarik diri).',
    'D — Bantah: bukti apa yang mendukung/menentang pikiran itu?',
    'E — Rumuskan pikiran baru yang seimbang ("Ini satu proyek, '
        'bukan definisi kemampuan saya").',
    'Latih dengan satu kejadian per hari melalui menu ABCDE CBT.',
  ],
);

/// Field worksheet ABCDE.
const abcdeWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'activating',
    label: 'A — Activating event (kejadian pemicu)',
    hint: 'Tulis fakta kejadiannya, bukan tafsirannya…',
  ),
  TherapyWorksheetField(
    id: 'belief',
    label: 'B — Belief (pikiran otomatis)',
    hint: 'Pikiran yang muncul saat kejadian itu…',
  ),
  TherapyWorksheetField(
    id: 'consequence_physical',
    label: 'C1 — Consequence: reaksi fisik',
    hint: 'Jantung berdebar, tegang, dll…',
  ),
  TherapyWorksheetField(
    id: 'consequence_emotional',
    label: 'C2 — Consequence: emosi & perilaku',
    hint: 'Malu, cemas, menghindar, dll…',
  ),
  TherapyWorksheetField(
    id: 'dispute',
    label: 'D — Dispute (bantah pikiran)',
    hint: 'Bukti yang mendukung/menentang pikiran itu…',
  ),
  TherapyWorksheetField(
    id: 'effective',
    label: 'E — Effective new belief (pikiran baru)',
    hint: 'Versi pikiran yang lebih seimbang & realistis…',
  ),
];

const thinkingTrapsModule = TherapyModule(
  id: 'thinking_traps',
  title: 'Identifikasi Distorsi Kognitif (Thinking Traps)',
  description:
      'Distorsi kognitif adalah "jebakan pikiran" — cara berpikir otomatis '
      'yang menyimpang dari fakta, seperti kata-kata harus (should), '
      'membaca pikiran orang lain, membesar-besarkan (catastrophizing), '
      'dan pemikiran hitam-putih. Mengenali jebakan adalah langkah pertama '
      'untuk keluar darinya.',
  icon: Icons.psychology_rounded,
  color: MalvaColors.amber,
  category: 'CBT',
  worksheetFields: thinkingTrapsWorksheetFields,
  steps: [
    'Tuliskan pikiran negatif yang muncul hari ini.',
    'Cocokkan dengan daftar jebakan umum: catastrophizing, mind reading, '
        'all-or-nothing, overgeneralization, should statements.',
    'Beri nama jebakan yang teridentifikasi ("Ini catastrophizing").',
    'Tanyakan: "Apa yang akan saya katakan ke teman yang berpikir begini?"',
    'Tulis versi pikiran yang lebih seimbang dan realistis.',
  ],
);

/// Field worksheet Thinking Traps.
const thinkingTrapsWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'thought',
    label: '1. Pikiran negatif yang muncul',
    hint: 'Tulis persis seperti yang ada di kepalamu…',
  ),
  TherapyWorksheetField(
    id: 'trap_type',
    label: '2. Jenis jebakan pikiran',
    hint: 'Mis. catastrophizing / mind reading / all-or-nothing / '
        'overgeneralization / should statements',
  ),
  TherapyWorksheetField(
    id: 'evidence',
    label: '3. Bukti nyata: mendukung vs menentang',
    hint: 'Apa fakta yang mendukung dan yang menentang pikiran itu?',
  ),
  TherapyWorksheetField(
    id: 'balanced_thought',
    label: '4. Pikiran seimbang versi baru',
    hint: 'Kalimat yang lebih adil untuk dirimu sendiri…',
  ),
];

const behavioralActivationModule = TherapyModule(
  id: 'behavioral_activation',
  title: 'Behavioral Activation / Goals',
  description:
      'Teknik CBT untuk mengatasi malaise: jangan menunggu "punya semangat dulu '
      'baru bergerak", tetapi bergerak dulu (aktivitas kecil bernilai) agar '
      'semangat mengikuti. Dikombinasikan dengan penetapan goals kecil yang '
      'terukur untuk membangun momentum.',
  icon: Icons.directions_run_rounded,
  color: MalvaColors.seed,
  category: 'CBT',
  worksheetFields: behavioralActivationWorksheetFields,
  steps: [
    'Pilih SATU aktivitas kecil bernilai (mis. jalan 10 menit, '
        'menyapu satu ruangan).',
    'Jadwalkan waktu spesifik (hari & jam) di menu Goals.',
    'Lakukan tanpa menunggu mood membaik — mulai sekecil apa pun.',
    'Catat hasil dan bagaimana perasaanmu setelahnya.',
    'Naikkan tingkat kesulitan bertahap setiap beberapa hari.',
    'Rayakan streak kecil untuk memperkuat kebiasaan.',
  ],
);

/// Field worksheet Behavioral Activation.
const behavioralActivationWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'activity',
    label: '1. Aktivitas kecil yang dipilih',
    hint: 'Mulai dari yang paling ringan dan spesifik…',
  ),
  TherapyWorksheetField(
    id: 'schedule',
    label: '2. Jadwal (hari & jam)',
    hint: 'Mis. Selasa 07.00 setelah bangun tidur',
  ),
  TherapyWorksheetField(
    id: 'result',
    label: '3. Hasil & perasaan setelah dilakukan',
    hint: 'Apa yang berubah pada mood atau energimu?',
  ),
  TherapyWorksheetField(
    id: 'next_step',
    label: '4. Langkah berikutnya',
    hint: 'Naikkan sedikit lebih menantang atau ulangi dulu?',
  ),
];

const groundingModule = TherapyModule(
  id: 'grounding',
  title: 'Grounding 5-4-3-2-1 (DBT)',
  description:
      'Teknik grounding berbasis panca indera untuk menghentikan spiral '
      'kecemasan dan membawa pikiran kembali ke saat ini dengan men '
      'engajahterapkan 5 hal yang dilihat, 4 yang didengar, 3 yang diraba, '
      '2 yang diendus, dan 1 yang dirasakan.',
  icon: Icons.self_improvement_rounded,
  color: MalvaColors.mint,
  category: 'DBT',
  worksheetFields: groundingWorksheetFields,
  steps: [
    'Tarik napas dalam sekali dan perlahan keluarkan.',
    '5 — Sebutkan 5 benda yang bisa kamu LIHAT sekarang.',
    '4 — Identifikasi 4 SUARA yang bisa kamu dengar.',
    '3 — Raba 3 benda dan perhatikan teksturnya.',
    '2 — Cium 2 AROMA di sekitarmu (atau aroma favoritmu).',
    '1 — Sadari 1 hal yang bisa kamu RASA (napas, rasa minuman).',
    'Ulangi bila perlu. Tersedia panduan audio di menu Safety.',
  ],
);

/// Field worksheet Grounding 5-4-3-2-1.
const groundingWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'see',
    label: '5 — Yang saya LIHAT',
    hint: 'Sebutkan 5 benda di sekitarmu…',
  ),
  TherapyWorksheetField(
    id: 'hear',
    label: '4 — Yang saya DENGAR',
    hint: 'Suara apa saja yang terdengar sekarang?',
  ),
  TherapyWorksheetField(
    id: 'touch',
    label: '3 — Yang saya RABA',
    hint: 'Tekstur benda yang kamu sentuh…',
  ),
  TherapyWorksheetField(
    id: 'smell',
    label: '2 — Yang saya CIUM',
    hint: 'Aroma di sekitar atau aroma favoritmu…',
  ),
  TherapyWorksheetField(
    id: 'taste_feel',
    label: '1 — Yang saya RASA',
    hint: 'Napas, rasa minuman, atau sensasi tubuh…',
  ),
];

const tippModule = TherapyModule(
  id: 'tipp',
  title: 'TIPP & Pernapasan Teratur (DBT & Somatik)',
  description:
      'TIPP = Temperature (air dingin di wajah), Intense exercise (olahraga '
      'singkat), Paced breathing (napas teratur), Paired muscle relaxation '
      '(relaksasi otot berpasangan). Teknik regulasi emosi cepat yang '
      'bekerja lewat respons fisiologis tubuh untuk menurunkan intensitas '
      'emosi dalam hitungan menit.',
  icon: Icons.ac_unit_rounded,
  color: MalvaColors.orchid,
  category: 'DBT',
  worksheetFields: tippWorksheetFields,
  steps: [
    'Temperature — Tempelkan kompres/wadah air dingin ke wajah 15-30 detik '
        '(menstimulasi refleks dive yang menenangkan).',
    'Intense exercise — Lakukan gerakan intens 1-2 menit (jumping jack, '
        'jalan cepat) untuk "membakar" hormon stres.',
    'Paced breathing — Napas perlahan: tarik 4 detik, tahan 2, hembus 6.',
    'Paired muscle relaxation — Ketegangkan otot saat menarik napas, '
        'lepaskan saat menghembuskan.',
    'Praktikkan saat tenang agar mudah dipanggil saat krisis.',
  ],
);

/// Field worksheet TIPP.
const tippWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'temperature',
    label: 'Temperature — pengalaman air dingin',
    hint: 'Berapa lama dan bagaimana rasanya setelahnya?',
  ),
  TherapyWorksheetField(
    id: 'exercise',
    label: 'Intense exercise — gerakan yang dilakukan',
    hint: 'Mis. jumping jack 60 detik',
  ),
  TherapyWorksheetField(
    id: 'paced_breathing',
    label: 'Paced breathing — siklus napas',
    hint: 'Berapa siklus 4-2-6 yang kamu lakukan?',
  ),
  TherapyWorksheetField(
    id: 'muscle_relaxation',
    label: 'Paired muscle relaxation — otot yang ditegangkan',
    hint: 'Otot mana dan apa bedanya sebelum/sesudah?',
  ),
  TherapyWorksheetField(
    id: 'intensity_after',
    label: 'Intensitas emosi setelah latihan (1-10)',
    hint: 'Sebelum: … Setelah: …',
  ),
];

const breathingModule = TherapyModule(
  id: 'breathing',
  title: 'Latihan Pernapasan Teratur',
  description:
      'Pernapasan lambat dan teratur mengaktifkan sistem saraf parasimpatis '
      '(respons istirahat) sehingga detak jantung menurun dan pikiran lebih '
      'jernih. Latihan paling portabel: bisa dilakukan di mana saja tanpa '
      'alat, efektif untuk stres harian dan gangguan tidur ringan.',
  icon: Icons.air_rounded,
  color: MalvaColors.mint,
  category: 'Relaksasi',
  worksheetFields: breathingWorksheetFields,
  steps: [
    'Duduk nyaman, punggung tegak, bahu rileks.',
    'Tarik napas melalui hidung 4 detik (perut mengembang).',
    'Tahan napas 2 detik.',
    'Hembuskan perlahan lewat mulut 6 detik.',
    'Ulangi 5-10 siklus, atau 5 menit sebelum tidur.',
    'Gunakan panduan animasi di Safety Protocol untuk ritme.',
  ],
);

/// Field worksheet Pernapasan Teratur.
const breathingWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'cycles',
    label: 'Jumlah siklus 4-2-6 yang dilakukan',
    hint: 'Mis. 8 siklus',
  ),
  TherapyWorksheetField(
    id: 'before_after',
    label: 'Perasaan sebelum & sesudah',
    hint: 'Sebelum: tegang… Sesudah: lebih tenang…',
  ),
  TherapyWorksheetField(
    id: 'note',
    label: 'Catatan tambahan',
    hint: 'Kapan paling membantu? Sebelum tidur? Saat cemas?',
  ),
];

const pmrModule = TherapyModule(
  id: 'pmr',
  title: 'Relaksasi Otot Progresif',
  description:
      'Progressive Muscle Relaxation (PMR): menegangkan lalu melepaskan '
      'kelompok otot secara berurutan dari kaki ke kepala. Perbedaan '
      'ketegangan-rileks melatih tubuh mengenali dan melepaskan stres '
      'terkumpul, membantu insomnia dan ketegangan fisik.',
  icon: Icons.spa_rounded,
  color: MalvaColors.seed,
  category: 'Relaksasi',
  worksheetFields: pmrWorksheetFields,
  steps: [
    'Berbaring atau duduk nyaman; tarik napas tenang.',
    'Mulai dari kaki: tegangkan otot 5 detik (jangan sampai kram).',
    'Lepaskan tiba-tiba; rasakan perbedaannya 10 detik.',
    'Naik bertahap: betis, paha, perut, tangan, bahu, wajah.',
    'Akhiri dengan 3 napas dalam dan rasakan seluruh tubuh rileks.',
    'Praktikkan 10-15 menit, idealnya sebelum tidur.',
  ],
);

/// Field worksheet PMR.
const pmrWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'muscle_groups',
    label: 'Kelompok otot yang dilalui',
    hint: 'Mis. kaki → betis → paha → perut → tangan → bahu → wajah',
  ),
  TherapyWorksheetField(
    id: 'difference',
    label: 'Perbedaan tegang vs rileks yang dirasakan',
    hint: 'Bagian mana yang paling terasa lepas?',
  ),
  TherapyWorksheetField(
    id: 'note',
    label: 'Catatan & kondisi setelah latihan',
    hint: 'Lebih mudah tidur? Tubuh lebih ringan?',
  ),
];

const psychoeducationModule = TherapyModule(
  id: 'psychoeducation',
  title: 'Terapi Psikoedukasi Terstruktur',
  description:
      'Psikoedukasi memberi pemahaman terstruktur tentang kondisi kesehatan '
      'jiwa: apa itu depresi/kecemasan, bagaimana siklus gejala bekerja, '
      'peran obat dan terapi, serta tanda bahaya. Pemahaman yang baik '
      'terbukti meningkatkan kepatuhan pengobatan dan kemampuan '
      'mengelola diri (self-management).',
  icon: Icons.menu_book_rounded,
  color: MalvaColors.amber,
  category: 'Psikoedukasi',
  worksheetFields: psychoeducationWorksheetFields,
  steps: [
    'Pelajari satu topik per minggu (mis. minggu 1: siklus depresi).',
    'Catat 3 poin penting dan 1 hal yang masih membingungkan.',
    'Hubungkan dengan pengalamanmu: kapan siklus itu terjadi padamu?',
    'Bawa pertanyaan ke sesi konsultasi berikutnya.',
    'Bagikan pemahaman baru ke orang terdekat sebagai sistem dukungan.',
    'Gunakan hasil screening sebagai titik awal diskusi dengan profesional.',
  ],
);

/// Field worksheet Psikoedukasi.
const psychoeducationWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'topic',
    label: 'Topik pekan ini',
    hint: 'Mis. siklus depresi, peran obat, tanda bahaya',
  ),
  TherapyWorksheetField(
    id: 'key_points',
    label: '3 poin penting yang dipelajari',
    hint: '1) … 2) … 3) …',
  ),
  TherapyWorksheetField(
    id: 'question',
    label: '1 hal yang masih membingungkan',
    hint: 'Pertanyaan untuk dibawa ke sesi konsultasi…',
  ),
  TherapyWorksheetField(
    id: 'reflection',
    label: 'Refleksi: kapan ini terjadi padaku?',
    hint: 'Hubungkan dengan pengalaman pribadimu…',
  ),
];

/// Semua modul terapi (dipakai Psychological Therapy di Home).
const List<TherapyModule> allTherapyModules = [
  abcdeModule,
  thinkingTrapsModule,
  behavioralActivationModule,
  groundingModule,
  tippModule,
  breathingModule,
  pmrModule,
  psychoeducationModule,
];

/// Halaman detail modul terapi: deskripsi + langkah + worksheet.
/// Worksheet bisa diisi, disimpan ke server (folder therapy), diunduh
/// (share/export), dan dibagikan ke profesional.
class TherapyDetailScreen extends ConsumerStatefulWidget {
  const TherapyDetailScreen({super.key, required this.module});

  final TherapyModule module;

  @override
  ConsumerState<TherapyDetailScreen> createState() =>
      _TherapyDetailScreenState();
}

class _TherapyDetailScreenState extends ConsumerState<TherapyDetailScreen> {
  final _controllers = <String, TextEditingController>{};
  bool _isSaving = false;
  bool _saved = false;
  String? _error;

  TherapyModule get module => widget.module;

  @override
  void initState() {
    super.initState();
    for (final field in module.worksheetFields) {
      _controllers[field.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _answers() => {
        for (final entry in _controllers.entries)
          entry.key: entry.value.text.trim(),
      };

  bool get _hasAnyAnswer =>
      _controllers.values.any((c) => c.text.trim().isNotEmpty);

  Future<void> _submit({bool share = false}) async {
    if (!_hasAnyAnswer) {
      setState(() => _error = 'Isi minimal satu kolom worksheet dulu.');
      return;
    }
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Login dulu untuk menyimpan worksheet.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final submission = await api.createTherapySubmission(
        accessToken: token,
        moduleId: module.id.isEmpty ? module.title : module.id,
        title: module.title,
        answers: _answers(),
        summary: '',
      );
      String? sharedTo;
      if (share) {
        sharedTo = await _pickProfessional();
        if (sharedTo == null) {
          if (mounted) {
            setState(() => _isSaving = false);
            _toast('Worksheet tersimpan di folder therapy. '
                'Belum dibagikan ke profesional.');
          }
          return;
        }
        await api.shareTherapySubmission(
          accessToken: token,
          submissionId: submission.id,
          professionalId: sharedTo,
        );
      }
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saved = true;
      });
      _toast(share
          ? 'Worksheet tersimpan & dibagikan ke profesional.'
          : 'Worksheet tersimpan di folder therapy.');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  /// Pilih profesional aktif untuk berbagi worksheet. Null bila dibatalkan.
  Future<String?> _pickProfessional() async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (token == null || token.isEmpty) return null;
    List<BackendPatientProfessionalLink> links;
    try {
      links = await ref
          .read(apiClientProvider)
          .listPatientProfessionalLinks(accessToken: token);
    } on Object {
      return null;
    }
    final active = links
        .where((link) =>
            link.status == 'active' &&
            (link.professionalDisplayName.trim().isNotEmpty))
        .toList(growable: false);
    if (!mounted || active.isEmpty) return null;
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Bagikan ke profesional',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 12),
              for (final link in active)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0x228E44AD),
                        child: Icon(Icons.medical_services_rounded,
                            color: MalvaColors.seed),
                      ),
                      title: Text(link.professionalDisplayName,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      trailing: const Icon(Icons.send_rounded, size: 18),
                      onTap: () => Navigator.pop(ctx, link.professionalUserId),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Unduh worksheet sebagai teks (share via share sheet).
  Future<void> _download() async {
    if (!_hasAnyAnswer) {
      setState(() => _error = 'Isi minimal satu kolom worksheet dulu.');
      return;
    }
    final buffer = StringBuffer()
      ..writeln('MALVA — Worksheet Terapi')
      ..writeln(module.title)
      ..writeln('Kategori: ${module.category ?? 'Terapi'}')
      ..writeln('Tanggal: ${DateTime.now().toIso8601String()}')
      ..writeln('----------------------------------------');
    for (final field in module.worksheetFields) {
      final answer = _controllers[field.id]?.text.trim() ?? '';
      buffer
        ..writeln(field.label)
        ..writeln(answer.isEmpty ? '(belum diisi)' : answer)
        ..writeln();
    }
    buffer
      ..writeln('----------------------------------------')
      ..writeln('Catatan: dokumen ini alat bantu latihan, '
          'bukan pengganti diagnosis profesional.');
    final text = buffer.toString();
    final tmp = await getTemporaryDirectory();
    final file = File(
        '${tmp.path}/malva-worksheet-${module.id.isEmpty ? 'terapi' : module.id}-'
        '${DateTime.now().millisecondsSinceEpoch}.txt');
    await file.writeAsString(text);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Worksheet ${module.title} — Malva',
        text: 'Worksheet terapi saya (${module.title}).',
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor:
              message.contains('tersimpan') ? MalvaColors.mint : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = module.color ?? MalvaColors.seed;
    return Scaffold(
      appBar: AppBar(
        title: Text(module.category ?? 'Terapi'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(module.icon ?? Icons.self_improvement_rounded,
                    color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  module.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Apa itu?',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 6),
                Text(module.description,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Langkah-langkah',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 10),
                for (var i = 0; i < module.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: color.withValues(alpha: 0.14),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w900,
                                fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(module.steps[i],
                              style: Theme.of(context).textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (module.worksheetFields.isNotEmpty) ...[
            const SizedBox(height: 14),
            const SectionLabel('Worksheet'),
            SoftCard(
              color: color.withValues(alpha: 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Isi worksheet ini sesuai kondisimu. Hasilnya bisa '
                    'disimpan ke folder therapy, diunduh, atau dikirim '
                    'langsung ke profesional.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  for (final field in module.worksheetFields) ...[
                    Text(field.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _controllers[field.id],
                      minLines: field.multiline ? 2 : 1,
                      maxLines: field.multiline ? 5 : 1,
                      decoration: InputDecoration(
                        hintText: field.hint.isEmpty ? null : field.hint,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    color: MalvaColors.danger, fontWeight: FontWeight.w700)),
          ],
          if (_saved) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: MalvaColors.mint),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Worksheet tersimpan di folder therapy (menu More → '
                    'Export / daftar worksheet).',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (module.worksheetFields.isNotEmpty) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _isSaving ? null : () => _submit(),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Simpan ke Folder Therapy'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _isSaving ? null : () => _submit(share: true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Simpan & Kirim ke Profesional'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _download,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download Worksheet'),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Catatan: konten ini bersifat edukasi dan alat bantu latihan, '
            'bukan pengganti diagnosis atau terapi profesional.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Halaman daftar worksheet yang sudah disimpan (folder therapy).
class TherapySubmissionsScreen extends ConsumerStatefulWidget {
  const TherapySubmissionsScreen({super.key});

  @override
  ConsumerState<TherapySubmissionsScreen> createState() =>
      _TherapySubmissionsScreenState();
}

class _TherapySubmissionsScreenState
    extends ConsumerState<TherapySubmissionsScreen> {
  List<BackendTherapySubmission> _items = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Login dulu untuk melihat worksheet.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(apiClientProvider)
          .listTherapySubmissions(accessToken: token);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _share(BackendTherapySubmission submission) async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (token == null || token.isEmpty) return;
    List<BackendPatientProfessionalLink> links;
    try {
      links = await ref
          .read(apiClientProvider)
          .listPatientProfessionalLinks(accessToken: token);
    } on Object {
      return;
    }
    final active = links.where((l) => l.status == 'active').toList();
    if (!mounted || active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Belum ada profesional aktif yang terhubung.')),
      );
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Bagikan worksheet ke',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 12),
              for (final link in active)
                ListTile(
                  leading: const Icon(Icons.medical_services_rounded,
                      color: MalvaColors.seed),
                  title: Text(link.professionalDisplayName,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () => Navigator.pop(ctx, link.professionalUserId),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    try {
      await ref.read(apiClientProvider).shareTherapySubmission(
            accessToken: token,
            submissionId: submission.id,
            professionalId: chosen,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Worksheet dibagikan ke profesional.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _delete(BackendTherapySubmission submission) async {
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus worksheet?'),
        content: Text('"${submission.title}" akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(apiClientProvider).deleteTherapySubmission(
          accessToken: token, submissionId: submission.id);
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Folder Therapy'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: 'Belum ada worksheet',
                      subtitle:
                          'Buka menu Psychological Therapy, pilih modul, isi '
                          'worksheet, lalu simpan. Hasilnya muncul di sini.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(18),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final created = item.createdDateTime;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SoftCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(item.title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w900)),
                                      ),
                                      StatusPill(
                                        label: item.isShared
                                            ? 'Dibagikan'
                                            : 'Tersimpan',
                                        color: item.isShared
                                            ? MalvaColors.mint
                                            : MalvaColors.amber,
                                        icon: item.isShared
                                            ? Icons.send_rounded
                                            : Icons.folder_rounded,
                                      ),
                                    ],
                                  ),
                                  if (created != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${created.day}/${created.month}/${created.year} '
                                      '${created.hour.toString().padLeft(2, '0')}:'
                                      '${created.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.black54),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _share(item),
                                        icon: const Icon(Icons.send_rounded,
                                            size: 16),
                                        label: const Text('Bagikan'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => _delete(item),
                                        icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 16),
                                        label: const Text('Hapus'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Halaman katalog terapi (dipakai dari Home > Psychological Therapy).
class TherapyCatalogScreen extends StatelessWidget {
  const TherapyCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories =
        allTherapyModules.map((m) => m.category ?? 'Lainnya').toSet().toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Psychological Therapy'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Folder Therapy (worksheet tersimpan)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TherapySubmissionsScreen(),
              ),
            ),
            icon: const Icon(Icons.folder_copy_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SoftCard(
            color: MalvaColors.mint.withValues(alpha: 0.10),
            child: Row(
              children: [
                const Icon(Icons.folder_copy_rounded, color: MalvaColors.mint),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Isi worksheet pada tiap modul, lalu simpan ke folder '
                    'therapy — bisa diunduh & dikirim ke profesional.',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TherapySubmissionsScreen(),
                    ),
                  ),
                  child: const Text('Buka'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (final category in categories) ...[
            SectionLabel(category),
            for (final module
                in allTherapyModules.where((m) => m.category == category))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ActionTile(
                  icon: module.icon ?? Icons.self_improvement_rounded,
                  title: module.title,
                  subtitle: module.description,
                  color: module.color ?? MalvaColors.seed,
                  maxSubtitleLines: 2,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TherapyDetailScreen(module: module),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
