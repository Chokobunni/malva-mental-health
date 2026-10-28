import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';

// ============================================================
// PRO PRICING — katalog harga profesional (F-13 / WS-3).
//   - Muat harga via GET /v1/pricing (reuse `getPricing`).
//   - Simpan via PUT /v1/professional/pricing (`updatePricing`).
//   - Tiga harga: quick chat, quick video, paket 4 sesi / 6 minggu.
// Semua dari server — tanpa data demo.
// ============================================================

class ProPricingScreen extends ConsumerStatefulWidget {
  const ProPricingScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<ProPricingScreen> createState() => _ProPricingScreenState();
}

class _ProPricingScreenState extends ConsumerState<ProPricingScreen> {
  final TextEditingController _chatPrice = TextEditingController();
  final TextEditingController _videoPrice = TextEditingController();
  final TextEditingController _packagePrice = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);

  String? get _token {
    final t = widget.session?.accessToken;
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _chatPrice.dispose();
    _videoPrice.dispose();
    _packagePrice.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Login dulu untuk mengatur harga.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final pricing = await _api.getPricing(accessToken: token);
      if (!mounted) return;
      setState(() {
        _chatPrice.text =
            pricing.quickChatPrice > 0 ? '${pricing.quickChatPrice}' : '';
        _videoPrice.text =
            pricing.quickVideoPrice > 0 ? '${pricing.quickVideoPrice}' : '';
        _packagePrice.text =
            pricing.packagePrice > 0 ? '${pricing.packagePrice}' : '';
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

  Future<void> _save() async {
    final token = _token;
    if (token == null) return;
    setState(() => _isSaving = true);
    try {
      await _api.updatePricing(
        accessToken: token,
        quickChatPrice: int.tryParse(_chatPrice.text.trim()) ?? 0,
        quickVideoPrice: int.tryParse(_videoPrice.text.trim()) ?? 0,
        packagePrice: int.tryParse(_packagePrice.text.trim()) ?? 0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harga tersimpan.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Katalog Harga'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: MalvaColors.danger,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    const SectionLabel('Harga layanan'),
                    SoftCard(
                      bordered: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Harga ini dipakai saat pasien booking quick chat, '
                            'quick video, atau paket 4 sesi.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                          const SizedBox(height: 14),
                          _PriceField(
                            controller: _chatPrice,
                            label: 'Quick chat (Rp)',
                            icon: Icons.chat_bubble_rounded,
                          ),
                          const SizedBox(height: 12),
                          _PriceField(
                            controller: _videoPrice,
                            label: 'Quick video (Rp)',
                            icon: Icons.videocam_rounded,
                          ),
                          const SizedBox(height: 12),
                          _PriceField(
                            controller: _packagePrice,
                            label: 'Paket 4 sesi / 6 minggu (Rp)',
                            icon: Icons.card_membership_rounded,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isSaving ? null : _save,
                              icon: const Icon(Icons.save_rounded),
                              label: Text(
                                  _isSaving ? 'Menyimpan...' : 'Simpan harga'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Jumlah sesi paket tetap 4 & masa berlaku 6 minggu; '
                      'yang kamu atur hanya harga.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: MalvaColors.seed),
      ),
    );
  }
}
