import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';

// ============================================================
// CRISIS INCIDENT LOG (professional)
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
  List<_IncidentRow> _rows = const [];
  bool _isLoading = true;
  String? _error;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
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
      final links = await apiClient.listPatientProfessionalLinks(
        accessToken: accessToken,
      );
      final rows = <_IncidentRow>[];
      await Future.wait(links.map((link) async {
        try {
          final incidents = await apiClient.listCrisisIncidents(
            accessToken: accessToken,
            patientId: link.patientId,
          );
          for (final inc in incidents) {
            rows.add(_IncidentRow(
              incident: inc,
              patientName: link.patientDisplayName.isEmpty
                  ? 'Pasien'
                  : link.patientDisplayName,
            ));
          }
        } on Object catch (_) {
          // Satu pasien gagal tidak menggagalkan semuanya.
        }
      }));
      rows.sort((a, b) {
        final ca = a.incident.createdAt;
        final cb = b.incident.createdAt;
        if (ca == null || cb == null) return 0;
        return cb.compareTo(ca);
      });
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
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
            else if (_rows.isEmpty)
              const EmptyState(
                icon: Icons.shield_outlined,
                title: 'Tidak ada incident',
                subtitle:
                    'Incident krisis (SOS / screening) akan tercatat di sini dengan jejak resolusi.',
              )
            else
              for (final row in _rows) ...[
                _IncidentCard(
                  row: row,
                  onResolve: () => _openResolve(context, row),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _openResolve(BuildContext context, _IncidentRow row) async {
    if (row.incident.status != 'active') return;
    _notesController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tandai Crisis Resolved?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Pasien: ${row.patientName}\nTrigger: ${row.incident.triggeredBy}'),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Resolution notes (wajib)',
                hintText: 'cth: Pasien sudah tenang, kontak keluarga...',
              ),
            ),
          ],
        ),
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
            child: const Text('Mark Crisis Resolved'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final notes = _notesController.text.trim();
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resolution notes wajib diisi.')),
      );
      return;
    }
    try {
      await widget.apiClient!.resolveCrisisIncident(
        accessToken: widget.session!.accessToken!,
        incidentId: row.incident.id,
        resolutionNotes: notes,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incident ditandai resolved. GPS otomatis dihapus.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
      _load();
    } on MalvaApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: MalvaColors.danger),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }
}

class _IncidentRow {
  const _IncidentRow({required this.incident, required this.patientName});

  final BackendCrisisIncident incident;
  final String patientName;
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.row, required this.onResolve});

  final _IncidentRow row;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final active = row.incident.status == 'active';
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: active
                    ? MalvaColors.danger.withValues(alpha: 0.12)
                    : MalvaColors.mint.withValues(alpha: 0.12),
                child: Icon(Icons.person_rounded,
                    color: active ? MalvaColors.danger : MalvaColors.mint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.patientName,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      _dateLabel(row.incident.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: active ? 'ACTIVE' : 'RESOLVED',
                color: active ? MalvaColors.danger : MalvaColors.mint,
                icon: active
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Safety Protocol triggered${row.incident.triggeredBy.isEmpty ? '' : ' • ${row.incident.triggeredBy}'}${row.incident.phq9Q9Score != null ? '\nPHQ-9 Q9 score ${row.incident.phq9Q9Score}' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (row.incident.resolutionNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('Resolution notes\n${row.incident.resolutionNotes}'),
            ),
          ],
          if (active) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onResolve,
                style:
                    FilledButton.styleFrom(backgroundColor: MalvaColors.mint),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Mark Crisis Resolved'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _dateLabel(DateTime? date) {
    if (date == null) return '';
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} $h:$m';
  }
}
