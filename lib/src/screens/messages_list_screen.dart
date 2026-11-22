import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/care_reference_widgets.dart';
import '../widgets/malva_components.dart';
import '../widgets/professional_avatar.dart';
import 'chat_screen.dart';
import 'notifications_screen.dart';
import 'settings_screens.dart';

// ============================================================
// MESSAGES — daftar percakapan (satu entry per profesional tertaut)
// ============================================================

class MessagesListScreen extends ConsumerStatefulWidget {
  const MessagesListScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

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
  AuthSession? get _session =>
      widget.session ?? ref.read(currentSessionProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load(silent: true));
  }

  @override
  void didUpdateWidget(covariant MessagesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.accessToken != widget.session?.accessToken ||
        oldWidget.apiClient != widget.apiClient) unawaited(_load());
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
        unawaited(_load());
      }
    });
    final isPro = _session?.role == UserRole.professional;
    final embeddedProfessional = isPro && Scaffold.maybeOf(context) != null;
    final recent = _links.where((link) => link.status == 'active');
    final history = _links.where((link) => link.status != 'active');
    return Scaffold(
      backgroundColor: carePageColor,
      appBar: isPro && !embeddedProfessional
          ? AppBar(title: const Text('Messages'))
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!isPro)
              CarePageHeader(
                title: 'Messages',
                subtitle: 'Lihat percakapan aktif dan riwayat chat.',
                name: _session?.displayName ?? '',
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
                      if (embeddedProfessional) ...[
                        Text('Messages',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                )),
                        const SizedBox(height: 16),
                      ],
                      const SectionLabel('Recent'),
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
                      else if (_links.isEmpty)
                        const EmptyState(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'Belum ada percakapan',
                          subtitle:
                              'Hubungkan akun dengan profesional untuk mulai chat.',
                        )
                      else
                        for (final (heading, group) in [
                          ('', recent),
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
                              // Foto hanya milik profesional; sisi profesional tetap
                              // memakai inisial pasien.
                              photoUrl: isPro ? '' : link.professionalPhotoUrl,
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
  });

  final String name;
  final String status;
  final VoidCallback onTap;

  /// URL foto profesional; kosong = gradien + inisial.
  final String photoUrl;

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
              // Foto profesional (bila ada) menggantikan inisial; fallback
              // gradien + inisial tetap dipakai saat foto kosong/gagal.
              ProfessionalAvatar(
                displayName: name,
                photoUrl: photoUrl,
                radius: 26,
              ),
              if (status == 'active')
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: status == 'active'
                          ? MalvaColors.mint
                          : Colors.black26,
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
