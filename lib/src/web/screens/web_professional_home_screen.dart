import 'package:flutter/material.dart';

import '../../theme.dart';
import '../web_routes.dart';
import '../web_theme.dart';
import '../widgets/web_page_header.dart';

/// Beranda profesional di web (kerangka fase 2A).
///
/// Isi sebenarnya (sesi berjalan, daftar pasien, asesmen masuk) dibangun pada
/// fase berikutnya; di sini hanya pintu masuk yang jelas ke tiap modul.
class WebProfessionalHomeScreen extends StatelessWidget {
  const WebProfessionalHomeScreen({
    super.key,
    required this.displayName,
    required this.onNavigate,
  });

  final String displayName;
  final ValueChanged<String> onNavigate;

  String get _greetingName {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'Profesional';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Selamat bertugas, $_greetingName',
          subtitle: 'Ringkasan praktik Anda akan tampil di sini pada fase '
              'berikutnya. Untuk sekarang, gunakan kartu di bawah.',
        ),
        const SizedBox(height: WebSpacing.section),
        const WebSectionTitle(text: 'PRAKTIK ANDA'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : (constraints.maxWidth >= 600 ? 2 : 1);
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
                    icon: Icons.event_note_outlined,
                    title: 'Jadwal',
                    description:
                        'Sesi terapi dan konsultasi yang menunggu Anda.',
                    accent: MalvaColors.seed,
                    onTap: () => onNavigate(WebRoutes.schedule),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: WebActionCard(
                    icon: Icons.groups_outlined,
                    title: 'Pasien',
                    description: 'Daftar pasien yang terhubung dengan Anda.',
                    accent: MalvaColors.mint,
                    onTap: () => onNavigate(WebRoutes.patients),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: WebActionCard(
                    icon: Icons.fact_check_outlined,
                    title: 'Asesmen',
                    description:
                        'Hasil asesmen pasien yang dibagikan kepada Anda.',
                    accent: MalvaColors.orchid,
                    onTap: () => onNavigate(WebRoutes.assessment),
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
            color: MalvaColors.mint.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(WebSpacing.radius),
            border: Border.all(color: MalvaColors.mint.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.verified_outlined,
                color: MalvaColors.mint,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Kredensial STR/SIP Anda diverifikasi admin. Pastikan nomor '
                  'yang terdaftar sesuai dengan surat izin praktik Anda.',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1F7A66),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
