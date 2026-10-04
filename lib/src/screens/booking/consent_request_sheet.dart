import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';

// ============================================================
// CONSENT REQUEST SHEET â€” Continuous Support 7 Days.
// Pasien memberi izin kepada profesional untuk memantau progres:
//   - Diary (riwayat harian)
//   - Goals (target & streak)
//   - Health Record (dokumen klinis)
//   - Mood & Medication check-in tracker
// Izin disimpan ke /v1/privacy/consents (backend) bila online.
// Bila offline: disimpan lokal dan disinkronkan saat terhubung.
// ============================================================

/// Tampilkan sheet permintaan izin. Return true bila pasien setuju.
Future<bool> showConsentRequestSheet({required BuildContext context}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) => const _ConsentRequestSheet(),
  );
  return result == true;
}

class _ConsentRequestSheet extends ConsumerStatefulWidget {
  const _ConsentRequestSheet();

  @override
  ConsumerState<_ConsentRequestSheet> createState() =>
      _ConsentRequestSheetState();
}

class _ConsentRequestSheetState extends ConsumerState<_ConsentRequestSheet> {
  bool _diary = true;
  bool _goals = true;
  bool _healthRecord = true;
  bool _moodCheckin = true;
  bool _medicationCheckin = true;
  bool _isSaving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: MalvaColors.mint.withValues(alpha: 0.15),
                  child: const Icon(Icons.handshake_rounded,
                      color: MalvaColors.mint),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Allow Progress Monitoring?',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your professional can follow your progress for the next 7 days '
              '(Continuous Support). Choose what you want to share â€” you can '
              'change this anytime.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            _ConsentToggle(
              icon: Icons.edit_note_rounded,
              color: MalvaColors.seed,
              title: 'Diary',
              subtitle: 'Riwayat catatan harianmu',
              value: _diary,
              onChanged: (v) => setState(() => _diary = v),
            ),
            _ConsentToggle(
              icon: Icons.flag_rounded,
              color: MalvaColors.amber,
              title: 'Goals',
              subtitle: 'Target harian & streak',
              value: _goals,
              onChanged: (v) => setState(() => _goals = v),
            ),
            _ConsentToggle(
              icon: Icons.folder_shared_rounded,
              color: MalvaColors.mint,
              title: 'Health Record',
              subtitle: 'Dokumen & catatan klinis',
              value: _healthRecord,
              onChanged: (v) => setState(() => _healthRecord = v),
            ),
            _ConsentToggle(
              icon: Icons.mood_rounded,
              color: MalvaColors.orchid,
              title: 'Mood Check-in Tracker',
              subtitle: 'Tren mood harian',
              value: _moodCheckin,
              onChanged: (v) => setState(() => _moodCheckin = v),
            ),
            _ConsentToggle(
              icon: Icons.medication_rounded,
              color: MalvaColors.seed,
              title: 'Medication Check-in Tracker',
              subtitle: 'Kepatuhan minum obat',
              value: _medicationCheckin,
              onChanged: (v) => setState(() => _medicationCheckin = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                    color: MalvaColors.danger, fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(_isSaving ? 'Menyimpan...' : 'Allow & Continue'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isSaving ? null : () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              child: const Text('Not Now'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final rawToken = ref.read(currentSessionProvider)?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    final professionalId = _resolveProfessionalId();
    if (accessToken == null || professionalId == null) {
      // Offline / tanpa link profesional: izin disimpan lokal (pref).
      await _saveLocalPreferences();
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Izin monitoring disimpan di perangkat. Disinkronkan saat terhubung.'),
        ),
      );
      return;
    }
    try {
      await ref.read(apiClientProvider).updatePrivacyConsent(
            accessToken: accessToken,
            professionalId: professionalId,
            shareScreenings: true,
            shareMoodDiary: _moodCheckin || _diary,
            shareMedications: _medicationCheckin,
            shareTimeline: true,
          );
      await _saveLocalPreferences();
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Izin monitoring 7 hari aktif. Profesional dapat memantau progresmu.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      // Gagal server: tetap lanjut dengan izin lokal.
      await _saveLocalPreferences();
      setState(() {
        _isSaving = false;

        _error = friendlyErrorMessage(e);
      });
      Navigator.pop(context, true);
    }
  }

  String? _resolveProfessionalId() {
    final rawToken = ref.read(currentSessionProvider)?.accessToken;
    if (rawToken == null || rawToken.isEmpty) return null;
    // Ambil dari sesi yang aktif: identifier profesional bila role-nya cocok.
    final session = ref.read(currentSessionProvider);
    if (session?.backendUserId != null &&
        (session?.backendUserId?.isNotEmpty ?? false)) {
      return session!.backendUserId;
    }
    return null;
  }

  Future<void> _saveLocalPreferences() async {
    final store = ref.read(malvaStoreProvider.notifier);
    await store.setContinuousSupportConsent(
      diary: _diary,
      goals: _goals,
      healthRecord: _healthRecord,
      moodCheckin: _moodCheckin,
      medicationCheckin: _medicationCheckin,
    );
  }
}

class _ConsentToggle extends StatelessWidget {
  const _ConsentToggle({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: value ? color.withValues(alpha: 0.06) : null,
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13.5)),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black54)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: color,
            ),
          ],
        ),
      ),
    );
  }
}
