import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/data/crisis_provider.dart';
import '../theme.dart';

// ============================================================
// CRISIS HOTLINE BANNER
// ============================================================

class CrisisHotlineBanner extends ConsumerWidget {
  const CrisisHotlineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crisis = ref.watch(crisisProvider);
    if (!crisis.isActive) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB00020), Color(0xFFD32F2F)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB00020).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Crisis Detected',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Hasil screening menunjukkan krisis aktif',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _callHotline(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB00020),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.phone_rounded, size: 20),
                  label: const Text(
                    'Hubungi 119 ext 8',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () => ref.read(crisisProvider.notifier).dismiss(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _callHotline(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hubungi Darurat?'),
        content: Text(
          'Menghubungi $crisisHotlineName\n'
          'Nomor: $crisisHotlineNumber extension $crisisHotlineExtension\n\n'
          '$crisisHotlineDescription',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: MalvaColors.danger),
            child: const Text('Hubungi Sekarang'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(crisisProvider.notifier).callExtension();
    }
  }
}

// ============================================================
// CRISIS FLOATING ACTION BUTTON
// ============================================================

class CrisisFab extends ConsumerWidget {
  const CrisisFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCrisis = ref.watch(hasCrisisFlagProvider);
    if (!hasCrisis) return const SizedBox.shrink();

    return FloatingActionButton.extended(
      onPressed: () => _callHotline(ref),
      backgroundColor: const Color(0xFFB00020),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.phone_rounded),
      label: const Text(
        'Darurat',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Future<void> _callHotline(WidgetRef ref) async {
    final uri = Uri(scheme: 'tel', path: '1198');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      ref.read(crisisProvider.notifier).dismiss();
    }
  }
}
