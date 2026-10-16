import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import 'care_package_screen.dart';
import 'chat_screen.dart';

// ============================================================
// MY CARE — paket sesi + jadwal sesi + profesional (sharing)
// ============================================================

class MyCareScreen extends ConsumerStatefulWidget {
  const MyCareScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<MyCareScreen> createState() => _MyCareScreenState();
}

class _MyCareScreenState extends ConsumerState<MyCareScreen> {
  String _tab = 'Paket';
  List<BackendCarePackage> _packages = const [];
  List<BackendCareSession> _sessions = const [];
  List<BackendPatientProfessionalLink> _links = const [];
  bool _isLoading = true;
  String? _error;

  static const _tabs = ['Paket', 'Jadwal', 'Riwayat', 'Professionals'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final rawToken = widget.session?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    if (accessToken == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Mode offline aktif. '
              'Hubungkan ke server untuk melihat paket dan jadwal Anda.';
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
        apiClient.listCarePackages(accessToken: accessToken),
        apiClient.listCareSessions(accessToken: accessToken, scope: 'all'),
        apiClient.listPatientProfessionalLinks(accessToken: accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<BackendCarePackage>;
        _sessions = results[1] as List<BackendCareSession>;
        _links = results[2] as List<BackendPatientProfessionalLink>;
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

  List<BackendCareSession> get _upcoming =>
      _sessions.where((s) => s.isScheduled).toList(growable: false)
        ..sort((a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));

  List<BackendCareSession> get _past =>
      _sessions.where((s) => !s.isScheduled).toList(growable: false)
        ..sort((a, b) => (b.scheduledAt ?? '').compareTo(a.scheduledAt ?? ''));

  List<BackendPatientProfessionalLink> get _activeLinks =>
      _links.where((l) => l.status == 'active').toList();

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
            else if (_tab == 'Paket')
              ..._packagesBody()
            else if (_tab == 'Jadwal')
              ..._scheduleBody(upcoming: true)
            else
              ..._scheduleBody(upcoming: false),
          ],
        ),
      ),
    );
  }

  List<Widget> _packagesBody() {
    if (_packages.isEmpty) {
      return [
        const EmptyState(
          icon: Icons.card_membership_outlined,
          title: 'Belum ada paket',
          subtitle:
              'Beli paket 4 sesi / 6 minggu dari profil profesional untuk mulai.',
        ),
      ];
    }
    return [
      for (final p in _packages) ...[
        _PackageCard(
          package: p,
          onOpen: () => _openPackage(p),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _scheduleBody({required bool upcoming}) {
    final list = upcoming ? _upcoming : _past;
    if (list.isEmpty) {
      return [
        EmptyState(
          icon:
              upcoming ? Icons.event_available_outlined : Icons.history_rounded,
          title:
              upcoming ? 'Tidak ada sesi mendatang' : 'Belum ada riwayat sesi',
          subtitle: upcoming
              ? 'Jadwalkan sesi dari paketmu.'
              : 'Sesi yang selesai akan tercatat di sini.',
        ),
      ];
    }
    return [
      for (final s in list) ...[
        _SessionCard(
          session: s,
          onOpenChat: () => _openChat(s),
          onJoin: () => _joinSession(s),
          onManage: () => _openPackageFor(s),
        ),
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
          subtitle: 'Beli paket atau booking sesi untuk mulai.',
        ),
      ];
    }
    return [
      const SectionLabel('Terhubung'),
      for (final link in _activeLinks) ...[
        _ProfessionalLinkCard(
          link: link,
          package: _packageForProfessional(link.professionalUserId),
          onChat: () => _openChatFor(link),
          onManage: () => _openManageData(link),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  /// Paket terbaru (aktif didahulukan) untuk profesional tsb, atau null.
  BackendCarePackage? _packageForProfessional(String professionalId) {
    BackendCarePackage? best;
    for (final p in _packages) {
      if (p.professionalId != professionalId) continue;
      if (best == null) {
        best = p;
        continue;
      }
      if (best.isActive && !p.isActive) continue;
      if (!best.isActive && p.isActive) {
        best = p;
        continue;
      }
      final a = p.createdAt;
      final b = best.createdAt;
      if (a != null && b != null && a.compareTo(b) > 0) best = p;
    }
    return best;
  }

  void _openPackage(BackendCarePackage p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CarePackageScreen(
          package: p,
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    ).then((_) => _load());
  }

  void _openPackageFor(BackendCareSession s) {
    if (s.packageId == null || s.packageId!.isEmpty) return;
    BackendCarePackage? found;
    for (final p in _packages) {
      if (p.id == s.packageId) {
        found = p;
        break;
      }
    }
    if (found != null) _openPackage(found);
  }

  void _openChat(BackendCareSession s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName:
              s.professionalName.isEmpty ? 'Profesional' : s.professionalName,
          otherUserId: s.professionalId,
        ),
      ),
    );
  }

  void _openChatFor(BackendPatientProfessionalLink link) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName: link.professionalDisplayName.isEmpty
              ? 'Profesional'
              : link.professionalDisplayName,
          otherUserId: link.professionalUserId,
        ),
      ),
    );
  }

  Future<void> _joinSession(BackendCareSession s) async {
    if (s.isVideo && s.meetingUrl.trim().isNotEmpty) {
      final uri = Uri.tryParse(s.meetingUrl.trim());
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    _openChat(s);
  }

  void _openManageData(BackendPatientProfessionalLink link) {
    final name = link.professionalDisplayName.isEmpty
        ? 'Profesional'
        : link.professionalDisplayName;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => ManageDataSheet(
        professionalId: link.professionalUserId,
        professionalName: name,
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.onOpen});

  final BackendCarePackage package;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final expires = package.expiresDateTime?.toLocal();
    return SoftCard(
      onTap: onOpen,
      color: MalvaColors.mint.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  package.professionalName.isEmpty
                      ? 'Paket Continuous'
                      : package.professionalName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              StatusPill(
                label: package.status,
                color: package.isActive
                    ? MalvaColors.mint
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ProgressStrip(
            value: package.totalSessions == 0
                ? 0
                : package.usedSessions / package.totalSessions,
            color: MalvaColors.seed,
          ),
          const SizedBox(height: 6),
          Text(
            '${package.remainingSessions}/${package.totalSessions} sesi tersisa'
            '${expires == null ? '' : ' • s/d ${expires.day}/${expires.month}/${expires.year}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          // F-12: ringkasan kredit/refund bila ada dana yang dikembalikan.
          if (package.refundedAmount > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Refund/kredit: ${_rupiah(package.refundedAmount)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: MalvaColors.mint),
            ),
          ],
        ],
      ),
    );
  }
}

/// Format nilai rupiah sederhana (tanpa pemisah ribuan berlebih).
String _rupiah(int value) => 'Rp ${value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    )}';

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    this.onOpenChat,
    this.onJoin,
    this.onManage,
  });

  final BackendCareSession session;
  final VoidCallback? onOpenChat;
  final VoidCallback? onJoin;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final at = session.scheduledDateTime?.toLocal();
    final dateLabel = at == null
        ? '-'
        : '${at.day}/${at.month}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final statusColor = switch (session.status) {
      'scheduled' => MalvaColors.seed,
      'completed' => MalvaColors.mint,
      'no_show' => MalvaColors.danger,
      'cancelled_by_professional' => MalvaColors.amber,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final statusLabel = switch (session.status) {
      'scheduled' =>
        'Terjadwal${session.packageId == null ? ' • sekali sesi' : ''}',
      'completed' => 'Selesai',
      'no_show' => 'Tidak hadir (hangus)',
      'cancelled_by_professional' => 'Dibatalkan profesional (kredit kembali)',
      'cancelled_by_patient' => 'Dibatalkan',
      _ => session.status,
    };
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
                child: Icon(
                    session.isVideo
                        ? Icons.videocam_rounded
                        : Icons.chat_bubble_rounded,
                    color: MalvaColors.seed),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.professionalName.isEmpty
                          ? 'Sesi ${session.isVideo ? 'Video' : 'Chat'}'
                          : session.professionalName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '$dateLabel • ${session.durationMinutes} mnt',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(label: statusLabel, color: statusColor),
            ],
          ),
          if (session.summaryForPatient.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Ringkasan: ${session.summaryForPatient}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          // F-12: tampilkan siapa yang membatalkan sesi (cancelled_by).
          if (session.cancelledBy.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              session.cancelledByProfessional
                  ? 'Dibatalkan oleh profesional — kuota sesi dikembalikan.'
                  : 'Dibatalkan oleh Anda.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          if (session.isScheduled) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onJoin,
                    style: compactFilledButtonStyle,
                    icon: Icon(
                        session.isVideo
                            ? Icons.videocam_rounded
                            : Icons.chat_bubble_rounded,
                        size: 16),
                    label: const Text('Join'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenChat,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Kirim'),
                  ),
                ),
                if (onManage != null && session.packageId != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onManage,
                      child: const Text('Kelola'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfessionalLinkCard extends StatelessWidget {
  const _ProfessionalLinkCard({
    required this.link,
    this.package,
    this.onChat,
    this.onManage,
  });

  final BackendPatientProfessionalLink link;

  /// Paket terbaru pasien dengan profesional ini (null = tanpa paket).
  final BackendCarePackage? package;
  final VoidCallback? onChat;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final pkg = package;
    final pkgLabel = pkg == null
        ? 'Tanpa paket aktif'
        : pkg.isActive
            ? 'Paket aktif: ${pkg.remainingSessions}/${pkg.totalSessions} sesi'
            : 'Paket ${pkg.status}: ${pkg.usedSessions}/${pkg.totalSessions} terpakai';
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: MalvaColors.mint.withValues(alpha: 0.12),
                child:
                    const Icon(Icons.person_rounded, color: MalvaColors.mint),
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
                      pkgLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(
                label:
                    pkg != null && pkg.isActive ? 'Paket aktif' : 'Terhubung',
                color: pkg != null && pkg.isActive
                    ? MalvaColors.mint
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onChat,
                  style: compactFilledButtonStyle,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Kirim'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onManage,
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Sharing'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MANAGE DATA — sharing toggles sesuai kolom consent server
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
  // Default MATI (opt-in eksplisit); nilai riil dimuat dari server.
  bool _screenings = false;
  bool _moodDiary = false;
  bool _medications = false;
  bool _timeline = false;
  bool _healthRecord = false;
  bool _goals = false;
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
          _error = 'Mode offline aktif. '
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
      if (!mounted) return;
      setState(() {
        _screenings = consent.shareScreenings;
        _moodDiary = consent.shareMoodDiary;
        _medications = consent.shareMedications;
        _timeline = consent.shareTimeline;
        _healthRecord = consent.shareHealthRecord;
        _goals = consent.shareGoals;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = friendlyErrorMessage(e);
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
          const Text(
              'Sharing: pilih kategori yang boleh dibaca profesional selama paket aktif.'),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            _Toggle(
                label: 'Assessment (PHQ-9/GAD-7)',
                value: _screenings,
                onChanged: (v) => setState(() => _screenings = v)),
            _Toggle(
                label: 'Mood & Diary',
                value: _moodDiary,
                onChanged: (v) => setState(() => _moodDiary = v)),
            _Toggle(
                label: 'Obat (Medication)',
                value: _medications,
                onChanged: (v) => setState(() => _medications = v)),
            _Toggle(
                label: 'Goals & Habits',
                value: _goals,
                onChanged: (v) => setState(() => _goals = v)),
            _Toggle(
                label: 'Health Record',
                value: _healthRecord,
                onChanged: (v) => setState(() => _healthRecord = v)),
            _Toggle(
                label: 'Timeline',
                value: _timeline,
                onChanged: (v) => setState(() => _timeline = v)),
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
        shareScreenings: _screenings,
        shareMoodDiary: _moodDiary,
        shareMedications: _medications,
        shareTimeline: _timeline,
        shareHealthRecord: _healthRecord,
        shareGoals: _goals,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengaturan sharing tersimpan.')),
      );
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
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
