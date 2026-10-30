import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/google_account_card.dart';
import '../widgets/malva_components.dart';

/// Layar pengelolaan Akun Google (pasien & profesional).
///
/// Menjelaskan aturan kepemilikan (1 Gmail = 1 akun, 1 STR/SIP = 1 profesional)
/// lalu menampilkan [GoogleAccountCard] yang menangani penautan & Google Meet.
class GoogleAccountScreen extends StatelessWidget {
  const GoogleAccountScreen({
    super.key,
    required this.session,
    required this.apiClient,
    this.showMeet = false,
  });

  final AuthSession session;

  /// Klien API. Disimpan untuk konsistensi antar layar; kartu memakai
  /// `apiClientProvider` agar mudah diuji dengan klien palsu.
  final MalvaApiClient apiClient;

  /// true untuk profesional: tampilkan bagian Google Meet.
  final bool showMeet;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Akun Google'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: MalvaColors.seed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Aturan akun',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Satu Gmail hanya boleh terhubung ke satu akun Malva. '
                  'Satu nomor STR/SIP hanya boleh dimiliki satu akun '
                  'profesional.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GoogleAccountCard(session: session, showMeet: showMeet),
          const SizedBox(height: 18),
          const SectionLabel('Privasi', icon: Icons.lock_outline_rounded),
          const Text(
            'Malva hanya memakai Gmail Anda untuk masuk dan, bila Anda '
            'mengaktifkannya, membuat tautan Google Meet untuk sesi video. '
            'Kami tidak membaca isi email Anda.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
