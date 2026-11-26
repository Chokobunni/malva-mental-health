import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import 'booking_owner.dart';

Future<bool> showConsentRequestSheet({
  required BuildContext context,
  required String professionalId,
  required String professionalName,
  bool oneTime = false,
  MalvaApiClient? apiClient,
  AuthSession? Function()? ownerSession,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xfffaf1f8),
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => ManageDataSheet(
        professionalId: professionalId,
        professionalName: professionalName,
        apiClient: apiClient,
        checkout: true,
        oneTime: oneTime,
        ownerSession: ownerSession),
  );
  return result == true;
}

class ManageDataSheet extends ConsumerStatefulWidget {
  const ManageDataSheet({
    super.key,
    required this.professionalId,
    required this.professionalName,
    this.checkout = false,
    this.oneTime = false,
    this.ownerSession,
    this.apiClient,
  });

  final String professionalId;
  final String professionalName;
  final bool checkout;
  final bool oneTime;
  final AuthSession? Function()? ownerSession;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<ManageDataSheet> createState() => _ManageDataSheetState();
}

class _ManageDataSheetState extends ConsumerState<ManageDataSheet> {
  // Default MATI (opt-in eksplisit); nilai riil dimuat dari server.
  late final BookingOwner _owner;
  bool _screenings = false;
  bool _moodDiary = false;
  bool _medications = false;
  bool _healthRecord = false;
  bool _goals = false;
  // Kategori Therapy Record (worksheet CBT/DBT) — OPT-IN, default MATI.
  bool _therapyRecords = false;
  bool _isLoading = true;
  bool _loaded = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _owner = BookingOwner(ref, null);
    if (widget.checkout) {
      _isLoading = false;
      _loaded = true;
    } else {
      _load();
    }
  }

  AuthSession? get _session =>
      widget.ownerSession == null ? _owner.session : widget.ownerSession!();

  Future<void> _load() async {
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final token = _session?.accessToken;
    if (token == null || token.isEmpty || widget.professionalId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loaded = widget.checkout;
          _error = widget.checkout
              ? null
              : 'Mode offline aktif. '
                  'Hubungkan ke server untuk mengatur persetujuan ini.';
        });
      }
      return;
    }
    try {
      final consent = await apiClient.getPrivacyConsent(
        accessToken: token,
        professionalId: widget.professionalId,
      );
      if (!mounted || _session == null) return;
      setState(() {
        if (!widget.checkout) {
          _screenings = consent.shareScreenings;
          _moodDiary = consent.shareMoodDiary;
          _medications = consent.shareMedications;
          _healthRecord = consent.shareHealthRecord;
          _goals = consent.shareGoals;
          _therapyRecords = consent.shareTherapyRecords;
        }
        _isLoading = false;
        _loaded = true;
      });
    } on Object catch (e) {
      if (!mounted || _session == null) return;
      setState(() {
        _isLoading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSessionProvider);
    final count = [
      _screenings,
      _moodDiary,
      _medications,
      _goals,
      _healthRecord,
      _therapyRecords,
    ].where((enabled) => enabled).length;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
                child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xffdfe1e8),
                borderRadius: BorderRadius.circular(8),
              ),
            )),
            const SizedBox(height: 14),
            Row(children: [
              const _ConsentIcon('privacy', size: 28),
              const SizedBox(width: 7),
              const Expanded(
                  child: Text('Privasi & Akses Data',
                      style: TextStyle(color: MalvaColors.seed))),
              IconButton(
                tooltip: 'Tutup',
                onPressed: _isSaving ? null : () => Navigator.maybePop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            Text('Atur Data Konseling',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(widget.professionalName,
                style: const TextStyle(
                    color: MalvaColors.seed, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(widget.oneTime
                ? 'Pilih kategori data yang diizinkan untuk diakses oleh profesional selama sesi konsultasi berlangsung.'
                : 'Pilih kategori data yang diizinkan untuk diakses oleh profesional selama masa paket aktif Anda.'),
            const SizedBox(height: 14),
            if (_session == null && !widget.checkout && _error == null)
              const Text('Sesi akun tidak tersedia.')
            else if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null && !_loaded)
              TextButton(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _error = null;
                    });
                    _load();
                  },
                  child: Text('$_error Coba lagi'))
            else ...[
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xffece2f3)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _Toggle(
                  asset: 'all',
                  label: 'Pilih Semua Data',
                  description: '$count dari 6 kategori aktif',
                  value: count == 6,
                  onChanged: _isSaving
                      ? null
                      : (enabled) => setState(() {
                            _screenings = _moodDiary = _medications = _goals =
                                _healthRecord = _therapyRecords = enabled;
                          }),
                ),
              ),
              const SizedBox(height: 8),
              _Toggle(
                  asset: 'assessment',
                  label: 'Asesmen',
                  description:
                      'Hasil kuesioner skrining kesehatan mental berkala (WHO-5, PHQ-9 + GAD-7, dan DASS-21).',
                  value: _screenings,
                  onChanged: _isSaving
                      ? null
                      : (v) => setState(() => _screenings = v)),
              const Divider(height: 1),
              _Toggle(
                  asset: 'mood',
                  label: 'Mood & Jurnal Harian',
                  description: 'Catatan perasaan harian dan refleksi pribadi.',
                  value: _moodDiary,
                  onChanged:
                      _isSaving ? null : (v) => setState(() => _moodDiary = v)),
              const Divider(height: 1),
              _Toggle(
                  asset: 'medication',
                  label: 'Catatan Obat & Resep',
                  description: 'Daftar konsumsi obat dan jadwal pengingat.',
                  value: _medications,
                  onChanged: _isSaving
                      ? null
                      : (v) => setState(() => _medications = v)),
              const Divider(height: 1),
              _Toggle(
                  asset: 'goals',
                  label: 'Target & Kebiasaan',
                  description: 'Progres kebiasaan positif dan tujuan terapi.',
                  value: _goals,
                  onChanged:
                      _isSaving ? null : (v) => setState(() => _goals = v)),
              const Divider(height: 1),
              _Toggle(
                  asset: 'clinical',
                  label: 'Profil Klinis',
                  description:
                      'Riwayat diagnosis dan catatan klinis sebelumnya.',
                  value: _healthRecord,
                  onChanged: _isSaving
                      ? null
                      : (v) => setState(() => _healthRecord = v)),
              const Divider(height: 1),
              _Toggle(
                  asset: 'therapy',
                  label: 'Riwayat Terapi (Psikologis)',
                  description:
                      'Profesional dapat melihat lembar kerja terapi CBT/DBT yang kamu isi (ABCDE, Jebakan Pikiran, TIPP, dll).',
                  value: _therapyRecords,
                  onChanged: _isSaving
                      ? null
                      : (v) => setState(() => _therapyRecords = v)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(color: MalvaColors.danger)),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(_isSaving ? 'Menyimpan...' : 'Simpan'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_loaded || _isSaving) return;
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final token = _session?.accessToken;
    if (widget.ownerSession != null && _session == null) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      if (token != null &&
          token.isNotEmpty &&
          widget.professionalId.isNotEmpty) {
        await apiClient.updatePrivacyConsent(
          accessToken: token,
          professionalId: widget.professionalId,
          shareScreenings: _screenings,
          shareMoodDiary: _moodDiary,
          shareMedications: _medications,
          shareHealthRecord: _healthRecord,
          shareGoals: _goals,
          shareTherapyRecords: _therapyRecords,
        );
      }
      if (!mounted) return;
      if (widget.ownerSession != null && _session == null) {
        Navigator.pop(context, false);
        return;
      }
      if (widget.checkout) {
        await ref.read(malvaStoreProvider.notifier).setContinuousSupportConsent(
              diary: _moodDiary,
              goals: _goals,
              healthRecord: _healthRecord,
              moodCheckin: _moodDiary,
              medicationCheckin: _medications,
              therapyRecords: _therapyRecords,
            );
        if (!mounted) return;
        final valid = widget.ownerSession == null || _session != null;
        Navigator.pop(context, valid);
        if (valid) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(widget.oneTime
                ? 'Pilihan berbagi data berlaku saat sesi berlangsung.'
                : 'Pilihan berbagi data berlaku selama paket aktif.'),
          ));
        }
      } else if (_session != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pengaturan sharing tersimpan.')),
        );
      }
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _ConsentIcon extends StatelessWidget {
  const _ConsentIcon(this.asset, {this.size = 44});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/care/consent-$asset.png',
        width: size,
        height: size,
        cacheWidth: 144,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.asset,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String asset, label, description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      secondary: _ConsentIcon(asset),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)),
      activeThumbColor: MalvaColors.seed,
      activeTrackColor: const Color(0xffd8afea),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    );
  }
}
