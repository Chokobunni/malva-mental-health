import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
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
          _error = 'Login diperlukan.';
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
        _error = 'Gagal memuat earnings: $e';
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
              SoftCard(
                color: MalvaColors.plum,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Total',
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('Monthly',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Rp ${_rupiah(_summary?.netAmount ?? 0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 30,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MoneyLine(
                        label: 'Session',
                        value: 'Rp ${_rupiah(_summary?.grossAmount ?? 0)}'),
                    _MoneyLine(
                        label: 'Platform Fee',
                        value:
                            '-${_summary == null ? 0 : _feePct(_summary!)}%'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const SectionLabel('Payout'),
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.account_balance_rounded,
                            color: MalvaColors.seed),
                        SizedBox(width: 8),
                        Text('BCA 2643985203',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Balance: Rp ${_rupiah(_summary?.netAmount ?? 0)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _transactions.isEmpty
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

  int _feePct(BackendEarningsSummary s) {
    if (s.grossAmount <= 0) return 0;
    return ((s.platformFee / s.grossAmount) * 100).round();
  }

  Future<void> _requestPayout(BuildContext context) async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) return;
    final pending = _transactions.where((t) => t.payoutStatus == 'pending');
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada transaksi pending payout.')),
      );
      return;
    }
    try {
      await apiClient.requestPayout(
        accessToken: accessToken,
        earningId: pending.first.id,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permintaan payout dikirim.'),
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
        SnackBar(content: Text('Gagal: $e')),
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

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
