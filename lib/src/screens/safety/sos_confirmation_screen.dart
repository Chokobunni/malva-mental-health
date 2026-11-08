import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/providers.dart';
import '../../platform/platform_providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/dial_fallback.dart';
import '../../widgets/malva_components.dart';
import 'guided_grounding_screen.dart';

// ============================================================
// SOS CONFIRMATION SCREEN
// ============================================================

class SosConfirmationScreen extends ConsumerStatefulWidget {
  const SosConfirmationScreen({super.key, required this.incident});

  final BackendCrisisIncident incident;

  @override
  ConsumerState<SosConfirmationScreen> createState() =>
      _SosConfirmationScreenState();
}

class _SosConfirmationScreenState extends ConsumerState<SosConfirmationScreen> {
  Timer? _pollTimer;
  Timer? _deadline;
  late final SafetyNotifier _notifier;
  String? _accountId;
  bool _refreshing = false;
  bool _timedOut = false;
  bool _accountChanged = false;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(safetyProvider.notifier);
    _accountId = ref.read(currentSessionProvider)?.backendUserId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _deadline?.cancel();
    _notifier.cancelBlastRefresh();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing ||
        _accountChanged ||
        _accountId == null ||
        _accountId != widget.incident.patientId ||
        !widget.incident.deliveryConfigured ||
        _accountId != ref.read(currentSessionProvider)?.backendUserId) return;
    _stopPolling();
    setState(() => _timedOut = false);
    _deadline = Timer(const Duration(seconds: 60), () {
      _stopPolling();
      if (mounted) setState(() => _timedOut = true);
    });
    await _poll();
  }

  Future<void> _poll() async {
    if (!mounted ||
        _accountChanged ||
        _timedOut ||
        _accountId != ref.read(currentSessionProvider)?.backendUserId) return;
    _refreshing = true;
    final blast = await _notifier.refreshBlastStatus(widget.incident.id);
    _refreshing = false;
    if (!mounted ||
        _accountChanged ||
        _timedOut ||
        _accountId != ref.read(currentSessionProvider)?.backendUserId) return;
    if (blast != null && (blast.total == 0 || blast.pending > 0)) {
      _pollTimer = Timer(const Duration(seconds: 2), () => unawaited(_poll()));
    } else {
      _stopPolling();
    }
  }

  String get _mapsLink {
    final lat = widget.incident.latitude;
    final lng = widget.incident.longitude;
    if (lat == null || lng == null) return '';
    return 'https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
  }

  @override
  Widget build(BuildContext context) {
    final safety = ref.watch(safetyProvider);
    final accountChanged = _accountChanged ||
        _accountId == null ||
        _accountId != widget.incident.patientId ||
        _accountId != ref.watch(currentSessionProvider)?.backendUserId;
    ref.listen(
        currentSessionProvider.select((session) => session?.backendUserId),
        (_, __) {
      _stopPolling();
      setState(() => _accountChanged = true);
    });
    if (accountChanged) {
      return Scaffold(
        appBar: AppBar(title: const Text('SOS')),
        body: const Center(
            child: Text('Sesi akun berubah. Buka kembali halaman SOS.')),
      );
    }
    final blast = safety.blastIncidentId == widget.incident.id
        ? safety.blastStatus
        : null;
    final total = blast?.total ?? 0;
    final gagal = blast?.failed ?? 0;
    final menunggu = blast?.pending ?? 0;
    // delivery_configured=false berarti MALVA_FONNTE_TOKEN belum diisi di
    // server. Tanpa peringatan ini, pasien melihat "Terkirim ke N kontak"
    // padahal pesan WhatsApp tidak pernah keluar dari server.
    final unconfigured = !widget.incident.deliveryConfigured;
    final statusText = unconfigured
        ? 'WhatsApp belum tersedia. Pesan belum terkirim.'
        : _timedOut
            ? 'Batas waktu pemeriksaan tercapai. Pengiriman belum dapat dipastikan.'
            : safety.blastError != null
                ? safety.blastError!
                : total == 0
                    ? 'Status pengiriman belum tersedia. Sedang memeriksa…'
                    : 'Antrean: $menunggu • Diterima layanan WhatsApp: ${blast?.sent ?? 0}\n'
                        'Diterima kontak: ${blast?.delivered ?? 0} • Gagal: $gagal';

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Aktif'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SoftCard(
              color: MalvaColors.mint.withValues(alpha: 0.12),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: MalvaColors.mint,
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 34),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Silent Emergency\nSOS Aktif!',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.message_rounded, color: MalvaColors.seed),
                      SizedBox(width: 8),
                      Text('WhatsApp',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const Divider(height: 20),
                  const Text(
                    'Emergency Alert: Bantuan kesehatan mental segera dibutuhkan.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (_mapsLink.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _openMaps(context),
                      child: Text(
                        'Live GPS: $_mapsLink',
                        style: const TextStyle(
                          color: MalvaColors.seed,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: MalvaColors.mint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'SOS',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Status kontak darurat',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          statusText,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (unconfigured)
                          const Text(
                            'Pesan belum terkirim. Hubungi kontak daruratmu sendiri atau hotline 119 ext 8.',
                            style: TextStyle(
                              color: MalvaColors.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else if (gagal > 0 ||
                            _timedOut ||
                            safety.blastError != null)
                          const Text(
                            'Hubungi kontak daruratmu sendiri atau hotline 119 ext 8.',
                            style: TextStyle(
                              color: MalvaColors.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh status',
                    onPressed: unconfigured ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
                    child: const Icon(Icons.medical_services_rounded,
                        color: MalvaColors.seed),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profesional tertaut',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                            'SOS dicatat. Jika perlu, hubungi profesional secara langsung.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Jalur bantuan yang selalu bisa diandalkan, terlepas dari status
            // pengiriman WhatsApp ke kontak darurat.
            FilledButton.icon(
              onPressed: () => _callHotline(context),
              style: FilledButton.styleFrom(
                backgroundColor: MalvaColors.danger,
                minimumSize: const Size.fromHeight(56),
              ),
              icon: const Icon(Icons.call_rounded),
              label: const Text('PANGGIL HOTLINE 119 EXT 8'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GuidedGroundingScreen(),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: MalvaColors.mint,
                minimumSize: const Size.fromHeight(56),
              ),
              icon: const Icon(Icons.self_improvement_rounded),
              label: const Text('Mulai Silent Grounding'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Kembali ke Home'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callHotline(BuildContext context) async {
    if (!ref.read(capabilitiesProvider).canDialTel) {
      await showDialFallbackSheet(context,
          rawTarget: '1198', displayName: 'Hotline 119 ext 8');
      return;
    }
    final uri = Uri(scheme: 'tel', path: '1198');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tidak dapat membuka panggilan. Hubungi 119 ext 8.')),
      );
    }
  }

  Future<void> _openMaps(BuildContext context) async {
    if (_mapsLink.isEmpty) return;
    final uri = Uri.parse(_mapsLink);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat membuka peta.')),
      );
    }
  }
}
