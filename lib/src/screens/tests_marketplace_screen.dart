import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/therapy_library.dart';

// ============================================================
// TES PSIKOLOGI — katalog dari server (psychological_tests_catalog).
// Bila katalog kosong/belum ada: tampilkan assessment yang memang
// tersedia di aplikasi (PHQ-9/GAD-7, DASS-21, WHO-5) — tanpa harga
// pajangan dan tanpa tombol mati.
// ============================================================

class TestsMarketplaceScreen extends ConsumerStatefulWidget {
  const TestsMarketplaceScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<TestsMarketplaceScreen> createState() =>
      _TestsMarketplaceScreenState();
}

class _TestsMarketplaceScreenState
    extends ConsumerState<TestsMarketplaceScreen> {
  List<BackendPsychTest> _tests = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final token = widget.session?.accessToken ??
        ref.read(currentSessionProvider)?.accessToken;
    // Tanpa token (mode lokal/test): langsung ke fallback assessment riil.
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _tests = const [];
          _isLoading = false;
          _error = null;
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final tests = await apiClient.listPsychTests(accessToken: token);
      if (!mounted) return;
      setState(() {
        _tests = tests;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _tests = const [];
        _isLoading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tes Psikologi'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SoftCard(
              color: MalvaColors.plum,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Apakah kamu baik-baik saja hari ini?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Kenali kondisimu dengan mengikuti tes psikologi dari Malva.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null && _tests.isEmpty)
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
            else if (_tests.isEmpty && _error == null) ...[
              const SectionLabel('Tersedia sekarang'),
              _AvailableTestTile(
                icon: Icons.fact_check_rounded,
                color: MalvaColors.seed,
                title: 'PHQ-9 & GAD-7',
                subtitle:
                    'Screening depresi & kecemasan (16 pertanyaan). Hasil tersimpan & bisa direview profesional.',
                onTap: () => Navigator.pushNamed(context, '/assessment'),
              ),
              const SizedBox(height: 10),
              _AvailableTestTile(
                icon: Icons.assignment_rounded,
                color: MalvaColors.seed,
                title: 'DASS-21',
                subtitle:
                    'Depresi, kecemasan & stres (21 pertanyaan, skor otomatis).',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const TherapyDetailScreen(module: dass21Module),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _AvailableTestTile(
                icon: Icons.favorite_rounded,
                color: MalvaColors.mint,
                title: 'WHO-5',
                subtitle:
                    'Kesejahteraan psikologis (5 pertanyaan, skor otomatis).',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const TherapyDetailScreen(module: who5Module),
                  ),
                ),
              ),
            ] else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
                children: [
                  for (final test in _tests)
                    _TestCard(
                      test: test,
                      onStart: () => _showStartDialog(context, test),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showStartDialog(BuildContext context, BackendPsychTest test) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(test.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(test.description),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MalvaColors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                test.disclaimer.isEmpty
                    ? 'Tes ini TIDAK ditujukan untuk mendiagnosis gangguan psikologis, namun untuk membantu mengenali kondisi diri.'
                    : test.disclaimer,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            if (test.price > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Rp ${_rupiah(test.price)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: MalvaColors.seed,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
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

class _AvailableTestTile extends StatelessWidget {
  const _AvailableTestTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      color: color,
      maxSubtitleLines: 3,
      onTap: onTap,
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test, required this.onStart});

  final BackendPsychTest test;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: MalvaColors.seed.withValues(alpha: 0.1),
            child: const Icon(Icons.psychology_rounded,
                color: MalvaColors.seed, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            test.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              test.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: MalvaColors.amber,
                foregroundColor: MalvaColors.ink,
                minimumSize: const Size.fromHeight(38),
                padding: EdgeInsets.zero,
              ),
              child: const Text('Lihat Detail',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
