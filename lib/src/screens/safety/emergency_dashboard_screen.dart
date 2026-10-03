import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/providers.dart';
import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/malva_components.dart';
import 'emergency_contacts_screen.dart';
import 'guided_grounding_screen.dart';
import 'sos_confirmation_screen.dart';

// ============================================================
// EMERGENCY DASHBOARD (SAFETY PROTOCOL)
// ============================================================

class EmergencyDashboardScreen extends ConsumerStatefulWidget {
  const EmergencyDashboardScreen({super.key, this.fromCrisisFlag = false});

  /// True bila dibuka otomatis karena PHQ-9 Q9 positif.
  final bool fromCrisisFlag;

  @override
  ConsumerState<EmergencyDashboardScreen> createState() =>
      _EmergencyDashboardScreenState();
}

class _EmergencyDashboardScreenState
    extends ConsumerState<EmergencyDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController;

  @override
  void initState() {
    super.initState();
    // Siklus napas 4-7-8 = 19 detik per putaran.
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 19),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(safetyProvider.notifier).load());
    });
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safety = ref.watch(safetyProvider);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const GradientHeader(
            title: 'Kami di sini bersamamu',
            subtitle:
                'Kamu tidak sendirian. Mari pelan-pelan selesaikan momen ini bersama.',
            leading:
                Icon(Icons.favorite_rounded, color: Colors.white, size: 34),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.fromCrisisFlag) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: MalvaColors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: MalvaColors.danger.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: MalvaColors.danger),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Hasil screening menunjukkan risiko. Halaman ini membantu kamu tetap aman.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                BreathingCircle(controller: _breathController),
                const SizedBox(height: 22),
                _PillarButton(
                  label: 'PANGGIL HOTLINE 119 EXT 8',
                  sublabel: '(BEBAS PULSA)',
                  icon: Icons.phone_in_talk_rounded,
                  color: MalvaColors.danger,
                  onPressed: () => _callHotline(context),
                ),
                const SizedBox(height: 12),
                _PillarButton(
                  label: 'SILENT SOS ALERT',
                  sublabel: safety.contacts.isEmpty
                      ? '(TAMBAHKAN KONTAK DARURAT DULU)'
                      : '(KIRIM GPS KE KONTAK DARURAT)',
                  icon: Icons.notifications_active_rounded,
                  color: MalvaColors.amber,
                  foregroundColor: MalvaColors.ink,
                  isLoading: safety.isLoading,
                  onPressed: () => _sendSilentSOS(context, ref),
                ),
                const SizedBox(height: 12),
                _PillarButton(
                  label: 'GUIDED GROUNDING',
                  sublabel: '(TANPA BICARA)',
                  icon: Icons.self_improvement_rounded,
                  color: MalvaColors.mint,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GuidedGroundingScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 22),
                const SectionLabel('Bagaimana perasaanmu saat ini?'),
                _FeelingChips(
                  onSelected: (label) => _sendSilentSOS(
                    context,
                    ref,
                    message: 'Pasien memilih ekspresi cepat: $label',
                  ),
                ),
                const SizedBox(height: 22),
                SectionLabel(
                  'Kontak Darurat',
                  action: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EmergencyContactsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: const Text('Kelola'),
                  ),
                ),
                if (safety.contacts.isEmpty)
                  const EmptyState(
                    icon: Icons.contact_emergency_outlined,
                    title: 'Belum ada kontak darurat',
                    subtitle:
                        'Tambahkan minimal 1 kontak agar Silent SOS bisa dikirim. Maksimal 5 kontak.',
                  )
                else
                  for (final contact in safety.contacts)
                    _EmergencyContactRow(contact: contact),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: MalvaColors.seed.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.location_on_outlined, color: MalvaColors.seed),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Lokasi GPS hanya dibagikan saat kamu menekan Silent SOS, dan dihapus otomatis setelah krisis selesai.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 76),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _callHotline(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: '119');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tidak dapat membuka panggilan. Hubungi 119 ext 8.')),
      );
    }
  }

  Future<void> _sendSilentSOS(
    BuildContext context,
    WidgetRef ref, {
    String message = '',
  }) async {
    final notifier = ref.read(safetyProvider.notifier);
    final contacts = ref.read(safetyProvider).contacts;
    if (contacts.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tambahkan kontak darurat terlebih dahulu.'),
          backgroundColor: MalvaColors.amber,
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_rounded,
            color: MalvaColors.amber, size: 42),
        title: const Text('Kirim Silent SOS?'),
        content: Text(
          'Pesan darurat + lokasi GPS akan dikirim ke ${contacts.length} kontak darurat dan profesional tertaut. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: MalvaColors.amber),
            child: const Text('Kirim SOS',
                style: TextStyle(color: MalvaColors.ink)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    double? lat;
    double? lng;
    try {
      final permission = await Geolocator.checkPermission();
      final granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse ||
          await Geolocator.requestPermission() ==
              LocationPermission.whileInUse ||
          await Geolocator.requestPermission() == LocationPermission.always;
      if (granted) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } on Object catch (_) {
      // GPS opsional — SOS tetap dikirim tanpa lokasi.
    }

    try {
      final incident = await notifier.sendSilentSOS(
        latitude: lat,
        longitude: lng,
        message: message,
      );
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SosConfirmationScreen(incident: incident),
        ),
      );
    } on AuthFailure catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } on MalvaApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: MalvaColors.danger),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim SOS: $e')),
      );
    }
  }
}

// ============================================================
// BREATHING CIRCLE (4-7-8 animation)
// ============================================================

class BreathingCircle extends StatelessWidget {
  const BreathingCircle({super.key, required this.controller});

  final AnimationController controller;

  static const _inhaleEnd = 4 / 19;
  static const _holdEnd = 11 / 19;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 220,
        height: 220,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value;
            double scale;
            String label;
            if (t < _inhaleEnd) {
              final p = t / _inhaleEnd;
              scale = 0.72 + 0.28 * _easeInOut(p);
              label = 'Tarik Napas...\n${(4 - p * 4).ceil()}s';
            } else if (t < _holdEnd) {
              scale = 1.0;
              label =
                  'Tahan...\n${(7 - ((t - _inhaleEnd) / (_holdEnd - _inhaleEnd)) * 7).ceil()}s';
            } else {
              final p = (t - _holdEnd) / (1 - _holdEnd);
              scale = 1.0 - 0.28 * _easeInOut(p);
              label = 'Hembuskan...\n${(8 - p * 8).ceil()}s';
            }
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 220 * scale,
                  height: 220 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MalvaColors.orchid.withValues(alpha: 0.15),
                  ),
                ),
                Container(
                  width: 170 * scale,
                  height: 170 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [MalvaColors.orchid, MalvaColors.pink],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: MalvaColors.orchid.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _easeInOut(double p) {
    final c = (p.clamp(0.0, 1.0) - 0.5) * math.pi;
    return (1 - math.cos(c)) / 2;
  }
}

// ============================================================
// PILLAR BUTTON
// ============================================================

class _PillarButton extends StatelessWidget {
  const _PillarButton({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.foregroundColor = Colors.white,
    this.isLoading = false,
  });

  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final Color foregroundColor;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foregroundColor,
        minimumSize: const Size.fromHeight(64),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: foregroundColor,
              ),
            )
          else
            Icon(icon, size: 26),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: foregroundColor.withValues(alpha: 0.85),
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

// ============================================================
// FEELING CHIPS
// ============================================================

class _FeelingChips extends StatelessWidget {
  const _FeelingChips({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const _feelings = [
    ('Napas Sesak', Icons.air_rounded),
    ('Gemetaran', Icons.vibration_rounded),
    ('Takut Sendirian', Icons.person_off_outlined),
    ('Jantung Berdebar', Icons.favorite_rounded),
    ('Pusing', Icons.refresh_rounded),
    ('Mual', Icons.sick_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, icon) in _feelings)
          ActionChip(
            avatar: Icon(icon, size: 16, color: MalvaColors.seed),
            label: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => onSelected(label),
            backgroundColor: MalvaColors.seed.withValues(alpha: 0.07),
            side: BorderSide(
              color: MalvaColors.seed.withValues(alpha: 0.25),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// EMERGENCY CONTACT ROW
// ============================================================

class _EmergencyContactRow extends StatelessWidget {
  const _EmergencyContactRow({required this.contact});

  final BackendEmergencyContact contact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
              child: Text(
                contact.contactName.isEmpty
                    ? '?'
                    : contact.contactName.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: MalvaColors.seed,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.contactName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${contact.contactPhone}${contact.relationship.isEmpty ? '' : ' • ${contact.relationship}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Panggil',
              onPressed: () => _call('tel:${contact.contactPhone}', context),
              icon: const Icon(Icons.phone_rounded, color: MalvaColors.seed),
            ),
            IconButton(
              tooltip: 'SMS',
              onPressed: () => _call('sms:${contact.contactPhone}', context),
              icon:
                  const Icon(Icons.message_rounded, color: MalvaColors.orchid),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _call(String url, BuildContext context) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tidak dapat membuka aplikasi telepon/SMS.')),
      );
    }
  }
}
