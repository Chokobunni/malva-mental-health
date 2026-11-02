import 'package:flutter/material.dart';

import '../../theme.dart';
import '../web_routes.dart';
import '../web_theme.dart';
import '../widgets/web_page_header.dart';

/// Beranda pasien di web.
///
/// Fase 2A hanya kerangka: sapaan + empat kartu aksi besar yang mengarah ke
/// rute masing-masing. Isi tiap tujuan dibangun pada fase berikutnya.
class WebHomeScreen extends StatelessWidget {
  const WebHomeScreen({
    super.key,
    required this.displayName,
    required this.onNavigate,
  });

  final String displayName;
  final ValueChanged<String> onNavigate;

  /// Nama panggilan: kata pertama dari nama lengkap, fallback "Pasien".
  String get _greetingName {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'Pasien';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Halo, $_greetingName!',
          subtitle: 'Selamat datang kembali di Malva. Mulai dari langkah kecil '
              'hari ini — kami menemani prosesnya.',
        ),
        const SizedBox(height: WebSpacing.section),
        const WebSectionTitle(text: 'MULAI DARI SINI'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final columns = _columnsFor(constraints.maxWidth);
            final cardWidth =
                (constraints.maxWidth - WebSpacing.cardGap * (columns - 1)) /
                    columns;
            return Wrap(
              spacing: WebSpacing.cardGap,
              runSpacing: WebSpacing.cardGap,
              children: <Widget>[
                SizedBox(
                  width: cardWidth,
                  child: WebActionCard(
                    icon: Icons.fact_check_outlined,
                    title: 'Asesmen',
                    description:
                        'Kenali kondisi Anda lewat asesmen mandiri terstruktur.',
                    accent: MalvaColors.seed,
                    onTap: () => onNavigate(WebRoutes.assessment),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: WebActionCard(
                    icon: Icons.self_improvement_rounded,
                    title: 'Terapi',
                    description:
                        'Latihan dan modul terapi psikologis yang terpandu.',
                    accent: MalvaColors.mint,
                    onTap: () => onNavigate(WebRoutes.therapy),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: WebActionCard(
                    icon: Icons.medical_services_outlined,
                    title: 'Cari Profesional',
                    description:
                        'Temukan psikiater atau psikolog terverifikasi.',
                    accent: MalvaColors.orchid,
                    onTap: () => onNavigate(WebRoutes.professional),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: WebActionCard(
                    icon: Icons.event_available_outlined,
                    title: 'Jadwal Saya',
                    description:
                        'Lihat sesi terapi dan konsultasi yang akan datang.',
                    accent: MalvaColors.amber,
                    onTap: () => onNavigate(WebRoutes.schedule),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: WebSpacing.section),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(WebSpacing.card),
          decoration: BoxDecoration(
            color: MalvaColors.plum.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(WebSpacing.radius),
            border: Border.all(color: MalvaColors.plum.withValues(alpha: 0.14)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.info_outline_rounded,
                color: MalvaColors.plum,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Fase ini baru menyiapkan fondasi web: masuk, navigasi, dan '
                  'kerangka beranda. Fitur asesmen, terapi, dan jadwal akan '
                  'aktif pada fase berikutnya.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: MalvaColors.plum,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _columnsFor(double width) {
    if (width >= 900) return 4;
    if (width >= 600) return 2;
    return 1;
  }
}
