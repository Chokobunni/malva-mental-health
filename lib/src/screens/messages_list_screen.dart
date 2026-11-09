import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/professional_avatar.dart';
import 'chat_screen.dart';

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
      final results = await Future.wait([
        apiClient.listPatientProfessionalLinks(accessToken: accessToken),
        apiClient.listCareSessions(accessToken: accessToken, scope: 'upcoming'),
      ]);
      if (!mounted ||
          request != _request ||
          _session?.accessToken != accessToken) return;
      final links = results[0] as List<BackendPatientProfessionalLink>;
      final sessions = results[1] as List<BackendCareSession>;
      final isPro = auth?.role == UserRole.professional;
      final peers = <String, BackendPatientProfessionalLink>{
        for (final link in links)
          (isPro ? link.patientId : link.professionalUserId): link,
      };
      for (final session in sessions.where((s) => s.status == 'scheduled')) {
        final peer = isPro ? session.patientId : session.professionalId;
        if (peer.isEmpty) continue;
        peers.putIfAbsent(
            peer,
            () => BackendPatientProfessionalLink(
                patientId: session.patientId,
                professionalUserId: session.professionalId,
                professionalId: '',
                patientDisplayName: session.patientName,
                professionalDisplayName: session.professionalName,
                professionalPhotoUrl: session.photoIntroUrl,
                status: 'active'));
      }
      setState(() {
        _links = peers.values.toList();
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
    return Scaffold(
      appBar: embeddedProfessional
          ? null
          : AppBar(
              title: const Text('Messages'),
              backgroundColor: MalvaColors.seed,
              foregroundColor: Colors.white,
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (embeddedProfessional) ...[
              Text('Messages',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                subtitle: 'Hubungkan akun dengan profesional untuk mulai chat.',
              )
            else
              for (final link in _links) ...[
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
                          otherUserId:
                              isPro ? link.patientId : link.professionalUserId,
                          otherUserPhotoUrl:
                              isPro ? '' : link.professionalPhotoUrl,
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
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        status == 'active' ? MalvaColors.mint : Colors.black26,
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
                      label: status == 'active' ? 'Terhubung' : status,
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
