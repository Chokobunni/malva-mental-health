import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../time/wib.dart';
import 'friendly_error.dart';

String _reviewAccountIdentity(AuthSession? session) => session == null
    ? ''
    : '${session.role.name}:${session.backendUserId?.isNotEmpty == true ? session.backendUserId : session.identifier}';

final reviewEntitlementsRevisionProvider = StateProvider<int>((ref) => 0);
final _reviewPromptedUnitsProvider = StateProvider<Set<String>>((ref) => {});

/// Prompts once per account/unit during this app session, after a server refresh.
class ReviewCompletionPrompt extends ConsumerStatefulWidget {
  const ReviewCompletionPrompt(
      {super.key, required this.apiClient, required this.child});
  final MalvaApiClient apiClient;
  final Widget child;
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll =
        Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_check()));
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
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
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        _checking ||
        _dialogOpen ||
        ModalRoute.of(context)?.isCurrent != true) return;
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
      if (!mounted ||
          generation != _accountGeneration ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed) ||
          identity !=
              _reviewAccountIdentity(ref.read(currentSessionProvider)) ||
          ModalRoute.of(context)?.isCurrent != true) return;
      final prompted = ref.read(_reviewPromptedUnitsProvider);
      final pending =
          eligible.where((e) => !prompted.contains('$identity:${e.key}'));
      if (pending.isEmpty) return;
      final entitlement = pending.first;
      ref.read(_reviewPromptedUnitsProvider.notifier).state = {
        ...prompted,
        '$identity:${entitlement.key}'
      };
      _dialogOpen = true;
      final sent = await showDialog<bool>(
          context: context,
          builder: (_) => _ReviewDialog(
              apiClient: widget.apiClient,
              ownerIdentity: identity,
              entitlement: entitlement,
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
        WidgetsBinding.instance
            .addPostFrameCallback((_) => unawaited(_check()));
      }
    });
    ref.listen<int>(
        reviewEntitlementsRevisionProvider, (_, next) => unawaited(_check()));
    return widget.child;
  }
}

/// Examples are kept outside patient data and are never part of rating totals.
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
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Contoh ulasan (demo)', style: TextStyle(fontSize: 13)),
          subtitle: Text(
              'Bukan pengalaman pasien; tidak dihitung dalam rating.',
              style: TextStyle(fontSize: 11)),
          children: [
            ListTile(
                title: Text('Contoh A · 5 bintang · Membantu'),
                subtitle: Text(
                    'Penjelasan mudah dipahami dan langkah berikutnya jelas.')),
            ListTile(
                title: Text('Contoh B · 4 bintang · Membantu'),
                subtitle: Text(
                    'Saya merasa didengarkan, tetapi ingin waktu diskusi lebih panjang.')),
            ListTile(
                title: Text('Contoh C · 2 bintang · Belum membantu'),
                subtitle: Text(
                    'Pendekatannya belum sesuai kebutuhan saya; saya perlu membahas pilihan lain.')),
          ],
        ),
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
  String? get _completedLabel {
    final raw = widget.entitlement.completedAt;
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    if (parsed == null) return null;
    final date = toWib(parsed);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${widget.entitlement.isPackage ? 'Paket' : 'Sesi'} berakhir ${two(date.day)}/${two(date.month)}/${date.year} · ${two(date.hour)}:${two(date.minute)} WIB';
  }

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
    return PopScope(
      canPop: !_sending,
      child: AlertDialog(
        title:
            Text(widget.entitlement.isPackage ? 'Ulasan paket' : 'Ulasan sesi'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.entitlement.professionalName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (_completedLabel != null)
                  Text(_completedLabel!, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i bintang',
                      onPressed:
                          _sending ? null : () => setState(() => _stars = i),
                      icon: Icon(
                          i <= _stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: Colors.amber),
                    )
                ]),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.entitlement.isPackage
                        ? 'Paket ini membantu saya'
                        : 'Sesi ini membantu saya'),
                    value: _helpful,
                    onChanged: _sending
                        ? null
                        : (v) => setState(() => _helpful = v ?? true)),
                TextField(
                    key: const Key('doctor-review-text'),
                    controller: _text,
                    enabled: !_sending,
                    maxLength: 2000,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                        labelText: 'Komentar (opsional)')),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: _sending ? null : () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
              onPressed: _sending ? null : _send,
              child: Text(_sending ? 'Mengirim…' : 'Kirim ulasan')),
        ],
      ),
    );
  }
}
