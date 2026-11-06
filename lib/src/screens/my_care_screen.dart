import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/care_session_refresh.dart';
import '../services/server_clock.dart';
import '../widgets/session_attendance_actions.dart';
import '../services/malva_api_client.dart';
import '../services/meeting_launcher.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/professional_avatar.dart';
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

class _MyCareScreenState extends ConsumerState<MyCareScreen>
    with WidgetsBindingObserver {
  String _tab = 'Paket';

  /// Filter status daftar sesi, DIPISAH per tab supaya pilihan di satu tab
  /// tidak bocor ke tab lain (dan tidak memicu empty state yang salah).
  /// Default "semua".
  String _filterUpcoming = 'semua';
  String _filterPast = 'semua';
  String _filterPackage = 'semua';
  bool _loadInProgress = false;
  List<BackendCarePackage> _packages = const [];
  List<BackendCareSession> _sessions = const [];
  List<BackendPatientProfessionalLink> _links = const [];
  bool _isLoading = true;
  late final CareSessionRefresh _sessionRefresh;
  String? _error;

  static const _tabs = ['Paket', 'Jadwal', 'Riwayat', 'Professionals'];

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
      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<BackendCarePackage>;
        _sessions = results[1] as List<BackendCareSession>;
        _links = results[2] as List<BackendPatientProfessionalLink>;
        _isLoading = false;
      });
      _sessionRefresh.update(_sessions);
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
      .where((s) => s.isScheduled && !s.isAfterJoinWindow)
      .toList(growable: false)
    ..sort((a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));

  List<BackendCareSession> get _past => _sessions
      .where((s) => !s.isScheduled || s.isAfterJoinWindow)
      .toList(growable: false)
    ..sort((a, b) => (b.scheduledAt ?? '').compareTo(a.scheduledAt ?? ''));

  // ============================================================
  // FILTER STATUS SESI
  //
  // Filter dijalankan di KLIEN atas data yang sudah dimuat (tidak menambah
  // round-trip). Hanya berlaku untuk daftar SESI — kartu paket di tab "Paket"
  // tidak difilter. Nilai status mengikuti CHECK constraint
  // `care_sessions_status_check` di DB.
  //
  // PENTING: state filter DIPISAH per tab (Jadwal vs Riwayat) dan himpunan
  // chip-nya juga per tab. Satu state bersama membuat chip yang mustahil
  // terisi (mis. "Selesai" di tab Jadwal) tampil sebagai 0, dan pilihan
  // "Dibatalkan" di Riwayat bisa membawa empty state yang salah ke tab
  // Jadwal — tab itu memang tidak pernah memuat sesi batal.
  // ============================================================

  /// Status DB yang termasuk tiap filter. `semua` tidak ada di map = cocok
  /// dengan apa pun.
  static const _statusByFilter = <String, Set<String>>{
    'aktif': {'scheduled', 'pending_payment'},
    'selesai': {'completed'},
    'dibatalkan': {
      'cancelled_by_patient',
      'cancelled_by_professional',
      'expired_unpaid',
    },
    'tidak_hadir': {'no_show'},
  };

  bool _matchesSessionFilter(BackendCareSession s, String filter) {
    final statuses = _statusByFilter[filter];
    if (statuses == null) return true;
    return statuses.contains(s.status);
  }

  String _filterFor({required bool upcoming}) =>
      upcoming ? _filterUpcoming : _filterPast;

  void _setFilter({required bool upcoming, required String value}) {
    setState(() {
      if (upcoming) {
        _filterUpcoming = value;
      } else {
        _filterPast = value;
      }
    });
  }

  /// Chip yang relevan untuk satu tab, diturunkan dari isi tab itu:
  ///   - `_upcoming` hanya memuat status `scheduled` -> cukup "Semua"+"Aktif";
  ///   - `_past` memuat completed/no_show/cancelled/expired DAN
  ///     `pending_payment` (sesi itu belum `scheduled`, jadi tidak masuk
  ///     `_upcoming`). Karena itu "Aktif" hanya ditambahkan di tab Riwayat
  ///     bila memang ada sesi seperti itu — tanpa itu, sesi `pending_payment`
  ///     hanya terlihat di "Semua" dan tidak bisa difilter.
  List<(String, String)> _filtersFor(
      {required bool upcoming, required List<BackendCareSession> base}) {
    if (upcoming) {
      return const [('semua', 'Semua'), ('aktif', 'Aktif')];
    }
    return [
      ('semua', 'Semua'),
      if (base.any((s) => _matchesSessionFilter(s, 'aktif')))
        ('aktif', 'Aktif'),
      ('selesai', 'Selesai'),
      ('dibatalkan', 'Dibatalkan'),
      ('tidak_hadir', 'Tidak hadir'),
    ];
  }

  List<BackendPatientProfessionalLink> get _activeLinks =>
      _links.where((l) => l.status == 'active').toList();

  @override
  Widget build(BuildContext context) {
    // Profesional mengubah foto/video intro → muat ulang data secara senyap.
    ref.listen<int>(professionalProfileRevisionProvider, (previous, next) {
      if (previous != next) {
        unawaited(_load(silent: true));
      }
    });
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
    final filter = _filterFor(upcoming: upcoming);
    final filtered = base
        .where((s) => _matchesSessionFilter(s, filter))
        .toList(growable: false);
    return [
      _sessionFilterChips(upcoming: upcoming, base: base),
      const SizedBox(height: 12),
      if (filtered.isEmpty)
        _sessionEmptyState(upcoming: upcoming)
      else
        for (final s in filtered) ...[
          _SessionCard(
            session: s,
            onChanged: _load,
            onOpenChat: () => _openChat(s),
            onJoin: () => _joinSession(s),
            onManage: () => _openPackageFor(s),
          ),
          const SizedBox(height: 10),
        ],
    ];
  }

  /// Baris chip filter status untuk daftar sesi (bisa digeser horizontal).
  /// Jumlah sesi per filter ditampilkan agar pasien tahu isinya tanpa harus
  /// menekan chip satu per satu.
  Widget _sessionFilterChips(
      {required bool upcoming, required List<BackendCareSession> base}) {
    final current = _filterFor(upcoming: upcoming);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label)
              in _filtersFor(upcoming: upcoming, base: base))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  _filterLabel(value, label, base),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                selected: current == value,
                onSelected: (_) => _setFilter(upcoming: upcoming, value: value),
              ),
            ),
        ],
      ),
    );
  }

  String _filterLabel(
      String value, String label, List<BackendCareSession> base) {
    final count = base.where((s) => _matchesSessionFilter(s, value)).length;
    return count == 0 ? label : '$label $count';
  }

  /// Empty state SPESIFIK per filter: daftar kosong tidak boleh tampil tanpa
  /// penjelasan (pasien perlu tahu bahwa tidak ada sesi pada kategori itu,
  /// bukan datanya gagal dimuat).
  Widget _sessionEmptyState({required bool upcoming}) {
    final filter = _filterFor(upcoming: upcoming);
    final (IconData icon, String title, String subtitle) = switch (filter) {
      'aktif' => (
          Icons.event_available_outlined,
          'Tidak ada sesi aktif',
          'Sesi terjadwal atau yang menunggu pembayaran akan muncul di sini.',
        ),
      'selesai' => (
          Icons.check_circle_outline_rounded,
          'Belum ada sesi selesai',
          'Sesi yang sudah selesai akan tercatat di sini.',
        ),
      'dibatalkan' => (
          Icons.cancel_outlined,
          'Belum ada sesi yang dibatalkan',
          'Sesi yang dibatalkan pasien/profesional atau kedaluwarsa karena '
              'tidak dibayar akan muncul di sini.',
        ),
      'tidak_hadir' => (
          Icons.person_off_outlined,
          'Belum ada sesi tidak hadir',
          'Sesi yang ditandai tidak hadir akan muncul di sini.',
        ),
      _ => upcoming
          ? (
              Icons.event_available_outlined,
              'Tidak ada sesi mendatang',
              'Jadwalkan sesi dari paketmu.',
            )
          : (
              Icons.history_rounded,
              'Belum ada riwayat sesi',
              'Sesi yang selesai akan tercatat di sini.',
            ),
    };
    return EmptyState(icon: icon, title: title, subtitle: subtitle);
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
      if (p.professionalId != professionalId) continue;
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
      bordered: true,
      onTap: onOpen,
      color: MalvaColors.mint.withValues(alpha: 0.08),
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
    this.onOpenChat,
    this.onJoin,
    this.onManage,
  });

  final BackendCareSession session;
  final Future<void> Function() onChanged;
  final VoidCallback? onOpenChat;
  final VoidCallback? onJoin;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final at = session.scheduledDateTime;
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
        session.isAfterJoinWindow ? 'Waktu sesi berakhir' : 'Terjadwal',
      'completed' => 'Selesai',
      'no_show' => 'Tidak hadir',
      'cancelled_by_professional' => 'Dibatalkan profesional',
      'cancelled_by_patient' => 'Dibatalkan',
      'expired_unpaid' => 'Pembayaran kedaluwarsa',
      'pending_payment' => 'Menunggu pembayaran',
      _ => session.status,
    };
    // Aksi sesi hanya tersedia selama sesi scheduled berada dalam jendela.
    final live = session.canJoinNow;
    return SoftCard(
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Foto profesional di sebelah kiri agar pasien mengenali wajah.
              _ProAvatar(
                professionalId: session.professionalId,
                displayName: session.professionalName,
                photoUrl: session.photoIntroUrl.isNotEmpty
                    ? session.photoIntroUrl
                    : null,
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
                      dateLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(label: statusLabel, color: statusColor),
                Text(
                    '${session.isVideo ? 'Video' : 'Chat'} • ${session.durationMinutes} mnt • ${session.packageId == null ? 'Sekali sesi' : 'Paket'}',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
          if (session.isScheduled && session.isBeforeJoinWindow) ...[
            const SizedBox(height: 8),
            const Text('Check-in dibuka 10 menit sebelum sesi.'),
          ],
          if (session.summaryForPatient.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Ringkasan: ${session.summaryForPatient}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (session.cancelledByProfessional ||
              session.status == 'no_show') ...[
            const SizedBox(height: 6),
            Text(
              session.cancelledByProfessional
                  ? 'Kuota sesi dikembalikan.'
                  : 'Kuota sesi terpakai.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          if (session.cancelReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Alasan: ${session.cancelReason}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (live) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  // Sesi video tanpa link: tampilkan "Menunggu link video",
                  // BUKAN tombol "Join" yang membuka URL kosong. Link dibuat
                  // profesional (kondisi akun Google-nya tidak bisa
                  // diperbaiki pasien).
                  child: session.isVideo && session.meetingUrl.trim().isEmpty
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon:
                              const Icon(Icons.hourglass_top_rounded, size: 16),
                          label: const Text('Menunggu link video'),
                        )
                      : FilledButton.icon(
                          onPressed: onJoin,
                          style: compactFilledButtonStyle,
                          icon: Icon(
                              session.isVideo
                                  ? Icons.videocam_rounded
                                  : Icons.chat_bubble_rounded,
                              size: 16),
                          label: Text(session.isVideo ? 'Gabung' : 'Join'),
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
              ],
            ),
          ],
          if (session.isScheduled &&
              onManage != null &&
              session.packageId != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Kelola paket')),
          ],
          const SizedBox(height: 10),
          SessionAttendanceActions(
              session: session, role: UserRole.patient, onChanged: onChanged),
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
      bordered: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Foto profesional (photo_intro_url dari server) bila tersedia;
              // fallback gradien + inisial bila kosong. Sebelumnya kartu ini
              // memakai ikon orang statis sehingga foto profesional tidak
              // pernah tampil walau datanya sudah dikirim backend.
              _ProAvatar(
                professionalId: link.professionalUserId,
                displayName: link.professionalDisplayName,
                photoUrl: link.professionalPhotoUrl.isNotEmpty
                    ? link.professionalPhotoUrl
                    : null,
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
      photoUrl: photoUrl,
    );
  }
}
