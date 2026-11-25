import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/client_intent_id.dart';
import '../services/malva_api_client.dart';
import '../time/wib.dart';
import 'friendly_error.dart';

String _reviewAccountIdentity(AuthSession? session) => session == null
    ? ''
    : '${session.role.name}:${session.backendUserId?.isNotEmpty == true ? session.backendUserId : session.identifier}';

final reviewEntitlementsRevisionProvider = StateProvider<int>((ref) => 0);

/// Prompts once per account/unit using a server-backed claim.
class ReviewCompletionPrompt extends ConsumerStatefulWidget {
  const ReviewCompletionPrompt(
      {super.key,
      required this.apiClient,
      required this.child,
      this.enabled = true});
  final MalvaApiClient apiClient;
  final Widget child;
  final bool enabled;
  @override
  ConsumerState<ReviewCompletionPrompt> createState() =>
      _ReviewCompletionPromptState();
}

class _ReviewCompletionPromptState extends ConsumerState<ReviewCompletionPrompt>
    with WidgetsBindingObserver {
  Timer? _poll;
  bool _checking = false;
  bool _dialogOpen = false;
  int _accountGeneration = 0;
  final _claimedUnits = <String, bool>{};
  final _claimIds = <String, String>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll =
        Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_check()));
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  @override
  void didUpdateWidget(covariant ReviewCompletionPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
    }
  }

  bool get _canPrompt {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        widget.enabled &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.of(context)?.isCurrent == true;
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (!_canPrompt || _checking || _dialogOpen) return;
    final owner = ref.read(currentSessionProvider);
    final token = owner?.accessToken;
    if (owner?.role != UserRole.patient || token == null || token.isEmpty)
      return;
    final identity = _reviewAccountIdentity(owner);
    final generation = _accountGeneration;
    _checking = true;
    try {
      final eligible =
          await widget.apiClient.listReviewEntitlements(accessToken: token);
      bool canShow() =>
          _canPrompt &&
          generation == _accountGeneration &&
          identity == _reviewAccountIdentity(ref.read(currentSessionProvider));
      if (!canShow()) return;
      BackendReviewEntitlement? entitlement;
      // Retain claims across a temporary navigation or background transition.
      // The account listener clears them when the authenticated owner changes.
      for (final unit in eligible) {
        if (unit.sessionId.isEmpty == unit.carePackageId.isEmpty) continue;
        var granted = _claimedUnits[unit.key];
        if (granted == null) {
          granted = await widget.apiClient.claimReviewPrompt(
            accessToken: ref.read(currentSessionProvider)?.accessToken ?? token,
            entitlement: unit,
            claimId: _claimIds.putIfAbsent(unit.key, newClientIntentId),
          );
          if (!mounted || generation != _accountGeneration) return;
          _claimedUnits[unit.key] = granted;
          _claimIds.remove(unit.key);
        }
        if (!canShow()) return;
        if (!granted) continue;
        _claimedUnits[unit.key] = false;
        entitlement = unit;
        break;
      }
      final pending = entitlement;
      if (pending == null) return;
      _dialogOpen = true;
      final sent = await showDialog<bool>(
          context: context,
          builder: (_) => _ReviewDialog(
              apiClient: widget.apiClient,
              ownerIdentity: identity,
              entitlement: pending,
              accessToken:
                  ref.read(currentSessionProvider)?.accessToken ?? token));
      if (mounted &&
          sent == true &&
          identity ==
              _reviewAccountIdentity(ref.read(currentSessionProvider))) {
        ref.read(reviewEntitlementsRevisionProvider.notifier).state++;
      }
    } catch (_) {
      // Eligibility failure never blocks care; retry on the next refresh.
    } finally {
      _checking = false;
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthSession?>(currentSessionProvider, (before, after) {
      if (_reviewAccountIdentity(before) != _reviewAccountIdentity(after)) {
        _accountGeneration++;
        _claimedUnits.clear();
        _claimIds.clear();
        WidgetsBinding.instance
            .addPostFrameCallback((_) => unawaited(_check()));
      }
    });
    ref.listen<int>(
        reviewEntitlementsRevisionProvider, (_, next) => unawaited(_check()));
    return widget.child;
  }
}

/// Review submission is available for completed sessions or packages.
class DoctorReviewActions extends ConsumerStatefulWidget {
  const DoctorReviewActions(
      {super.key,
      required this.apiClient,
      required this.professionalId,
      required this.onSubmitted,
      this.accessToken});

  final MalvaApiClient apiClient;
  final String professionalId;
  final String? accessToken;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<DoctorReviewActions> createState() =>
      _DoctorReviewActionsState();
}

class _DoctorReviewActionsState extends ConsumerState<DoctorReviewActions> {
  List<BackendReviewEntitlement> _eligible = const [];
  int _request = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant DoctorReviewActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.professionalId != widget.professionalId ||
        oldWidget.accessToken != widget.accessToken) {
      _eligible = const [];
      Future.microtask(_load);
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    final owner = ref.read(currentSessionProvider);
    final identity = _reviewAccountIdentity(owner);
    final token = owner?.accessToken ?? widget.accessToken;
    if (owner?.role != UserRole.patient || token == null || token.isEmpty) {
      if (mounted) setState(() => _eligible = const []);
      return;
    }
    try {
      final items =
          await widget.apiClient.listReviewEntitlements(accessToken: token);
      if (mounted &&
          request == _request &&
          identity ==
              _reviewAccountIdentity(ref.read(currentSessionProvider))) {
        setState(() => _eligible = items
            .where((e) => e.professionalId == widget.professionalId)
            .toList());
      }
    } catch (_) {
      if (mounted && request == _request) setState(() => _eligible = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
        reviewEntitlementsRevisionProvider, (_, next) => unawaited(_load()));
    ref.listen<AuthSession?>(currentSessionProvider, (before, after) {
      if (_reviewAccountIdentity(before) != _reviewAccountIdentity(after)) {
        setState(() => _eligible = const []);
        unawaited(_load());
      }
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_eligible.isNotEmpty) ...[
          OutlinedButton.icon(
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('Tulis ulasan'),
            onPressed: () async {
              final owner = ref.read(currentSessionProvider);
              final ownerIdentity = _reviewAccountIdentity(owner);
              final token = owner?.accessToken ?? widget.accessToken;
              if (token == null || token.isEmpty) return;
              final sent = await showDialog<bool>(
                  context: context,
                  builder: (_) => _ReviewDialog(
                      apiClient: widget.apiClient,
                      ownerIdentity: ownerIdentity,
                      entitlement: _eligible.first,
                      accessToken: token));
              if (context.mounted &&
                  sent == true &&
                  _reviewAccountIdentity(ref.read(currentSessionProvider)) ==
                      ownerIdentity) {
                widget.onSubmitted();
                await _load();
              }
            },
          ),
          const Text(
              'Satu ulasan per sesi satu kali atau paket yang telah selesai. '
              'Nama ditampilkan tersamar; hindari informasi kesehatan pribadi.',
              style: TextStyle(fontSize: 12)),
        ],
      ],
    );
  }
}

class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog(
      {required this.apiClient,
      required this.ownerIdentity,
      required this.entitlement,
      required this.accessToken});
  final MalvaApiClient apiClient;
  final String ownerIdentity;
  final BackendReviewEntitlement entitlement;
  final String accessToken;
  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  final _text = TextEditingController();
  int _stars = 5;
  bool _helpful = true;
  bool _sending = false;
  bool _accountChanged = false;
  String? _error;
  static const _purple = Color(0xff76358e);
  static const _softPurple = Color(0xfff2e8f6);
  static const _border = Color(0xffe4d7e9);
  static const _muted = Color(0xff6d5c75);

  String? get _completedLabel {
    final end = parseWibStored(widget.entitlement.completedAt);
    if (end == null) return null;
    String two(int value) => value.toString().padLeft(2, '0');
    String day(DateTime value) =>
        '${two(value.day)}/${two(value.month)}/${value.year}';
    String time(DateTime value) => '${two(value.hour)}:${two(value.minute)}';
    final start = parseWibStored(widget.entitlement.scheduledAt);
    if (start == null) return 'Berakhir ${day(end)} • ${time(end)} WIB';
    return '${day(start)} • ${time(start)}–'
        '${day(start) == day(end) ? '' : '${day(end)} '}${time(end)} WIB';
  }

  BoxDecoration _panel(Color color) => BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      );

  bool get _isCurrent =>
      !_accountChanged &&
      _reviewAccountIdentity(ref.read(currentSessionProvider)) ==
          widget.ownerIdentity;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_isCurrent) return;
    final token =
        ref.read(currentSessionProvider)?.accessToken ?? widget.accessToken;
    if (token.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.apiClient.createDoctorReview(
          accessToken: token,
          userId: widget.entitlement.professionalId,
          sessionId: widget.entitlement.sessionId,
          carePackageId: widget.entitlement.carePackageId,
          stars: _stars,
          reviewText: _text.text.trim(),
          helpful: _helpful);
      if (mounted && _isCurrent) Navigator.pop(context, true);
    } catch (error) {
      if (mounted && _isCurrent)
        setState(() {
          _sending = false;
          _error = friendlyErrorMessage(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthSession?>(currentSessionProvider, (_, next) {
      if (_reviewAccountIdentity(next) != widget.ownerIdentity) {
        _accountChanged = true;
        _text.clear();
      }
    });
    final ownerIdentity =
        _reviewAccountIdentity(ref.watch(currentSessionProvider));
    if (_accountChanged || ownerIdentity != widget.ownerIdentity) {
      return AlertDialog(
          content: const Text('Sesi akun telah berubah.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'))
          ]);
    }
    final entitlement = widget.entitlement;
    final (title, badge, intro, service, helpful, icon) = entitlement.isPackage
        ? (
            'Ulasan Paket',
            'PAKET KONSULTASI',
            'Bagikan pengalaman konsultasimu',
            '',
            'Paket ini membantu saya',
            Icons.inventory_2_outlined
          )
        : switch (entitlement.sessionType) {
            'video' => (
                'Ulasan Sesi Video',
                'SESI SEKALI • VIDEO',
                'Bagaimana sesi video call barusan?',
                'Konsultasi Video (1× Sesi)',
                'Sesi video ini membantu saya',
                Icons.videocam_outlined
              ),
            'chat' => (
                'Ulasan Sesi Chat',
                'SESI SEKALI • CHAT',
                'Bagaimana sesi chat konsultasimu barusan?',
                'Konsultasi Chat',
                'Sesi ini membantu saya',
                Icons.chat_bubble_outline
              ),
            _ => (
                'Ulasan Sesi',
                'SESI SEKALI',
                'Bagaimana sesi konsultasimu?',
                '',
                'Sesi ini membantu saya',
                Icons.event_outlined
              ),
          };
    final initials = entitlement.professionalName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !word.contains('.'))
        .take(2)
        .map((word) => word.characters.first)
        .join()
        .toUpperCase();
    final completedLabel = _completedLabel;
    return PopScope(
      canPop: !_sending,
      child: Dialog(
        backgroundColor: const Color(0xfffaf6fb),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ))),
                  IconButton(
                    tooltip: 'Tutup',
                    style: IconButton.styleFrom(backgroundColor: _softPurple),
                    onPressed: _sending ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: _muted),
                  ),
                ]),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: _panel(_softPurple),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(icon, color: _purple, size: 14),
                      const SizedBox(width: 5),
                      Text(badge,
                          style: const TextStyle(
                              color: _purple,
                              fontWeight: FontWeight.w800,
                              fontSize: 11)),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Text(intro, style: const TextStyle(color: _muted)),
                const SizedBox(height: 14),
                Container(
                  decoration: _panel(_softPurple),
                  padding: const EdgeInsets.all(13),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      child: initials.isEmpty ? Icon(icon) : Text(initials),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entitlement.professionalName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        if (service.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(service,
                                style: const TextStyle(
                                    color: _purple,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                          ),
                        if (completedLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(completedLabel,
                                style: const TextStyle(
                                    color: _muted, fontSize: 12)),
                          ),
                      ],
                    )),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Flexible(
                          child: IconButton(
                        tooltip: '$i bintang',
                        isSelected: i <= _stars,
                        onPressed:
                            _sending ? null : () => setState(() => _stars = i),
                        icon: const Icon(Icons.star_border_rounded),
                        selectedIcon: const Icon(Icons.star_rounded),
                        color: const Color(0xffecab20),
                        iconSize: 31,
                      )),
                  ],
                ),
                Align(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xfffff7df),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: Text(
                        const [
                          'Sangat Kurang',
                          'Kurang Memuaskan',
                          'Cukup',
                          'Memuaskan',
                          'Sangat Memuaskan!',
                        ][_stars - 1],
                        style: const TextStyle(
                            color: Color(0xff8b570c),
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: _panel(Colors.white),
                  child: Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        secondary:
                            const Icon(Icons.thumb_up_outlined, color: _purple),
                        title: Text(helpful),
                        activeTrackColor: _purple,
                        value: _helpful,
                        onChanged: _sending
                            ? null
                            : (value) => setState(() => _helpful = value),
                      )),
                ),
                const SizedBox(height: 13),
                TextField(
                  key: const Key('doctor-review-text'),
                  controller: _text,
                  enabled: !_sending,
                  maxLength: 2000,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText:
                        'Ceritakan pengalamanmu atau masukan untuk dokter (opsional)…',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _border),
                    ),
                  ),
                ),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 9),
                Row(children: [
                  Expanded(
                      child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: _softPurple,
                      foregroundColor: _purple,
                      minimumSize: const Size(0, 46),
                    ),
                    onPressed: _sending ? null : () => Navigator.pop(context),
                    child: const Text('Batal'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _purple,
                          minimumSize: const Size(0, 46),
                        ),
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.send_outlined, size: 18),
                        label: Text(_sending ? 'Mengirim…' : 'Kirim Ulasan'),
                      )),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
