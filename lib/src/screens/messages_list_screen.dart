import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/realtime_service.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/care_reference_widgets.dart';
import '../widgets/malva_components.dart';
import '../widgets/professional_avatar.dart';
import '../widgets/account_avatar.dart';
import 'booking/doctor_discovery_screen.dart';
import 'chat_screen.dart';
import 'notifications_screen.dart';
import 'settings_screens.dart';

// ============================================================
// MESSAGES — daftar percakapan (satu entry per profesional tertaut)
// ============================================================

class MessagesListScreen extends ConsumerStatefulWidget {
  const MessagesListScreen({
    super.key,
    this.session,
    this.apiClient,
    this.showProfessionalHeader = true,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final bool showProfessionalHeader;

  @override
  ConsumerState<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends ConsumerState<MessagesListScreen>
    with WidgetsBindingObserver {
  List<BackendPatientProfessionalLink> _links = const [];
  bool _isLoading = true;
  String? _error;
  int _request = 0;
  Timer? _refreshTimer;
  RealtimeService? _presenceService;
  StreamSubscription<RealtimeEvent>? _presenceSub;
  StreamSubscription<bool>? _connectionSub;
  int _presenceGeneration = 0;
  final _onlinePeers = <String, bool>{};
  final _patientAvatars = <String, String?>{};
  AuthSession? get _session =>
      widget.session ?? ref.read(currentSessionProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _connectPresence();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _disconnectPresence();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _connectPresence();
      unawaited(_load(silent: true));
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(
          const Duration(seconds: 30), (_) => _load(silent: true));
    } else {
      _refreshTimer?.cancel();
      _disconnectPresence();
      setState(_onlinePeers.clear);
    }
  }

  void _disconnectPresence() {
    _presenceGeneration++;
    unawaited(_presenceSub?.cancel());
    unawaited(_connectionSub?.cancel());
    unawaited(_presenceService?.dispose());
    _presenceService = null;
    _presenceSub = null;
    _connectionSub = null;
  }

  void _connectPresence() {
    _disconnectPresence();
    _onlinePeers.clear();
    final auth = _session;
    final token = auth?.accessToken;
    if (auth?.role != UserRole.professional ||
        token == null ||
        token.isEmpty ||
        WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed)
      return;
    final generation = _presenceGeneration;
    final MalvaApiClient api = widget.apiClient ?? ref.read(apiClientProvider);
    final service =
        RealtimeService(accessToken: token, baseUrl: api.baseUri.toString());
    _presenceService = service;
    bool ownsConnection() =>
        mounted &&
        generation == _presenceGeneration &&
        _session?.accessToken == token;
    _presenceSub = service.events.listen((event) {
      if (!ownsConnection() ||
          event.type != 'presence' ||
          event.data['online'] is! bool) return;
      final peer = event.stringValue('user_id');
      if (peer.isEmpty || peer == (auth?.backendUserId ?? auth?.identifier))
        return;
      setState(() => _onlinePeers[peer] = event.data['online'] == true);
    });
    _connectionSub = service.connection.listen((connected) {
      if (ownsConnection() && !connected) setState(_onlinePeers.clear);
    });
    service.connect();
  }

  @override
  void didUpdateWidget(covariant MessagesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.accessToken != widget.session?.accessToken ||
        oldWidget.apiClient != widget.apiClient) {
      _patientAvatars.clear();
      _connectPresence();
      unawaited(_load());
    }
  }

  Future<void> _load({bool silent = false}) async {
    final request = ++_request;
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final auth = _session;
    final rawToken = auth?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    if (accessToken == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Mode offline aktif. '
              'Hubungkan ke server untuk melihat percakapan.';
        });
      }
      return;
    }
    if (!silent)
      setState(() {
        _isLoading = true;
        _error = null;
      });
    try {
      final links = await apiClient.listPatientProfessionalLinks(
          accessToken: accessToken);
      if (!mounted ||
          request != _request ||
          _session?.accessToken != accessToken) return;
      setState(() {
        _links = links;
        _error = null;
        _isLoading = false;
      });
      if (auth?.role == UserRole.professional) {
        await Future.wait(links.map((link) async {
          try {
            final avatar = await apiClient.fetchPatientAvatar(
                accessToken: accessToken, patientId: link.patientId);
            if (mounted &&
                request == _request &&
                _session?.accessToken == accessToken) {
              setState(() => _patientAvatars[link.patientId] = avatar);
            }
          } on Object {
            // Private avatar failures preserve the existing identity fallback.
          }
        }));
      }
    } on Object catch (e) {
      if (!mounted ||
          request != _request ||
          _session?.accessToken != accessToken) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Identitas profesional (nama/foto) bisa berubah lewat event realtime
    // `professional.profile.updated` — segarkan daftar percakapan agar tidak
    // menampilkan nama lama.
    ref.listen<int>(professionalProfileRevisionProvider, (previous, next) {
      _load();
    });
    ref.listen<AuthSession?>(currentSessionProvider, (previous, next) {
      if (widget.session == null &&
          previous?.accessToken != next?.accessToken) {
        _links = const [];
        _patientAvatars.clear();
        _connectPresence();
        unawaited(_load());
      }
    });
    final isPro = _session?.role == UserRole.professional;
    final embeddedProfessional = isPro && Scaffold.maybeOf(context) != null;
    final recent = _links.where((link) => link.status == 'active');
    final history = _links.where((link) => link.status != 'active');
    const proTitle = 'Percakapan';
    const proSubtitle = 'Lihat pesan dan riwayat chat dengan pasien.';
    return Scaffold(
      backgroundColor: carePageColor,
      appBar: isPro && !embeddedProfessional
          ? AppBar(
              toolbarHeight: 72,
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(proTitle),
                  Text(proSubtitle, style: TextStyle(fontSize: 12)),
                ],
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!isPro)
              CarePageHeader(
                title: 'Percakapan',
                subtitle: 'Lihat percakapan aktif dan riwayat chat.',
                session: _session,
                onNotifications: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => NotificationsScreen(
                            session: _session, apiClient: widget.apiClient))),
                onProfile: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen())),
              ),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isPro) const SectionLabel('Terbaru'),
                      if (embeddedProfessional &&
                          widget.showProfessionalHeader) ...[
                        Text(proTitle,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const Text(proSubtitle),
                        const SizedBox(height: 12),
                      ],
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
                      else if (_links.isEmpty && !isPro)
                        CareIllustratedCard(
                          asset: 'assets/reference/messages-empty.png',
                          title: 'Belum ada percakapan',
                          subtitle:
                              'Hubungkan akun dengan profesional untuk mulai chat.',
                          action: Align(
                            child: SizedBox(
                              width: 224,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xff681477),
                                  minimumSize: const Size(0, 44),
                                ),
                                iconAlignment: IconAlignment.end,
                                icon: const Icon(Icons.arrow_forward_rounded),
                                label: const Text('Cari profesional'),
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DoctorDiscoveryScreen(
                                        session: _session,
                                        apiClient: widget.apiClient,
                                      ),
                                    )),
                              ),
                            ),
                          ),
                        )
                      else if (_links.isEmpty)
                        const EmptyState(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'Belum ada percakapan',
                          subtitle:
                              'Hubungkan akun dengan profesional untuk mulai chat.',
                        )
                      else
                        for (final (heading, group) in [
                          (isPro ? 'Terbaru' : '', recent),
                          ('Riwayat', history)
                        ]) ...[
                          if (heading.isNotEmpty && group.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SectionLabel(heading),
                          ],
                          for (final link in group) ...[
                            _ConversationCard(
                              name: isPro
                                  ? (link.patientDisplayName.isEmpty
                                      ? 'Pasien'
                                      : link.patientDisplayName)
                                  : (link.professionalDisplayName.isEmpty
                                      ? 'Profesional'
                                      : link.professionalDisplayName),
                              photoUrl: isPro ? '' : link.professionalPhotoUrl,
                              patientAvatar: _patientAvatars[link.patientId],
                              isPatient: isPro,
                              online: _onlinePeers[isPro
                                      ? link.patientId
                                      : link.professionalUserId] ==
                                  true,
                              status: link.status,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      otherUserName: isPro
                                          ? link.patientDisplayName
                                          : link.professionalDisplayName,
                                      otherUserId: isPro
                                          ? link.patientId
                                          : link.professionalUserId,
                                      otherUserPhotoUrl: isPro
                                          ? ''
                                          : link.professionalPhotoUrl,
                                      otherUserAvatar: isPro
                                          ? _patientAvatars[link.patientId]
                                          : null,
                                    ),
                                  ),
                                ).then((_) {
                                  if (mounted) unawaited(_load(silent: true));
                                });
                              },
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                    ])),
          ],
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.name,
    required this.status,
    required this.onTap,
    this.photoUrl = '',
    this.patientAvatar,
    this.isPatient = false,
    this.online = false,
  });

  final String name;
  final String status;
  final VoidCallback onTap;

  /// URL foto profesional; kosong = gradien + inisial.
  final String photoUrl;
  final String? patientAvatar;
  final bool isPatient;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      color: Colors.white,
      radius: 18,
      bordered: false,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Stack(
            children: [
              // Only authenticated profile data replaces the identity fallback.
              if (isPatient)
                PatientAvatar(
                    displayName: name, avatar: patientAvatar, radius: 26)
              else
                ProfessionalAvatar(
                  displayName: name,
                  photoUrl: photoUrl,
                  radius: 26,
                ),
              if (online)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    key: ValueKey('online-$name'),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MalvaColors.mint,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    StatusPill(
                      label: status == 'active' ? 'Terhubung' : 'Expired',
                      color: status == 'active'
                          ? MalvaColors.mint
                          : Colors.black54,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
