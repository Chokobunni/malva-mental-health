import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/malva_components.dart';

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
    this.icon,
    this.color,
    this.category,
  });

  final String title;
  final String description;
  final List<String> steps;
  final IconData? icon;
  final Color? color;
  final String? category;
}

const dass21Module = TherapyModule(
  title: 'DASS-21 (Depression Anxiety Stress Scales)',
  description:
      'Kuesioner 21 pertanyaan untuk mengukur tiga aspek: depresi, kecemasan, '
      'dan stres. Setiap aspek dinilai 7 pertanyaan dengan skala 0-3 '
      '(0 = tidak sama sekali, 3 = sangat sering) selama minggu terakhir. '
      'Hasil membantu memahami tingkat gejala dan memantau perkembangan.',
  icon: Icons.assignment_rounded,
  color: MalvaColors.seed,
  category: 'Assessment',
  steps: [
    'Cari tempat tenang dan luangkan waktu ± 10 menit.',
    'Jawab 21 pernyataan sesuai kondisi minggu terakhir (0-3).',
    'Jawab berdasarkan pengalaman nyata, bukan yang "seharusnya".',
    'Lihat hasil per kategori: Depresi, Kecemasan, Stres.',
    'Simpan hasilnya untuk dibagikan ke profesional saat konsultasi.',
    'Ulangi setiap 2-4 minggu untuk memantau tren, bukan hari per hari.',
  ],
);

const who5Module = TherapyModule(
  title: 'WHO-5 (Well-Being Index)',
  description:
      'Kuesioner singkat 5 pertanyaan untuk mengukur kesejahteraan psikologis '
      'dua minggu terakhir. Skor 0-5 per item (total 0-25); skor di bawah 13 '
      'menandakan kesejahteraan rendah dan disarankan screening lanjutan. '
      'Cepat, mudah, dan cocok untuk pemantauan rutin.',
  icon: Icons.favorite_rounded,
  color: MalvaColors.mint,
  category: 'Assessment',
  steps: [
    'Siapkan diri di kondisi tenang (± 3 menit).',
    'Ingat dua minggu terakhir, bukan hanya hari ini.',
    'Nilai 5 pernyataan (contoh: "Saya merasa cerah dan bersemangat") '
        'dari 0 (tidak pernah) sampai 5 (setiap saat).',
    'Jumlahkan skor: 0-25. Di bawah 13 = pertimbangkan konsultasi.',
    'Ulangi rutin untuk melihat arah perubahan.',
  ],
);

const abcdeModule = TherapyModule(
  title: 'Restrukturisasi Kognitif (ABCDE)',
  description:
      'Teknik inti CBT untuk mengidentifikasi dan mengubah pola pikir negatif. '
      'ABCDE = Activating event (kejadian pemicu), Belief (pikiran/interpretasi), '
      'Consequence (perasaan & perilaku), Dispute (mempertanyakan pikiran), '
      'Effective new belief (pikiran baru yang seimbang).',
  icon: Icons.psychology_alt_rounded,
  color: MalvaColors.orchid,
  category: 'CBT',
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

const thinkingTrapsModule = TherapyModule(
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
  steps: [
    'Tuliskan pikiran negatif yang muncul hari ini.',
    'Cocokkan dengan daftar jebakan umum: catastrophizing, mind reading, '
        'all-or-nothing, overgeneralization, should statements.',
    'Beri nama jebakan yang teridentifikasi ("Ini catastrophizing").',
    'Tanyakan: "Apa yang akan saya katakan ke teman yang berpikir begini?"',
    'Tulis versi pikiran yang lebih seimbang dan realistis.',
  ],
);

const behavioralActivationModule = TherapyModule(
  title: 'Behavioral Activation / Goals',
  description:
      'Teknik CBT untuk mengatasi malaise: jangan menunggu "punya semangat dulu '
      'baru bergerak", tetapi bergerak dulu (aktivitas kecil bernilai) agar '
      'semangat mengikuti. Dikombinasikan dengan penetapan goals kecil yang '
      'terukur untuk membangun momentum.',
  icon: Icons.directions_run_rounded,
  color: MalvaColors.seed,
  category: 'CBT',
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

const groundingModule = TherapyModule(
  title: 'Grounding 5-4-3-2-1 (DBT)',
  description:
      'Teknik grounding berbasis panca indera untuk menghentikan spiral '
      'kecemasan dan membawa pikiran kembali ke saat ini dengan men '
      'engajahterapkan 5 hal yang dilihat, 4 yang didengar, 3 yang diraba, '
      '2 yang diendus, dan 1 yang dirasakan.',
  icon: Icons.self_improvement_rounded,
  color: MalvaColors.mint,
  category: 'DBT',
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

const tippModule = TherapyModule(
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
  steps: [
    'Temperature — Tempelkan kompres/waduh air dingin ke wajah 15-30 detik '
        '(menstimulasi refleks dive yang menenangkan).',
    'Intense exercise — Lakukan gerakan intens 1-2 menit (jumping jack, '
        'jalan cepat) untuk "membakar" hormon stres.',
    'Paced breathing — Napas perlahan: tarik 4 detik, tahan 2, hembus 6.',
    'Paired muscle relaxation — Ketegangkan otot saat menarik napas, '
        'lepaskan saat menghembuskan.',
    'Praktikkan saat tenang agar mudah dipanggil saat krisis.',
  ],
);

const breathingModule = TherapyModule(
  title: 'Latihan Pernapasan Teratur',
  description:
      'Pernapasan lambat dan teratur mengaktifkan sistem saraf parasimpatis '
      '(respons istirahat) sehingga detak jantung menurun dan pikiran lebih '
      'jernih. Latihan paling portabel: bisa dilakukan di mana saja tanpa '
      'alat, efektif untuk stres harian dan gangguan tidur ringan.',
  icon: Icons.air_rounded,
  color: MalvaColors.mint,
  category: 'Relaksasi',
  steps: [
    'Duduk nyaman, punggung tegak, bahu rileks.',
    'Tarik napas melalui hidung 4 detik (perut mengembang).',
    'Tahan napas 2 detik.',
    'Hembuskan perlahan lewat mulut 6 detik.',
    'Ulangi 5-10 siklus, atau 5 menit sebelum tidur.',
    'Gunakan panduan animasi di Safety Protocol untuk ritme.',
  ],
);

const pmrModule = TherapyModule(
  title: 'Relaksasi Otot Progresif',
  description:
      'Progressive Muscle Relaxation (PMR): menegangkan lalu melepaskan '
      'kelompok otot secara berurutan dari kaki ke kepala. Perbedaan '
      'ketegangan-rileks melatih tubuh mengenali dan melepaskan stres '
      'terkumpul, membantu insomnia dan ketegangan fisik.',
  icon: Icons.spa_rounded,
  color: MalvaColors.seed,
  category: 'Relaksasi',
  steps: [
    'Berbaring atau duduk nyaman; tarik napas tenang.',
    'Mulai dari kaki: tegangkan otot 5 detik (jangan sampai kram).',
    'Lepaskan tiba-tiba; rasakan perbedaannya 10 detik.',
    'Naik bertahap: betis, paha, perut, tangan, bahu, wajah.',
    'Akhiri dengan 3 napas dalam dan rasakan seluruh tubuh rileks.',
    'Praktikkan 10-15 menit, idealnya sebelum tidur.',
  ],
);

const psychoeducationModule = TherapyModule(
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
  steps: [
    'Pelajari satu topik per minggu (mis. minggu 1: siklus depresi).',
    'Catat 3 poin penting dan 1 hal yang masih membingungkan.',
    'Hubungkan dengan pengalamanmu: kapan siklus itu terjadi padamu?',
    'Bawa pertanyaan ke sesi konsultasi berikutnya.',
    'Bagikan pemahaman baru ke orang terdekat sebagai sistem dukungan.',
    'Gunakan hasil screening sebagai titik awal diskusi dengan profesional.',
  ],
);

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

/// Halaman detail modul terapi: deskripsi + langkah-langkah.
class TherapyDetailScreen extends StatelessWidget {
  const TherapyDetailScreen({super.key, required this.module});

  final TherapyModule module;

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
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
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
