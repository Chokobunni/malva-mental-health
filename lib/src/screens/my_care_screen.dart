import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/care_session_refresh.dart';
import '../services/server_clock.dart';
import '../widgets/doctor_review_actions.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../widgets/friendly_error.dart';
import '../widgets/care_reference_widgets.dart';
import '../widgets/care_session_card.dart';
import '../widgets/session_attendance_actions.dart';
import '../professional_role.dart';
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
      .where((session) => const {
            'completed',
            'cancelled_by_patient',
            'cancelled_by_professional',
            'expired_unpaid',
            'no_show',
          }.contains(session.status))
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
                  title: 'Konsultasi Saya',
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
                        ],
                      ],
                    )),
              ],
            ),
          ),
        ));
  }

  List<Widget> _scheduleBody({required bool upcoming}) {
    final base = upcoming ? _upcoming : _past;
    final filtered = upcoming
        ? base
        : base.where((s) => _matchesSessionFilter(s, _filterPast)).toList();
    return [
      if (!upcoming) ...[
        Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                for (final (value, label) in _historyFilters)
                  _careFilterChip(
                    label: Text(base.isEmpty
                        ? label
                        : '$label ${base.where((s) => _matchesSessionFilter(s, value)).length}'),
                    selected: _filterPast == value,
                    onSelected: (_) => setState(() => _filterPast = value),
                  ),
              ],
            ),
          ),
        ),
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
          CareSessionCard(
            key: ValueKey(session.id),
            session: session,
            role: UserRole.patient,
            subtitle: _professionals[session.professionalId] == null
                ? null
                : professionalRoleLabel(_professionals[session.professionalId]!
                    .credential
                    .specialization),
            onChanged: _load,
            onOpenChat: () => _openChat(session),
            accessToken: (widget.session ?? ref.read(currentSessionProvider))
                ?.accessToken,
            apiClient: widget.apiClient,
            onProfile: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => DoctorProfileScreen(
                    doctorUserId: session.professionalId,
                    doctorName: session.professionalName,
                    session: widget.session,
                    apiClient: widget.apiClient,
                  ),
                )),
            onCancel:
                _mayChange(session) ? () => _cancelSession(session) : null,
            onReschedule:
                _mayChange(session) ? () => _reschedule(session) : null,
          ),
          if (session.canJoinNow)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SessionAttendanceActions(
                session: session,
                role: UserRole.patient,
                onChanged: _load,
                accessToken:
                    (widget.session ?? ref.read(currentSessionProvider))
                        ?.accessToken,
                apiClient: widget.apiClient,
              ),
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

  bool _mayChange(BackendCareSession session) {
    final start = session.scheduledDateTime;
    return session.isScheduled &&
        start != null &&
        start.difference(ServerClock.now()) >= const Duration(hours: 24);
  }

  Future<void> _reschedule(BackendCareSession existing) async {
    final token =
        (widget.session ?? ref.read(currentSessionProvider))?.accessToken;
    if (token == null || token.isEmpty) return;
    final api = widget.apiClient ?? ref.read(apiClientProvider);
    if (api == null) return;
    final changed = await reschedulePatientCareSession(
      context,
      api: api,
      token: token,
      session: existing,
      expiresAt: existing.packageId == null
          ? null
          : _packageForProfessional(existing.professionalId)?.expiresDateTime,
    );
    if (mounted && changed) await _load();
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

Widget _careFilterChip(
        {required Widget label,
        required bool selected,
        required ValueChanged<bool> onSelected}) =>
    ChoiceChip(
      label: label,
      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
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
  });

  final BackendCarePackage package;
  final VoidCallback onOpen;

  /// Catatan kecil di bawah kartu (dipakai kartu gabungan).

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

Future<bool> reschedulePatientCareSession(
  BuildContext context, {
  required MalvaApiClient api,
  required String token,
  required BackendCareSession session,
  DateTime? expiresAt,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  var stillCurrent = true;
  final subscription = container.listen<String?>(
    currentSessionProvider.select((value) => value?.accessToken),
    (_, next) {
      if (next != token) stillCurrent = false;
    },
  );
  try {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => CareSessionSchedulerSheet(
        apiClient: api,
        accessToken: token,
        professionalId: session.professionalId,
        expiresAt: expiresAt,
        initialType: session.sessionType,
        serviceCategory: session.packageId != null
            ? 'package'
            : session.isVideo
                ? 'quick_video'
                : 'quick_chat',
      ),
    );
    if (!context.mounted || !stillCurrent || selected == null) return false;
    final updated = await api.rescheduleCareSession(
      accessToken: token,
      sessionId: session.id,
      scheduledAt: selected.split('|').first,
    );
    if (!context.mounted || !stillCurrent) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
      updated.warnings.isEmpty
          ? 'Sesi berhasil dijadwalkan ulang.'
          : updated.warnings.join(' '),
    )));
    return true;
  } on Object catch (error) {
    if (context.mounted && stillCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
    return false;
  } finally {
    subscription.close();
  }
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
        ? ('Paket aktif', const Color(0xff117a64))
        : (
            switch (package.status) {
              'expired' || 'active' => 'Expired',
              'completed' => 'Selesai',
              'cancelled' => 'Dibatalkan',
              _ => 'Tidak aktif',
            },
            Colors.black54,
          );
    final reviews = doctor?.reviews;
    final specialization = doctor?.credential.specialization;
    final name = link.professionalDisplayName.trim();
    final progress = package.totalSessions <= 0
        ? 0.0
        : (remaining / package.totalSessions).clamp(0.0, 1.0);

    Widget action(IconData icon, String text, VoidCallback callback,
        {bool emphasized = false}) {
      return OutlinedButton.icon(
        onPressed: callback,
        style: OutlinedButton.styleFrom(
          backgroundColor: emphasized ? const Color(0xfff3e8fa) : Colors.white,
          side: careCardBorder,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        icon: Icon(icon, size: 16),
        label: Text(text, textAlign: TextAlign.center),
      );
    }

    return SoftCard(
      color: Colors.white,
      outline: careCardBorder,
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ProAvatar(
            professionalId: link.professionalUserId,
            displayName: name,
            photoUrl: link.professionalPhotoUrl,
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isEmpty ? 'Profesional' : name,
                  style: const TextStyle(
                      color: MalvaColors.plum,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
              if (specialization != null && specialization.isNotEmpty)
                Text(professionalRoleLabel(specialization),
                    style: const TextStyle(
                        color: Color(0xff596776), fontSize: 12)),
              const SizedBox(height: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xfff8f2fa),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded,
                      color: MalvaColors.amber, size: 15),
                  const SizedBox(width: 4),
                  Flexible(
                      child: Text(
                    reviews == null
                        ? 'Ulasan belum dapat dimuat'
                        : reviews.reviewCount > 0
                            ? '${reviews.averageStars.toStringAsFixed(1)} (${reviews.reviewCount} ulasan)'
                            : 'Belum ada ulasan',
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xff535964)),
                  )),
                ]),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          _careBadge('• $label', color),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: InkWell(
            onTap: onPackage,
            borderRadius: BorderRadius.circular(15),
            child: SoftCard(
              outline: careCardBorder,
              radius: 15,
              padding: const EdgeInsets.all(12),
              color: const Color(0xfff8f2fa),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                              '$remaining/${package.totalSessions} sesi tersisa',
                              style: const TextStyle(
                                  color: MalvaColors.plum,
                                  fontWeight: FontWeight.w800)),
                          if (expires != null)
                            Text(
                                '${active ? 'Hingga' : 'Berakhir'} ${expires.day}/${expires.month}/${expires.year}',
                                style: const TextStyle(
                                    color: Color(0xff596776), fontSize: 12)),
                        ]),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress,
                      borderRadius: BorderRadius.circular(10),
                      minHeight: 8,
                      color: MalvaColors.orchid,
                      backgroundColor: const Color(0xffead8f1),
                    ),
                  ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          if (active) ...[
            Expanded(
                child: action(Icons.chat_bubble_outline, 'Chat', onChat,
                    emphasized: true)),
            const SizedBox(width: 6),
          ],
          Expanded(child: action(Icons.person_outline, 'Profil', onProfile)),
          if (active) ...[
            const SizedBox(width: 6),
            Expanded(child: action(Icons.tune_rounded, 'Atur Data', onManage)),
          ],
        ]),
        if (active) ...[
          const SizedBox(height: 7),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: onSchedule == null
                  ? null
                  : const LinearGradient(
                      colors: [MalvaColors.plum, MalvaColors.orchid],
                    ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: FilledButton.icon(
              onPressed: onSchedule,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                minimumSize: const Size(0, 46),
              ),
              icon: const Icon(Icons.edit_calendar_rounded, size: 19),
              label: const Text('Jadwalkan Sesi'),
            ),
          ),
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
                label: 'Asesmen (PHQ-9/GAD-7)',
                value: _screenings,
                onChanged: (v) => setState(() => _screenings = v)),
            _Toggle(
                label: 'Mood & Jurnal',
                value: _moodDiary,
                onChanged: (v) => setState(() => _moodDiary = v)),
            _Toggle(
                label: 'Obat (Obat)',
                value: _medications,
                onChanged: (v) => setState(() => _medications = v)),
            _Toggle(
                label: 'Target & Kebiasaan',
                value: _goals,
                onChanged: (v) => setState(() => _goals = v)),
            _Toggle(
                label: 'Rekam Medis',
                value: _healthRecord,
                onChanged: (v) => setState(() => _healthRecord = v)),
            _Toggle(
                label: 'Riwayat Terapi (Psikologis)',
                description:
                    'Profesional dapat melihat lembar kerja terapi CBT/DBT yang kamu isi '
                    '(ABCDE, Jebakan Pikiran, TIPP, dll).',
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
