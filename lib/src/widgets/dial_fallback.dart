import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../platform/contracts/ports.dart';

/// Lembar fallback panggilan untuk platform tanpa `tel:` yang andal (web).
///
/// Menampilkan nomor + tombol salin + tautan WhatsApp. Mengembalikan
/// [DialOutcome.fallbackShown] agar pemanggil bisa menandai bahwa aksi
/// dilakukan lewat fallback (bukan panggilan langsung).
Future<DialOutcome> showDialFallbackSheet(
  BuildContext context, {
  required String rawTarget,
  String? displayName,
}) async {
  final number = _phoneDigits(rawTarget);
  await showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              (displayName ?? '').trim().isNotEmpty
                  ? displayName!.trim()
                  : 'Hubungi nomor',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 10),
            SelectableText(
              number.isEmpty ? rawTarget : number,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: number));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Nomor disalin.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Salin nomor'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
                if (digits.isEmpty) return;
                final wa = Uri.parse('https://wa.me/$digits');
                if (await canLaunchUrl(wa)) {
                  await launchUrl(wa, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.chat_rounded),
              label: const Text('Chat WhatsApp'),
            ),
          ],
        ),
      ),
    ),
  );
  return DialOutcome.fallbackShown;
}

/// Ambil digit nomor dari target `tel:`/`sms:`/angka mentah.
String _phoneDigits(String raw) {
  final uri = Uri.tryParse(raw);
  final candidate = (uri != null && uri.path.isNotEmpty) ? uri.path : raw;
  return candidate.replaceAll(RegExp(r'[^0-9+]'), '');
}
