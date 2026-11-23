import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/care_session_refresh.dart';
import '../services/server_clock.dart';
import '../widgets/session_attendance_actions.dart';
import '../widgets/doctor_review_actions.dart';
import '../services/malva_api_client.dart';
import '../services/meeting_launcher.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../widgets/friendly_error.dart';
import '../widgets/care_reference_widgets.dart';
import '../widgets/malva_components.dart';
import '../widgets/professional_avatar.dart';
import 'care_package_screen.dart';
import 'chat_screen.dart';
import 'notifications_screen.dart';
import 'settings_screens.dart';
import 'schedule_package_sessions_screen.dart';
import 'booking/doctor_profile_screen.dart';

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

class _MyCareScreenState extends ConsumerState<MyCareScreen>
    with WidgetsBindingObserver {
  String _tab = 'Jadwal';
  String _filterLinks = 'aktif';

  String _filterPast = 'selesai';
  String _filterPackage = 'semua';
  bool _loadInProgress = false;
  List<BackendCarePackage> _packages = const [];
  List<BackendCareSession> _sessions = const [];
  List<BackendPatientProfessionalLink> _links = const [];
  Map<String, BackendDoctorProfile> _professionals = const {};
  bool _isLoading = true;
  late final CareSessionRefresh _sessionRefresh;
  String? _error;

  static const _tabs = ['Jadwal', 'Terhubung', 'Riwayat'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionRefresh = CareSessionRefresh(() {
      if (!mounted) return;
      setState(() {});
      unawaited(_load(silent: true));
    });
    _load();
  }

  @override
  void dispose() {
    _sessionRefresh.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      unawaited(_load(silent: true));
    }
  }

  /// Memuat paket, sesi, dan tautan profesional.
  ///
  /// [silent] = true dipakai saat penyegaran otomatis (event realtime) agar
  /// indikator loading tidak berkedip menutupi data yang sudah tampil.
  Future<void> _load({bool silent = false}) async {
    if (_loadInProgress) return;
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
    // Saat penyegaran senyap, biarkan data lama tetap tampil.
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    _loadInProgress = true;
    try {
      final results = await Future.wait([
        apiClient.listCarePackages(accessToken: accessToken),
        apiClient.listCareSessions(accessToken: accessToken, scope: 'all'),
        apiClient.listPatientProfessionalLinks(accessToken: accessToken),
      ]);
      // Fetch exact linked profiles: a bounded directory can omit a linked doctor.
      final professionals = <String, BackendDoctorProfile>{};
      final links = results[2] as List<BackendPatientProfessionalLink>;
      await Future.wait(
          links.map((link) => link.professionalUserId).toSet().map((id) async {
        try {
          professionals[id] = await apiClient.getDoctorProfile(
              accessToken: accessToken, userId: id);
        } catch (_) {
          /* Care remains available; show profile data as unavailable. */
        }
      }));
      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<BackendCarePackage>;
        _sessions = results[1] as List<BackendCareSession>;
        _links = results[2] as List<BackendPatientProfessionalLink>;
        _professionals = professionals;
        _isLoading = false;
      });
      _sessionRefresh.update(_sessions);
      ref.read(reviewEntitlementsRevisionProvider.notifier).state++;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    } finally {
      _loadInProgress = false;
    }
  }

  List<BackendCareSession> get _upcoming => _sessions
      .where((session) =>
          (session.isScheduled && !session.isAfterJoinWindow) ||
          session.status == 'pending_payment')
      .toList()
    ..sort((a, b) => (a.scheduledDateTime?.millisecondsSinceEpoch ?? 0)
        .compareTo(b.scheduledDateTime?.millisecondsSinceEpoch ?? 0));

  List<BackendCareSession> get _past => _sessions
      .where((session) =>
          session.status != 'pending_payment' &&
          (!session.isScheduled || session.isAfterJoinWindow))
      .toList()
    ..sort((a, b) => (b.scheduledDateTime?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.scheduledDateTime?.millisecondsSinceEpoch ?? 0));

  static const _historyFilters = [
    ('selesai', 'Selesai'),
    ('dibatalkan', 'Dibatalkan'),
    ('tidak_hadir', 'Tidak Hadir'),
    ('semua', 'Semua'),
  ];

  bool _matchesSessionFilter(BackendCareSession session, String filter) =>
      switch (filter) {
        'selesai' => session.status == 'completed',
        'dibatalkan' => const {
            'cancelled_by_patient',
            'cancelled_by_professional',
            'expired_unpaid'
          }.contains(session.status),
        'tidak_hadir' => session.status == 'no_show',
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    // Profesional mengubah foto/video intro → muat ulang data secara senyap.
    ref.listen<int>(professionalProfileRevisionProvider, (previous, next) {
      if (previous != next) {
        unawaited(_load(silent: true));
      }
    });
    return Theme(
        data: Theme.of(context).copyWith(
            cardTheme: Theme.of(context).cardTheme.copyWith(
                elevation: .3,
                shadowColor: const Color(0x148E44AD),
                surfaceTintColor: Colors.white)),
        child: Scaffold(
          backgroundColor: carePageColor,
          body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                CarePageHeader(
                  title: 'My Care',
                  subtitle:
                      'Lihat profesional terhubung, jadwal, dan riwayat sesi.',
                  session: widget.session ?? ref.watch(currentSessionProvider),
                  onNotifications: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => NotificationsScreen(
                              session: widget.session,
                              apiClient: widget.apiClient))),
                  onProfile: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen())),
                ),
                Padding(
                    padding: const EdgeInsets.fromLTRB(15, 12, 15, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1E7F8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              for (final tab in _tabs)
                                Expanded(
                                  child: ChoiceChip(
                                    showCheckmark: false,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    selectedColor: Colors.white,
                                    backgroundColor: const Color(0xFFF1E7F8),
                                    color: WidgetStateProperty.resolveWith(
                                        (states) => states
                                                .contains(WidgetState.selected)
                                            ? Colors.white
                                            : const Color(0xFFF1E7F8)),
                                    side: BorderSide.none,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    label: Center(
                                        child: Text(tab,
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                                color: _tab == tab
                                                    ? MalvaColors.seed
                                                    : Colors.black54))),
                                    selected: _tab == tab,
                                    onSelected: (_) =>
                                        setState(() => _tab = tab),
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
                            bordered: true,
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
                        else if (_tab == 'Terhubung')
                          ..._professionalsBody()
                        else if (_tab == 'Jadwal') ...[
                          ..._scheduleBody(upcoming: true),
                          if (_packages
                              .any((p) => p.status == 'pending_payment')) ...[
                            const SizedBox(height: 14),
                            const SectionLabel('Menunggu pembayaran'),
                            for (final package in _packages.where(
                                (p) => p.status == 'pending_payment')) ...[
                              _PackageCard(
                                package: package,
                                onOpen: () => _openPackage(package),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ] else ...[
                          ..._scheduleBody(upcoming: false),
                          if (_packages.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const SectionLabel('Riwayat paket'),
                            ..._packagesBody(),
                          ],
                        ],
                      ],
                    )),
              ],
            ),
          ),
        ));
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
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (status, label) in const [
            ('semua', 'Semua'),
            ('pending_payment', 'Menunggu pembayaran'),
            ('active', 'Aktif'),
            ('cancelled', 'Dibatalkan'),
            ('completed', 'Selesai'),
            ('expired', 'Kedaluwarsa')
          ])
            if (status == 'semua' || _packages.any((p) => p.status == status))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                    label: Text(
                        '$label ${_packages.where((p) => status == 'semua' || p.status == status).length}'),
                    selected: _filterPackage == status,
                    onSelected: (_) => setState(() => _filterPackage = status)),
              ),
        ]),
      ),
      const SizedBox(height: 10),
      if (_packageGroups.isEmpty)
        const EmptyState(
            icon: Icons.card_membership_outlined,
            title: 'Tidak ada paket pada status ini',
            subtitle: 'Pilih status lain untuk melihat paketmu.'),
      for (final group in _packageGroups) ...[
        if (group.merged)
          _MergedPackageCard(
            package: group.display,
            primary: group.primary,
            count: group.count,
            onOpen: () => _openPackage(group.primary),
          )
        else
          _PackageCard(
            package: group.primary,
            onOpen: () => _openPackage(group.primary),
          ),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _scheduleBody({required bool upcoming}) {
    final base = upcoming ? _upcoming : _past;
    final filtered = upcoming
        ? base
        : base.where((s) => _matchesSessionFilter(s, _filterPast)).toList();
    return [
      if (!upcoming) ...[
        _careFilters([
          for (final (value, label) in _historyFilters)
            _careFilterChip(
              label: Text(base.isEmpty
                  ? label
                  : '$label ${base.where((s) => _matchesSessionFilter(s, value)).length}'),
              selected: _filterPast == value,
              onSelected: (_) => setState(() => _filterPast = value),
            ),
        ]),
        const SizedBox(height: 14),
      ],
      _careSectionLabel(
          upcoming ? 'Konsultasi mendatang' : 'Riwayat konsultasi',
          filtered.length,
          'sesi'),
      if (filtered.isEmpty)
        CareIllustratedCard(
          asset: upcoming ? 'care-schedule' : 'care-history',
          title:
              upcoming ? 'Tidak ada sesi mendatang' : 'Belum ada riwayat sesi',
          subtitle: upcoming ? 'Jadwalkan sesi dari paketmu.' : null,
        )
      else
        for (final session in filtered) ...[
          _SessionCard(
            session: session,
            onChanged: _load,
            onOpenChat: () => _openChat(session),
            onJoin: () => _joinSession(session),
            onCancel: () => _cancelSession(session),
            onReschedule: () => _openScheduler(existing: session),
          ),
          const SizedBox(height: 12),
        ],
    ];
  }

  List<Widget> _professionalsBody() {
    final pairs = <String, BackendPatientProfessionalLink>{
      for (final link in _links) link.professionalUserId: link,
    };
    final groups = <String, BackendCarePackage>{};
    for (final package in _packages) {
      if (package.status == 'pending_payment' || package.status == 'merged')
        continue;
      groups.putIfAbsent(package.professionalId,
          () => _packageForProfessional(package.professionalId)!);
      pairs.putIfAbsent(
          package.professionalId,
          () => BackendPatientProfessionalLink(
                patientId: package.patientId,
                professionalUserId: package.professionalId,
                professionalId: '',
                patientDisplayName: package.patientName,
                professionalDisplayName: package.professionalName,
                professionalPhotoUrl: package.photoIntroUrl,
                status: package.status,
              ));
    }
    if (groups.isEmpty) {
      return const [
        CareIllustratedCard(
          asset: 'care-no-package',
          title: 'Belum ada paket',
          subtitle: 'Beli paket dari profil profesional untuk mulai.',
          imageHeight: 146,
        )
      ];
    }
    final active = groups.values.where(_isUsablePackage).toList()
      ..sort((a, b) => (a.expiresDateTime?.millisecondsSinceEpoch ?? 0)
          .compareTo(b.expiresDateTime?.millisecondsSinceEpoch ?? 0));
    final inactive = groups.values
        .where((pkg) => !_isUsablePackage(pkg))
        .toList()
      ..sort((a, b) => (b.expiresDateTime?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.expiresDateTime?.millisecondsSinceEpoch ?? 0));
    final filtered = switch (_filterLinks) {
      'aktif' => active,
      'tidak_aktif' => inactive,
      _ => [...active, ...inactive],
    };
    return [
      _careFilters([
        for (final (value, label) in [
          ('aktif', 'Aktif ${active.length}'),
          ('tidak_aktif', 'Tidak aktif ${inactive.length}'),
          ('semua', 'Semua ${groups.length}'),
        ])
          _careFilterChip(
            label: Text(label),
            selected: _filterLinks == value,
            onSelected: (_) => setState(() => _filterLinks = value),
          ),
      ]),
      const SizedBox(height: 14),
      _careSectionLabel(
          _filterLinks == 'semua'
              ? 'Daftar profesional'
              : 'Profesional terhubung',
          filtered.length,
          'profesional'),
      if (filtered.isEmpty)
        CareIllustratedCard(
          asset:
              _filterLinks == 'aktif' ? 'care-no-active' : 'care-no-inactive',
          title: _filterLinks == 'aktif'
              ? 'Belum ada paket aktif'
              : 'Belum ada paket tidak aktif',
        ),
      for (final package in filtered) ...[
        _ProfessionalLinkCard(
          link: pairs[package.professionalId]!,
          doctor: _professionals[package.professionalId],
          package: package,
          active: _isUsablePackage(package),
          onProfile: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DoctorProfileScreen(
                        doctorUserId: package.professionalId,
                        doctorName: pairs[package.professionalId]!
                            .professionalDisplayName,
                        session: widget.session,
                        apiClient: widget.apiClient,
                      ))),
          onPackage: () => _openPackage(package),
          onChat: () => _openChatFor(pairs[package.professionalId]!),
          onManage: () => _openManageData(pairs[package.professionalId]!),
          onSchedule: package.remainingSessions > 0
              ? () => _openPackageScheduler(package)
              : null,
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  /// Paket dikelompokkan per profesional: pasien yang membeli beberapa paket
  /// dari profesional yang sama melihat SATU kartu gabungan dengan total
  /// pertemuan dijumlahkan (aturan bisnis: kuota digabung). Backend
  /// menjamin satu paket aktif per pasangan lewat merge (`status=merged`,
  /// sudah difilter server); pengelompokan di sini adalah pengaman untuk
  /// data lama/race. Grup non-aktif tetap dirender per paket.
  /// True bila paket boleh dihitung sebagai kuota yang masih SAH.
  ///
  /// `isActive` hanya mengecek `status == 'active'`. Paket yang sudah lewat
  /// `expires_at` tetapi belum disapu sweeper tetap berstatus aktif, sehingga
  /// dulu ikut digabung dan sisa sesi tampak lebih banyak dari yang sah
  /// (aturan bisnis: sisa hangus setelah masa berlaku habis). Karena itu
  /// penggabungan di MyCare juga mensyaratkan belum kedaluwarsa.
  static bool _isUsablePackage(BackendCarePackage p) {
    if (!p.isActive) return false;
    final expires = p.expiresDateTime;
    return expires == null || expires.isAfter(ServerClock.now());
  }

  List<_PackageDisplay> get _packageGroups {
    final order = <String>[];
    final byPro = <String, List<BackendCarePackage>>{};
    for (final p in _packages.where(
        (p) => _filterPackage == 'semua' || p.status == _filterPackage)) {
      if (!byPro.containsKey(p.professionalId)) {
        order.add(p.professionalId);
        byPro[p.professionalId] = [];
      }
      byPro[p.professionalId]!.add(p);
    }
    final out = <_PackageDisplay>[];
    for (final proId in order) {
      final list = byPro[proId]!;
      final active = list.where(_isUsablePackage).toList(growable: false);
      if (active.length > 1) {
        out.add(_PackageDisplay(
            primary: active.reduce(
                (a, b) => b.remainingSessions > a.remainingSessions ? b : a),
            display: _mergedAggregate(active),
            count: active.length));
        for (final p in list.where((p) => !_isUsablePackage(p))) {
          out.add(_PackageDisplay(primary: p, display: p, count: 1));
        }
      } else {
        final sorted = List<BackendCarePackage>.from(list)
          ..sort((a, b) => switch ((_isUsablePackage(a), _isUsablePackage(b))) {
                (true, false) => -1,
                (false, true) => 1,
                _ => (b.createdAt ?? '').compareTo(a.createdAt ?? ''),
              });
        for (final p in sorted) {
          out.add(_PackageDisplay(primary: p, display: p, count: 1));
        }
      }
    }
    return out;
  }

  /// Paket untuk kartu Professionals: seluruh paket AKTIF profesional yang
  /// sama digabung (total/terpakai/sisa), paket non-aktif terbaru sebagai
  /// fallback bila tidak ada yang aktif.
  BackendCarePackage? _packageForProfessional(String professionalId) {
    final active = _packages
        .where((p) => p.professionalId == professionalId && _isUsablePackage(p))
        .toList(growable: false);
    if (active.isNotEmpty) {
      if (active.length == 1) return active.first;
      return _mergedAggregate(active);
    }
    BackendCarePackage? best;
    for (final p in _packages) {
      if (p.professionalId != professionalId ||
          p.status == 'pending_payment' ||
          p.status == 'merged') continue;
      if (best == null) {
        best = p;
        continue;
      }
      final a = p.createdAt;
      final b = best.createdAt;
      if (a != null && b != null && a.compareTo(b) > 0) best = p;
    }
    return best;
  }

  /// Menggabungkan beberapa paket aktif (profesional sama) menjadi satu baris
  /// tampilan: total/terpakai/sisa dijumlahkan, kedaluwarsa ambil yang paling
  /// akhir, harga/refund ikut dijumlahkan.
  static BackendCarePackage _mergedAggregate(List<BackendCarePackage> active) {
    final primary = active
        .reduce((a, b) => b.remainingSessions > a.remainingSessions ? b : a);
    var total = 0;
    var used = 0;
    var remaining = 0;
    var refunded = 0;
    var price = 0;
    DateTime? latest;
    for (final p in active) {
      total += p.totalSessions;
      used += p.usedSessions;
      remaining += p.remainingSessions;
      refunded += p.refundedAmount;
      price += p.price;
      final e = p.expiresDateTime;
      if (e != null && (latest == null || e.isAfter(latest))) latest = e;
    }
    return BackendCarePackage(
      id: primary.id,
      patientId: primary.patientId,
      professionalId: primary.professionalId,
      patientName: primary.patientName,
      professionalName: primary.professionalName,
      totalSessions: total,
      usedSessions: used,
      remainingSessions: remaining,
      refundValue: primary.refundValue,
      refundedAmount: refunded,
      validityDays: primary.validityDays,
      price: price,
      status: 'active',
      startsAt: primary.startsAt,
      expiresAt: latest != null ? wibIso(latest) : primary.expiresAt,
      createdAt: primary.createdAt,
      photoIntroUrl: primary.photoIntroUrl,
    );
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

  Future<void> _openPackageScheduler(BackendCarePackage package) async {
    final session = widget.session ?? ref.read(currentSessionProvider);
    final api = widget.apiClient ?? ref.read(apiClientProvider);
    if (session == null || api == null || !_isUsablePackage(package)) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SchedulePackageSessionsScreen(
          package: package,
          api: api,
          session: session,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openScheduler({
    BackendCarePackage? package,
    BackendCareSession? existing,
  }) async {
    final token =
        (widget.session ?? ref.read(currentSessionProvider))?.accessToken;
    final professionalId = package?.professionalId ?? existing?.professionalId;
    if (token == null || token.isEmpty || professionalId == null) return;
    final api = widget.apiClient ?? ref.read(apiClientProvider);
    if (api == null) return;
    final expires = package?.expiresDateTime ??
        (existing?.packageId == null
            ? null
            : _packageForProfessional(professionalId)?.expiresDateTime);
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: carePageColor,
      builder: (_) => CareSessionSchedulerSheet(
        apiClient: api,
        accessToken: token,
        professionalId: professionalId,
        expiresAt: expires,
        initialType: existing?.sessionType ?? 'video',
        serviceCategory: package != null || existing?.packageId != null
            ? 'package'
            : existing?.sessionType == 'chat'
                ? 'quick_chat'
                : 'quick_video',
      ),
    );
    if (!mounted ||
        selected == null ||
        token !=
            (widget.session ?? ref.read(currentSessionProvider))?.accessToken)
      return;
    try {
      final at = selected.split('|').first;
      final String message;
      if (existing != null) {
        final updated = await api.rescheduleCareSession(
          accessToken: token,
          sessionId: existing.id,
          scheduledAt: at,
        );
        message = updated.warnings.isEmpty
            ? 'Sesi berhasil dijadwalkan ulang.'
            : updated.warnings.join(' ');
      } else {
        final scheduled = await api.scheduleSession(
          accessToken: token,
          packageId: package!.id,
          scheduledAt: at,
          sessionType: 'video',
        );
        message = scheduled.meetPending
            ? 'Sesi berhasil dijadwalkan. Link video dibuat profesional sebelum sesi dimulai.'
            : 'Sesi berhasil dijadwalkan.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }

  Future<void> _cancelSession(BackendCareSession session) async {
    final token =
        (widget.session ?? ref.read(currentSessionProvider))?.accessToken;
    final api = widget.apiClient ?? ref.read(apiClientProvider);
    if (token == null || token.isEmpty || api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan sesi?'),
        content: const Text('Pembatalan minimal 24 jam sebelum sesi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Kembali')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Batalkan')),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        token !=
            (widget.session ?? ref.read(currentSessionProvider))?.accessToken)
      return;
    try {
      await api.updateCareSession(
        accessToken: token,
        sessionId: session.id,
        status: 'cancelled_by_patient',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sesi dibatalkan.')));
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
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
    if (s.isVideo) {
      if (s.meetingUrl.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Link video belum tersedia. Profesional akan membuatnya '
                'sebelum sesi dimulai.',
              ),
            ),
          );
        }
        return;
      }
      if (s.isBeforeJoinWindow) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Belum bisa bergabung — ${s.joinStateLabel}.')),
          );
        }
        return;
      }
      final url = s.meetingUrl.trim();
      final result = await openMeetLink(url);
      if (!mounted) return;
      switch (result) {
        case MeetLaunchResult.openedExternal:
        case MeetLaunchResult.openedInApp:
          return;
        case MeetLaunchResult.invalid:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Link Google Meet tidak valid.')),
          );
          return;
        case MeetLaunchResult.failed:
          // Aplikasi Meet tidak terbuka: salin tautan agar pengguna bisa
          // menempelnya manual di browser.
          await copyMeetLink(url);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Link Google Meet disalin. Tempel di browser bila aplikasi '
                'Meet tidak terbuka.',
              ),
            ),
          );
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

/// Satu baris tampilan paket: paket utama (untuk navigasi) + paket yang
/// ditampilkan (bisa hasil gabungan beberapa paket aktif) + jumlah paket.
class _PackageDisplay {
  const _PackageDisplay({
    required this.primary,
    required this.display,
    required this.count,
  });

  final BackendCarePackage primary;
  final BackendCarePackage display;
  final int count;

  bool get merged => count > 1;
}

Widget _careFilterChip(
        {required Widget label,
        required bool selected,
        required ValueChanged<bool> onSelected}) =>
    ChoiceChip(
      label: label,
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      selectedColor: MalvaColors.seed,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF535964),
          fontWeight: FontWeight.w700,
          fontSize: 12),
      side: BorderSide(
          color: selected ? MalvaColors.seed : const Color(0xFFF0E6F6)),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    );

Widget _careFilters(List<Widget> children) => Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: children,
    );

Widget _careSectionLabel(String text, int count, String unit) => Padding(
      padding: const EdgeInsets.fromLTRB(3, 4, 3, 14),
      child: Row(children: [
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: MalvaColors.seed,
                    fontSize: 16,
                    fontWeight: FontWeight.w800))),
        const SizedBox(width: 8),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xFFF1E7F8),
                borderRadius: BorderRadius.circular(30)),
            child: Text('$count $unit',
                style: const TextStyle(
                    color: MalvaColors.seed,
                    fontSize: 11,
                    fontWeight: FontWeight.w700))),
      ]),
    );

Widget _careBadge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: .16))),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.onOpen,
    this.footerNote,
  });

  final BackendCarePackage package;
  final VoidCallback onOpen;

  /// Catatan kecil di bawah kartu (dipakai kartu gabungan).
  final String? footerNote;

  @override
  Widget build(BuildContext context) {
    final expires = package.expiresDateTime;
    return SoftCard(
      radius: 26,
      onTap: onOpen,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Foto profesional di sebelah kiri agar pasien mengenali wajah.
              _ProAvatar(
                professionalId: package.professionalId,
                displayName: package.professionalName,
                photoUrl: package.photoIntroUrl.isNotEmpty
                    ? package.photoIntroUrl
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  package.professionalName.isEmpty
                      ? 'Paket Continuous'
                      : package.professionalName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              StatusPill(
                label: package.status == 'pending_payment'
                    ? 'Menunggu pembayaran'
                    : package.status,
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
                : (package.remainingSessions / package.totalSessions)
                    .clamp(0.0, 1.0),
            color: MalvaColors.seed,
          ),
          const SizedBox(height: 6),
          Text(
            '${package.remainingSessions}/${package.totalSessions} sesi tersisa'
            '${expires == null ? '' : ' • s/d ${expires.day}/${expires.month}/${expires.year}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (footerNote != null && footerNote!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              footerNote!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
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

/// Kartu paket gabungan: total/terpakai/sisa dijumlahkan dari beberapa paket
/// aktif profesional yang sama. Ketuk membuka paket utama (sisa terbanyak).
class _MergedPackageCard extends StatelessWidget {
  const _MergedPackageCard({
    required this.package,
    required this.primary,
    required this.count,
    required this.onOpen,
  });

  /// Baris agregat (total/terpakai/sisa/expired hasil penjumlahan).
  final BackendCarePackage package;
  final BackendCarePackage primary;

  /// Jumlah paket yang digabung.
  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return _PackageCard(
      package: package,
      onOpen: onOpen,
      footerNote: 'Digabung dari $count paket',
    );
  }
}

/// Expiry agregat dihitung di `_mergedAggregate`; helper ini hanya menegaskan
/// tipe agar tidak ada logika baru tersembunyi di sini.

/// Format nilai rupiah sederhana (tanpa pemisah ribuan berlebih).
String _rupiah(int value) => 'Rp ${value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    )}';

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onChanged,
    required this.onOpenChat,
    required this.onJoin,
    required this.onCancel,
    required this.onReschedule,
  });

  final BackendCareSession session;
  final Future<void> Function() onChanged;
  final VoidCallback onOpenChat, onJoin, onCancel, onReschedule;

  @override
  Widget build(BuildContext context) {
    final at = session.scheduledDateTime;
    const weekdays = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu'
    ];
    final dateLabel = at == null
        ? '-'
        : '${weekdays[at.weekday - 1]}, ${at.day}/${at.month}/${at.year} · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final kind =
        '${session.isVideo ? 'Video' : 'Chat'} · ${session.durationMinutes} mnt · ${session.packageId == null ? 'Sekali sesi' : 'Paket'}';
    final (status, color) = switch (session.status) {
      'scheduled' => (
          session.isAfterJoinWindow ? 'Waktu sesi berakhir' : 'Terjadwal',
          MalvaColors.seed
        ),
      'completed' => ('Selesai', const Color(0xff129471)),
      'no_show' => ('Tidak hadir', MalvaColors.danger),
      'cancelled_by_professional' || 'cancelled_by_patient' => (
          'Dibatalkan',
          Colors.black54
        ),
      'expired_unpaid' => ('Pembayaran kedaluwarsa', Colors.black54),
      'pending_payment' => ('Menunggu pembayaran', MalvaColors.amber),
      _ => (session.status, Colors.black54),
    };
    final live = session.canJoinNow;
    final upcoming = session.isScheduled && !session.isAfterJoinWindow;
    final before = at?.difference(ServerClock.now());
    final minutes = before?.inMinutes ?? 0;
    final remaining = minutes ~/ 60 > 0
        ? '${minutes ~/ 60} jam ${minutes % 60} mnt'
        : '${minutes.clamp(1, 59)} mnt';
    final mayChange = before != null && before >= const Duration(hours: 24);
    return SoftCard(
      color: Colors.white,
      outline: careCardBorder,
      radius: 16,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _ProAvatar(
                professionalId: session.professionalId,
                displayName: session.professionalName,
                photoUrl: session.photoIntroUrl),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: Text(
                            session.professionalName.isEmpty
                                ? 'Profesional'
                                : session.professionalName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 14))),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 108),
                        child: _careBadge(status, color)),
                  ]),
                  const SizedBox(height: 4),
                  if (upcoming)
                    Text(kind)
                  else ...[
                    _detailLine(Icons.calendar_today_outlined, dateLabel),
                    const SizedBox(height: 4),
                    _detailLine(
                        session.isVideo
                            ? Icons.videocam_rounded
                            : Icons.chat_bubble_rounded,
                        kind),
                  ],
                ])),
          ]),
          if (upcoming) ...[
            const SizedBox(height: 12),
            _sessionStrip(Icons.calendar_today_outlined, dateLabel,
                const Color(0xfff6f2f8), MalvaColors.ink),
            if (session.isBeforeJoinWindow) ...[
              const SizedBox(height: 6),
              _sessionStrip(Icons.schedule_rounded, 'Mulai dalam $remaining',
                  const Color(0xfff3e8fa), MalvaColors.seed),
              const SizedBox(height: 6),
              const Text('Check-in dibuka 10 menit sebelum sesi.'),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final primary = FilledButton.icon(
                onPressed: onOpenChat,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                icon: const Icon(Icons.chat_bubble_rounded, size: 14),
                label: const Text('Chat'),
              );
              final secondaryStyle = OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                side: careCardBorder,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              );
              final actions = [
                primary,
                if (live)
                  FilledButton(
                    onPressed:
                        session.isVideo && session.meetingUrl.trim().isEmpty
                            ? null
                            : onJoin,
                    style: compactFilledButtonStyle,
                    child: Text(
                        session.isVideo && session.meetingUrl.trim().isEmpty
                            ? 'Menunggu link video'
                            : 'Gabung'),
                  )
                else ...[
                  OutlinedButton(
                      style: secondaryStyle,
                      onPressed: mayChange ? onReschedule : null,
                      child: const Text('Reschedule')),
                  OutlinedButton(
                    style: secondaryStyle.copyWith(
                        foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? null
                          : const Color(0xffa62c60),
                    )),
                    onPressed: mayChange ? onCancel : null,
                    child: const Text('Batal'),
                  ),
                ],
              ];
              if (live ||
                  constraints.maxWidth < 260 ||
                  MediaQuery.textScalerOf(context).scale(12) > 16) {
                return Wrap(spacing: 7, runSpacing: 4, children: actions);
              }
              return Row(children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  Expanded(child: actions[i]),
                ],
              ]);
            }),
          ],
          if (session.summaryForPatient.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Ringkasan: ${session.summaryForPatient}')),
          if (session.packageId != null &&
              (session.cancelledByProfessional || session.status == 'no_show'))
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(session.cancelledByProfessional
                    ? 'Kuota sesi dikembalikan.'
                    : 'Kuota sesi terpakai.')),
          if (session.cancelReason.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Alasan: ${session.cancelReason}')),
          SessionAttendanceActions(
              session: session, role: UserRole.patient, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _detailLine(IconData icon, String text) => Row(children: [
        Icon(icon, color: MalvaColors.seed, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ]);

  Widget _sessionStrip(IconData icon, String text, Color color, Color ink) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, color: MalvaColors.seed, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: ink, fontSize: 13, fontWeight: FontWeight.w800))),
        ]),
      );
}

class _ProfessionalLinkCard extends StatelessWidget {
  const _ProfessionalLinkCard({
    required this.link,
    required this.package,
    required this.active,
    required this.onProfile,
    required this.onPackage,
    required this.onChat,
    required this.onManage,
    required this.onSchedule,
    this.doctor,
  });

  final BackendPatientProfessionalLink link;
  final BackendCarePackage package;
  final bool active;
  final VoidCallback onProfile, onPackage, onChat, onManage;
  final VoidCallback? onSchedule;
  final BackendDoctorProfile? doctor;

  @override
  Widget build(BuildContext context) {
    final remaining = active ? package.remainingSessions : 0;
    final expires = package.expiresDateTime;
    final (label, color) = active
        ? ('Paket aktif', const Color(0xff129471))
        : (
            switch (package.status) {
              'expired' || 'active' => 'Expired',
              'completed' => 'Selesai',
              'cancelled' => 'Dibatalkan',
              _ => 'Tidak aktif',
            },
            Colors.black54
          );
    final reviews = doctor?.reviews;
    return SoftCard(
      color: Colors.white,
      outline: careCardBorder,
      radius: 17,
      padding: const EdgeInsets.all(13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ProAvatar(
              professionalId: link.professionalUserId,
              displayName: link.professionalDisplayName,
              photoUrl: link.professionalPhotoUrl),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Row(children: [
                  Expanded(
                      child: TextButton(
                    onPressed: onProfile,
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 40),
                    ),
                    child: Text(
                        link.professionalDisplayName.isEmpty
                            ? 'Profesional'
                            : link.professionalDisplayName,
                        style: const TextStyle(
                            color: MalvaColors.plum,
                            fontSize: 14,
                            fontWeight: FontWeight.w900)),
                  )),
                  const SizedBox(width: 5),
                  _careBadge(label, color),
                ]),
                InkWell(
                  onTap: onPackage,
                  borderRadius: BorderRadius.circular(7),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1, bottom: 8),
                    child: Column(children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: Text(
                                    '$remaining/${package.totalSessions} sesi tersisa',
                                    style: const TextStyle(
                                        color: MalvaColors.seed,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11))),
                            if (expires != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                  child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        '${active ? 'Hingga' : 'Berakhir'} ${expires.day}/${expires.month}/${expires.year}',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                            color: active
                                                ? const Color(0xff535964)
                                                : MalvaColors.danger,
                                            fontSize: 11),
                                      ))),
                            ],
                          ]),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: package.totalSessions <= 0
                            ? 0
                            : (remaining / package.totalSessions)
                                .clamp(0.0, 1.0),
                        borderRadius: BorderRadius.circular(8),
                        minHeight: 7,
                        color: MalvaColors.orchid,
                        backgroundColor: const Color(0xfff2e4f8),
                      ),
                    ]),
                  ),
                ),
              ])),
        ]),
        Row(children: [
          const Icon(Icons.star_rounded, color: MalvaColors.amber, size: 18),
          const SizedBox(width: 5),
          Expanded(
              child: Text(
                  reviews == null
                      ? 'Ulasan belum dapat dimuat'
                      : reviews.reviewCount > 0
                          ? '${reviews.averageStars.toStringAsFixed(1)} / 5 (${reviews.reviewCount} ulasan)'
                          : 'Belum ada ulasan',
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xff535964)))),
        ]),
        if (active) ...[
          const SizedBox(height: 7),
          Row(children: [
            Expanded(
                child: FilledButton.icon(
                    onPressed: onChat,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 15),
                    label: const Text('Chat'))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: onManage,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        side: careCardBorder,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9)),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        textStyle: const TextStyle(fontSize: 12)),
                    icon: const Icon(Icons.share_rounded, size: 15),
                    label: const Text('Bagikan data'))),
          ]),
          const SizedBox(height: 3),
          FilledButton.tonalIcon(
              onPressed: onSchedule,
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 33),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                  foregroundColor: MalvaColors.plum,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: const Text('Jadwalkan Sesi')),
        ],
      ]),
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
  // Kategori Therapy Record (worksheet CBT/DBT) — OPT-IN, default MATI.
  bool _therapyRecords = false;
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
        _therapyRecords = consent.shareTherapyRecords;
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
                label: 'Therapy Record (Psikologis)',
                description:
                    'Profesional dapat melihat worksheet terapi CBT/DBT yang kamu isi '
                    '(ABCDE, Thinking Traps, TIPP, dll).',
                value: _therapyRecords,
                onChanged: (v) => setState(() => _therapyRecords = v)),
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
        shareTherapyRecords: _therapyRecords,
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
      {required this.label,
      required this.value,
      required this.onChanged,
      this.description});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Penjelasan singkat di bawah label (dipakai kategori yang butuh konteks).
  final String? description;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: description == null
          ? null
          : Text(description!, style: Theme.of(context).textTheme.bodySmall),
      activeThumbColor: MalvaColors.seed,
      contentPadding: EdgeInsets.zero,
    );
  }
}

/// Avatar profesional untuk kartu MyCare. Menampilkan foto dari URL bila
/// tersedia (dari photo_intro_url di professional_credentials), fallback ke
/// inisial nama. Menggunakan ProfessionalAvatar widget yang sudah mendukung
/// network image dengan error/loading fallback.
class _ProAvatar extends StatelessWidget {
  const _ProAvatar({
    required this.professionalId,
    required this.displayName,
    this.photoUrl,
  });

  final String professionalId;
  final String displayName;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return ProfessionalAvatar(
      displayName: displayName,
      radius: 22,
      borderRadius: BorderRadius.circular(22),
      photoUrl: photoUrl,
    );
  }
}
