import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../time/wib.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';

// ============================================================
// CRISIS INCIDENT LOG (professional)
//
// Feed kronologis READ-ONLY: gabungan insiden SOS (crisis_incidents) dan flag
// krisis screening (screening_sessions.crisis_flag) untuk SEMUA pasien yang
// terhubung. Satu permintaan (GET /v1/crisis-incident-log), bukan N per pasien.
// Tidak ada form review wajib. Profesional boleh (opsional) menandai insiden
// SOS sebagai sudah ditangani tanpa harus menulis catatan.
// ============================================================

class CrisisIncidentLogScreen extends ConsumerStatefulWidget {
  const CrisisIncidentLogScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<CrisisIncidentLogScreen> createState() =>
      _CrisisIncidentLogScreenState();
}

class _CrisisIncidentLogScreenState
    extends ConsumerState<CrisisIncidentLogScreen> {
  List<BackendCrisisLogItem> _items = const [];
  int _total = 0;
  int _unresolved = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Mode offline aktif. '
              'Hubungkan ke server untuk melihat incident log.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final log =
          await apiClient.getCrisisIncidentLog(accessToken: accessToken);
      if (!mounted) return;
      setState(() {
        _items = log.items;
        _total = log.total;
        _unresolved = log.unresolved;
        _isLoading = false;
      });
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyServerMessage(e.message);
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crisis Incident Log'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              SoftCard(
                child: Column(
                  children: [
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: MalvaColors.danger,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              )
            else if (_items.isEmpty)
              const EmptyState(
                icon: Icons.shield_outlined,
                title: 'Belum ada incident tercatat',
                subtitle:
                    'Insiden krisis (SOS / screening) dari pasien terhubung akan tampil di sini.',
              )
            else ...[
              if (_total > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$_total catatan • $_unresolved SOS perlu tindak lanjut',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Screening adalah catatan kondisi saat pengisian. '
                  'Penanganan SOS dapat dikonfirmasi tanpa menulis catatan.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              for (final item in _items) ...[
                _CrisisLogCard(
                  item: item,
                  onResolve: item.isSos && !item.isResolved
                      ? () => _resolveSos(context, item)
                      : null,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Tandai insiden SOS sudah ditangani TANPA catatan (opsional, tidak wajib).
  Future<void> _resolveSos(
      BuildContext context, BackendCrisisLogItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tandai sudah ditangani?'),
        content: Text('Insiden SOS pasien ${item.patientName} akan ditandai '
            'sudah ditangani. Catatan tidak wajib diisi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle.copyWith(
              backgroundColor: const WidgetStatePropertyAll(MalvaColors.mint),
            ),
            child: const Text('Tandai sudah ditangani'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) return;
    try {
      await apiClient.resolveCrisisIncident(
        accessToken: accessToken,
        incidentId: item.id,
        resolutionNotes: '',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incident ditandai sudah ditangani.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
      await _load();
    } on MalvaApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyServerMessage(e.message)),
            backgroundColor: MalvaColors.danger),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }
}

class _CrisisLogCard extends StatelessWidget {
  const _CrisisLogCard({required this.item, this.onResolve});

  final BackendCrisisLogItem item;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    // PIl sumber: SOS (merah) vs Screening (amber).
    final isSos = item.isSos;
    final pillColor = isSos ? MalvaColors.danger : MalvaColors.amber;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: pillColor.withValues(alpha: 0.12),
                child: Icon(
                  isSos ? Icons.sos_rounded : Icons.fact_check_rounded,
                  color: pillColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.patientName,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      formatIncidentDate(item.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: isSos ? 'SOS' : 'Screening',
                color: pillColor,
                icon: isSos
                    ? Icons.warning_amber_rounded
                    : Icons.fact_check_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title.isEmpty
                ? (isSos ? 'SOS darurat' : 'Screening krisis')
                : item.title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (item.detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.detail,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              StatusPill(
                label: !isSos
                    ? 'Riwayat screening'
                    : item.isResolved
                        ? 'Sudah ditangani'
                        : 'Perlu tindak lanjut',
                color: !isSos
                    ? MalvaColors.amber
                    : item.isResolved
                        ? MalvaColors.mint
                        : MalvaColors.danger,
                icon: !isSos
                    ? Icons.history_rounded
                    : item.isResolved
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
              ),
            ],
          ),
          if (item.resolutionNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('Catatan penanganan\n${item.resolutionNotes}'),
            ),
          ],
          if (onResolve != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onResolve,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Tandai sudah ditangani'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Waktu insiden krisis (`d/M/yyyy HH:mm`) dalam waktu WIB.
///
/// Format waktu insiden server memakai helper WIB yang sama dengan layar lain.
String formatIncidentDate(DateTime? date) {
  if (date == null) return '';
  return formatWibDateTimeShort(date);
}
