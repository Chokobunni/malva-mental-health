import 'package:flutter/material.dart';

import '../../theme.dart';
import '../web_theme.dart';

/// Panel merek di sisi kiri layar autentikasi web.
///
/// Hanya ditampilkan pada layar lebar (>= [WebBreakpoints.splitPanel]); di
/// jendela browser sempit panel ini disembunyikan agar formulir tetap fokus.
class WebBrandPanel extends StatelessWidget {
  const WebBrandPanel({super.key});

  /// Nilai jual Malva yang ditampilkan sebagai daftar centang.
  static const List<String> _valuePoints = <String>[
    'Asesmen mandiri terstruktur (PHQ-9, GAD-7, WHO-5, DASS-21)',
    'Terapi psikologis terpandu dalam satu tempat',
    'Jadwal sesi dengan psikiater & psikolog terverifikasi',
    'Catatan kesehatan yang Anda kendalikan sendiri',
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            MalvaColors.plum,
            MalvaColors.seed,
            MalvaColors.orchid,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.spa_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Malva',
                style: textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          Text(
            'Ruang aman untuk\nkesehatan mental Anda.',
            style: textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontSize: 36,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Malva menghubungkan Anda dengan profesional terverifikasi, '
            'menemani proses asesmen, terapi, dan pemulihan — tanpa perlu '
            'menebak langkah berikutnya.',
            style: textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          ..._valuePoints.map(
            (String point) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: MalvaColors.mint,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      point,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.94),
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Data Anda terenkripsi dan tidak dibagikan tanpa izin.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
