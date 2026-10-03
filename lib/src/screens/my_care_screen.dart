import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

// ============================================================
// MY CARE — jadwal sesi + daftar profesional (Active/Ended)
// ============================================================

class MyCareScreen extends ConsumerStatefulWidget {
  const MyCareScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<MyCareScreen> createState() => _MyCareScreenState();
}

class _MyCareScreenState extends ConsumerState<MyCareScreen> {
  String _tab = 'Schedule';
  List<BackendPatientProfessionalLink> _links = const [];
  List<BackendBooking> _bookings = const [];
  bool _isLoading = true;
  String? _error;

  static const _tabs = [
    'Schedule',
    'Upcoming',
    'Past History',
    'Professionals'
  ];

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
          _error = 'Login diperlukan.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        apiClient.listPatientProfessionalLinks(accessToken: accessToken),
        apiClient.listBookings(accessToken: accessToken, limit: 50),
      ]);
      if (!mounted) return;
      setState(() {
        _links = results[0] as List<BackendPatientProfessionalLink>;
        _bookings = results[1] as List<BackendBooking>;
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
        _error = 'Gagal memuat My Care: $e';
        _isLoading = false;
      });
    }
  }

  List<BackendBooking> get _upcoming => _bookings
      .where((b) =>
          b.status == 'paid' || b.status == 'pending' || b.status == 'active')
      .toList();

  List<BackendBooking> get _past => _bookings
      .where((b) => b.status == 'completed' || b.status == 'cancelled')
      .toList();

  List<BackendPatientProfessionalLink> get _activeLinks =>
      _links.where((l) => l.status == 'active').toList();

  List<BackendPatientProfessionalLink> get _endedLinks =>
      _links.where((l) => l.status != 'active').toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Care'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tab in _tabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tab,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        selected: _tab == tab,
                        onSelected: (_) => setState(() => _tab = tab),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
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
            else if (_tab == 'Professionals')
              ..._professionalsBody()
            else
              ..._scheduleBody(),
          ],
        ),
      ),
    );
  }

  List<Widget> _scheduleBody() {
    final list = _tab == 'Upcoming' ? _upcoming : _past;
    if (list.isEmpty) {
      return [
        EmptyState(
          icon: _tab == 'Upcoming'
              ? Icons.event_available_outlined
              : Icons.history_rounded,
          title: _tab == 'Upcoming'
              ? 'Tidak ada sesi mendatang'
              : 'Belum ada riwayat sesi',
          subtitle: _tab == 'Upcoming'
              ? 'Booking konsultasi untuk menjadwalkan sesi.'
              : 'Sesi yang selesai akan tercatat di sini.',
        ),
      ];
    }
    return [
      for (final b in list) ...[
        _SessionCard(booking: b),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _professionalsBody() {
    if (_links.isEmpty) {
      return [
        const EmptyState(
          icon: Icons.medical_services_outlined,
          title: 'Belum ada profesional',
          subtitle: 'Hubungkan akun dengan profesional untuk mulai.',
        ),
      ];
    }
    final active = _activeLinks;
    final ended = _endedLinks;
    return [
      if (active.isNotEmpty) ...[
        const SectionLabel('Active'),
        for (final link in active) ...[
          _ProfessionalLinkCard(link: link, active: true),
          const SizedBox(height: 10),
        ],
      ],
      if (ended.isNotEmpty) ...[
        const SectionLabel('Ended'),
        for (final link in ended) ...[
          _ProfessionalLinkCard(link: link, active: false),
          const SizedBox(height: 10),
        ],
      ],
    ];
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.booking});

  final BackendBooking booking;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
            child: const Icon(Icons.videocam_rounded, color: MalvaColors.seed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${booking.serviceType} • 30 minutes',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${booking.bookingDate} • ${booking.status}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfessionalLinkCard extends StatelessWidget {
  const _ProfessionalLinkCard({required this.link, required this.active});

  final BackendPatientProfessionalLink link;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: active
                ? MalvaColors.mint.withValues(alpha: 0.12)
                : Colors.black12,
            child: Icon(Icons.person_rounded,
                color: active ? MalvaColors.mint : Colors.black45),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  link.professionalDisplayName.isEmpty
                      ? 'Profesional'
                      : link.professionalDisplayName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  'Status: ${link.status}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          StatusPill(
            label: 'Sharing',
            color: active ? MalvaColors.mint : Colors.black45,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MANAGE DATA — sharing toggles inline per profesional
// ============================================================

class ManageDataSheet extends ConsumerStatefulWidget {
  const ManageDataSheet({
    super.key,
    required this.professionalId,
    required this.professionalName,
  });

  final String professionalId;
  final String professionalName;

  @override
  ConsumerState<ManageDataSheet> createState() => _ManageDataSheetState();
}

class _ManageDataSheetState extends ConsumerState<ManageDataSheet> {
  bool _mood = true;
  bool _diary = true;
  bool _goals = true;
  bool _record = true;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiClient = ref.read(apiClientProvider);
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Login diperlukan.';
        });
      }
      return;
    }
    try {
      final consent = await apiClient.getPrivacyConsent(
        accessToken: token,
        professionalId: widget.professionalId,
      );
      if (!mounted) return;
      setState(() {
        _mood = consent.shareMoodDiary;
        _diary = consent.shareMoodDiary;
        _goals = true;
        _record = consent.shareScreenings;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Gagal memuat consent: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Manage Data — ${widget.professionalName}',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text('Sharing: pilih kategori yang boleh dibaca profesional.'),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            _Toggle(
                label: 'Mood',
                value: _mood,
                onChanged: (v) => setState(() => _mood = v)),
            _Toggle(
                label: 'Diary',
                value: _diary,
                onChanged: (v) => setState(() => _diary = v)),
            _Toggle(
                label: 'Goals',
                value: _goals,
                onChanged: (v) => setState(() => _goals = v)),
            _Toggle(
                label: 'Record',
                value: _record,
                onChanged: (v) => setState(() => _record = v)),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      color: MalvaColors.danger, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: Text(_isSaving ? 'Menyimpan...' : 'Simpan'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final apiClient = ref.read(apiClientProvider);
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await apiClient.updatePrivacyConsent(
        accessToken: token,
        professionalId: widget.professionalId,
        shareScreenings: _record,
        shareMoodDiary: _mood || _diary,
        shareMedications: true,
        shareTimeline: true,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengaturan sharing tersimpan.')),
      );
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      activeThumbColor: MalvaColors.seed,
      contentPadding: EdgeInsets.zero,
    );
  }
}
