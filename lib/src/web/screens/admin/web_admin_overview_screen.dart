import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../theme.dart';
import '../../web_format.dart';
import '../../web_routes.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// Beranda konsol admin (`/admin`).
///
/// Metrik diambil dari `GET /v1/admin/overview`. Semua angka berasal dari
/// server — tidak ada nilai contoh/dummy agar admin tidak salah mengambil
/// keputusan berdasarkan data palsu.
class WebAdminOverviewScreen extends ConsumerStatefulWidget {
  const WebAdminOverviewScreen({
    super.key,
    required this.displayName,
    required this.onNavigate,
  });

  final String displayName;
  final ValueChanged<String> onNavigate;

  @override
  ConsumerState<WebAdminOverviewScreen> createState() =>
      _WebAdminOverviewScreenState();
}

class _WebAdminOverviewScreenState
    extends ConsumerState<WebAdminOverviewScreen> {
  AdminOverview? _overview;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String get _accessToken =>
      ref.read(authStateProvider).session?.accessToken ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await ref
          .read(apiClientProvider)
          .adminOverview(accessToken: _accessToken);
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Ringkasan Operasional',
          subtitle:
              'Halo ${widget.displayName.trim().isEmpty ? 'Admin' : widget.displayName.trim()}. '
              'Metrik di bawah dihitung server dalam zona WIB.',
          trailing: OutlinedButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        if (_loading)
          const WebAdminCard(child: WebAdminLoading())
        else if (_error != null)
          WebAdminCard(
            child: WebAdminError(
                error: _error!, onRetry: () => unawaited(_load())),
          )
        else if (overview != null) ...<Widget>[
          const WebSectionTitle(text: 'METRIK UTAMA'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 4
                  : (constraints.maxWidth >= 600 ? 2 : 1);
              final width =
                  (constraints.maxWidth - WebSpacing.cardGap * (columns - 1)) /
                      columns;
              return Wrap(
                spacing: WebSpacing.cardGap,
                runSpacing: WebSpacing.cardGap,
                children: <Widget>[
                  SizedBox(
                    width: width,
                    child: WebStatCard(
                      label: 'Pengguna terdaftar',
                      value: '${overview.usersTotal}',
                      icon: Icons.people_outline_rounded,
                      note:
                          '${overview.usersPatients} pasien · ${overview.usersProfessionals} profesional · '
                          '${overview.usersDisabled} nonaktif',
                      accent: MalvaColors.seed,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: WebStatCard(
                      label: 'Pembayaran lunas',
                      value: '${overview.paidCount}',
                      icon: Icons.payments_outlined,
                      note: '${overview.pendingCount} menunggu verifikasi',
                      accent: MalvaColors.mint,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: WebStatCard(
                      label: 'Pendapatan bulan ini',
                      value: formatRupiah(overview.monthRevenue),
                      icon: Icons.trending_up_rounded,
                      note: 'Akumulasi gross pembayaran lunas (WIB)',
                      accent: MalvaColors.orchid,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: WebStatCard(
                      label: 'Kredensial menunggu',
                      value: '${overview.credentialsPending}',
                      icon: Icons.verified_outlined,
                      note: '${overview.sessionsToday} sesi terjadwal hari ini',
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
              final width =
                  (constraints.maxWidth - WebSpacing.cardGap * (columns - 1)) /
                      columns;
              return Wrap(
                spacing: WebSpacing.cardGap,
                runSpacing: WebSpacing.cardGap,
                children: <Widget>[
                  SizedBox(
                    width: width,
                    child: WebActionCard(
                      icon: Icons.receipt_long_outlined,
                      title: 'Pembayaran',
                      description:
                          'Verifikasi manual, riwayat transaksi, dan refund.',
                      accent: MalvaColors.seed,
                      onTap: () => widget.onNavigate(WebRoutes.adminPayments),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: WebActionCard(
                      icon: Icons.sell_outlined,
                      title: 'Harga & Paket',
                      description: 'Atur harga chat, video, dan paket.',
                      accent: MalvaColors.mint,
                      onTap: () => widget.onNavigate(WebRoutes.adminPricing),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: WebActionCard(
                      icon: Icons.manage_accounts_outlined,
                      title: 'Pengguna',
                      description: 'Ban/unban, reset password, cabut sesi.',
                      accent: MalvaColors.orchid,
                      onTap: () => widget.onNavigate(WebRoutes.adminUsers),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: WebActionCard(
                      icon: Icons.medical_services_outlined,
                      title: 'Dokter',
                      description: 'Verifikasi kredensial STR/SIP profesional.',
                      accent: MalvaColors.amber,
                      onTap: () => widget.onNavigate(WebRoutes.adminDoctors),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: WebSpacing.section),
          WebAdminCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.shield_outlined,
                    color: MalvaColors.plum, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Setiap tindakan admin (override pembayaran, refund, reset '
                    'password, cabut sesi) tercatat di audit log server. '
                    'Jangan membagikan akses akun admin kepada pihak lain.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
