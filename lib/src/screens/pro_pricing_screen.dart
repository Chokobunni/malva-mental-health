import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/professional_availability_summary.dart';

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
        _chatPrice.text = formatProfessionalPrice(pricing.quickChatPrice);
        _videoPrice.text = formatProfessionalPrice(pricing.quickVideoPrice);
        _packagePrice.text = formatProfessionalPrice(pricing.packagePrice);
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
        quickChatPrice: parseProfessionalPrice(_chatPrice.text),
        quickVideoPrice: parseProfessionalPrice(_videoPrice.text),
        packagePrice: parseProfessionalPrice(_packagePrice.text),
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
                    ProfessionalPriceCard(
                      chat: _chatPrice,
                      video: _videoPrice,
                      package: _packagePrice,
                      onSave: _save,
                      isSaving: _isSaving,
                    ),
                  ],
                ),
    );
  }
}
