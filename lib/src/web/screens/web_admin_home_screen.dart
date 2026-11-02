import 'package:flutter/material.dart';

import '../../theme.dart';
import '../web_routes.dart';
import '../web_theme.dart';
import '../widgets/web_page_header.dart';

/// Beranda admin di web (kerangka fase 2A).
///
/// Nilai statistik sengaja ditampilkan sebagai "—" dengan catatan eksplisit,
/// bukan angka palsu: fase ini belum tersambung ke API admin console.
class WebAdminHomeScreen extends StatelessWidget {
  const WebAdminHomeScreen({
    super.key,
    required this.displayName,
    required this.onNavigate,
  });

  final String displayName;
  final ValueChanged<String> onNavigate;

  String get _greetingName {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return 'Admin';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Ringkasan Operasional',
          subtitle: 'Halo $_greetingName. Angka di bawah akan terisi setelah '
              'API admin console tersambung pada fase berikutnya.',
        ),
        const SizedBox(height: WebSpacing.section),
        const WebSectionTitle(text: 'METRIK UTAMA'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 4
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
                  child: const WebStatCard(
                    label: 'Pembayaran tertunda',
                    value: '—',
                    icon: Icons.payments_outlined,
                    note: 'Menunggu integrasi API',
                    accent: MalvaColors.seed,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: const WebStatCard(
                    label: 'Pengguna aktif',
                    value: '—',
                    icon: Icons.people_outline_rounded,
                    note: 'Menunggu integrasi API',
                    accent: MalvaColors.mint,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: const WebStatCard(
                    label: 'Dokter terverifikasi',
                    value: '—',
                    icon: Icons.medical_information_outlined,
                    note: 'Menunggu integrasi API',
                    accent: MalvaColors.orchid,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: const WebStatCard(
                    label: 'Pendapatan bulan ini',
                    value: '—',
                    icon: Icons.trending_up_rounded,
                    note: 'Menunggu integrasi API',
                    accent: MalvaColors.amber,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: WebSpacing.section),
        const WebSectionTitle(text: 'AREA KERJA'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
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
                    icon: Icons.receipt_long_outlined,
                    title: 'Pembayaran',
                    description: 'Verifikasi dan riwayat transaksi.',
                    accent: MalvaColors.seed,
                    onTap: () => onNavigate(WebRoutes.adminPayments),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: WebActionCard(
                    icon: Icons.sell_outlined,
                    title: 'Harga & Paket',
                    description: 'Atur harga sesi dan paket perawatan.',
                    accent: MalvaColors.mint,
                    onTap: () => onNavigate(WebRoutes.adminPricing),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: WebActionCard(
                    icon: Icons.manage_accounts_outlined,
                    title: 'Pengguna',
                    description: 'Kelola akun pasien dan akses aplikasi.',
                    accent: MalvaColors.orchid,
                    onTap: () => onNavigate(WebRoutes.adminUsers),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: WebActionCard(
                    icon: Icons.medical_services_outlined,
                    title: 'Dokter',
                    description: 'Verifikasi kredensial STR/SIP profesional.',
                    accent: MalvaColors.amber,
                    onTap: () => onNavigate(WebRoutes.adminDoctors),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(WebSpacing.radius),
            border: Border.all(color: const Color(0xFFEDE6F1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.shield_outlined,
                color: MalvaColors.plum,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Setiap tindakan admin tercatat di audit log server. Jangan '
                  'membagikan akses akun admin kepada pihak lain.',
                  style: textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
