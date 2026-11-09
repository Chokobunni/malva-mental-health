import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';

// ============================================================
// EARNINGS DASHBOARD (professional)
// ============================================================

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  BackendEarningsSummary? _summary;
  List<BackendEarningsTransaction> _transactions = const [];
  bool _isLoading = true;
  String? _error;
  final _bankController = TextEditingController();
  final _accountController = TextEditingController();

  @override
  void dispose() {
    _bankController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Mode offline aktif. '
              'Hubungkan ke server untuk melihat earnings.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final full = await apiClient.getEarningsFull(accessToken: accessToken);
      if (!mounted) return;
      setState(() {
        _summary = full.summary;
        _transactions = full.transactions;
        _isLoading = false;
      });
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
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
            else ...[
              const SectionLabel('Payout'),
              SoftCard(
                bordered: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Balance: Rp ${_rupiah(_summary?.pendingNet ?? 0)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    // Sejak aturan "pendapatan diakui saat sesi selesai",
                    // saldo tetap 0 walau pasien sudah membayar. Tanpa
                    // penjelasan ini profesional mengira pembayarannya hilang.
                    Text(
                      'Saldo bertambah setelah sesi ditandai selesai, bukan '
                      'saat pembayaran masuk.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bankController,
                      decoration: const InputDecoration(
                          labelText: 'Bank tujuan', hintText: 'BCA'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _accountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Nomor rekening', hintText: '…'),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (_summary?.pendingNet ?? 0) <= 0
                            ? null
                            : () => _requestPayout(context),
                        child: const Text('Request Payout'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const SectionLabel('Recent Transactions'),
              if (_transactions.isEmpty)
                const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Belum ada transaksi',
                  subtitle:
                      'Transaksi pembayaran yang masuk akan tampil di sini.',
                )
              else
                for (final t in _transactions) ...[
                  SoftCard(
                    bordered: true,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              MalvaColors.seed.withValues(alpha: 0.12),
                          child: const Icon(Icons.person_rounded,
                              color: MalvaColors.seed),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.reference,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                              Text(t.paymentMethod,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        Text(
                          'Rp ${_rupiah(t.net)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: MalvaColors.mint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _requestPayout(BuildContext context) async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) return;
    // Saldo gabungan: yang dicairkan adalah SELURUH earning pending, jadi
    // kelayakan ditentukan oleh pendingNet, bukan oleh ada/tidaknya baris
    // transaksi (daftar transaksi dibatasi 20 baris dan bisa kosong walau
    // masih ada saldo).
    if ((_summary?.pendingNet ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada saldo yang bisa dicairkan.')),
      );
      return;
    }
    final bank = _bankController.text.trim();
    final account = _accountController.text.trim();
    if (bank.isEmpty || account.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi bank & nomor rekening dulu.')),
      );
      return;
    }
    try {
      final result = await apiClient.requestPayoutAll(
        accessToken: accessToken,
        bank: bank,
        account: account,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permintaan payout dikirim: '
              'Rp ${_rupiah(result.netAmount)} '
              '(${result.count} transaksi).'),
          backgroundColor: MalvaColors.mint,
        ),
      );
      _load();
    } on MalvaApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: MalvaColors.danger),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  static String _rupiah(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final pos = s.length - i;
      buf.write(s[i]);
      if (pos > 1 && pos % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }
}
