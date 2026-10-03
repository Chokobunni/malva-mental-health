import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    await ref
        .read(safetyProvider.notifier)
        .refreshBlastStatus(widget.incident.id);
    if (mounted) setState(() {});
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
    final blast = safety.blastStatus;
    final delivered = (blast?.delivered ?? 0) + (blast?.sent ?? 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Terkirim'),
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
                      'Silent Emergency\nSOS Sent!',
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
                      Text('SMS/WhatsApp',
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
                      'LIVE',
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
                          'Contacting Emergency Contacts...',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Terkirim ke $delivered dari ${blast?.total ?? safety.contacts.length} kontak',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh status',
                    onPressed: _refresh,
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
                        Text('Notified (High Priority)'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
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
