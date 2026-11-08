import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import 'friendly_error.dart';

String _reviewAccountIdentity(AuthSession? session) => session == null
    ? ''
    : '${session.role.name}:${session.backendUserId?.isNotEmpty == true ? session.backendUserId : session.identifier}';

/// Examples are kept outside patient data and are never part of rating totals.
class DoctorReviewActions extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accessToken?.isNotEmpty == true) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Tulis ulasan'),
              onPressed: () async {
                final owner = ref.read(currentSessionProvider);
                final ownerIdentity = _reviewAccountIdentity(owner);
                final token = owner?.accessToken ?? accessToken;
                if (token == null || token.isEmpty) return;
                final sent = await showDialog<bool>(
                    context: context,
                    builder: (_) => _ReviewDialog(
                        apiClient: apiClient,
                        ownerIdentity: ownerIdentity,
                        professionalId: professionalId,
                        accessToken: token));
                if (context.mounted &&
                    sent == true &&
                    _reviewAccountIdentity(ref.read(currentSessionProvider)) ==
                        ownerIdentity) onSubmitted();
              },
            ),
            const Text(
                'Ulasan hanya dapat dikirim setelah sesi selesai. '
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

class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog(
      {required this.apiClient,
      required this.ownerIdentity,
      required this.professionalId,
      required this.accessToken});
  final MalvaApiClient apiClient;
  final String ownerIdentity;
  final String professionalId;
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
          userId: widget.professionalId,
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
        title: const Text('Ulasan sesi'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                    title: const Text('Sesi ini membantu saya'),
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
