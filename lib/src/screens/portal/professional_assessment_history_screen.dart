import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../time/wib.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../../widgets/shared_record_detail.dart';

// ============================================================
// RIWAYAT ASESMEN (professional) — SATU PINTU dari dashboard.
//
// Menggabungkan riwayat screening PHQ-9 + GAD-7 untuk SEMUA pasien yang
// terhubung (active links). Sumber data = `listPatientProfessionalLinks`
// lalu `listScreenings` per pasien (dijalankan paralel dengan Future.wait).
//
// PENTING (privasi & ketahanan): consent satu pasien TIDAK boleh mengosongkan
// seluruh halaman. Bila satu pasien membalas 403 (belum membagikan screening),
// pasien itu cukup ditandai "belum membagikan" — pasien lain tetap tampil.
// Hanya pasien dari daftar link aktif yang boleh muncul.
// ============================================================

class ProfessionalAssessmentHistoryScreen extends ConsumerStatefulWidget {
  const ProfessionalAssessmentHistoryScreen({
    super.key,
    this.session,
    this.apiClient,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<ProfessionalAssessmentHistoryScreen> createState() =>
      _ProfessionalAssessmentHistoryScreenState();
}

/// Satu grup pasien berisi daftar screening miliknya.
class _PatientAssessments {
  _PatientAssessments({
    required this.patientId,
    required this.patientName,
    required this.screenings,
    required this.notShared,
  });

  final String patientId;
  final String patientName;
  final List<BackendScreeningSession> screenings;

  /// True bila pasien membalas 403 (belum membagikan screening). Dipakai untuk
  /// menampilkan penanda per-pasien, bukan mengosongkan seluruh halaman.
  final bool notShared;
}

class _ProfessionalAssessmentHistoryScreenState
    extends ConsumerState<ProfessionalAssessmentHistoryScreen> {
  List<_PatientAssessments> _groups = const [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Mode offline aktif. Hubungkan ke server untuk melihat '
            'riwayat asesmen pasien.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final links = await apiClient.listPatientProfessionalLinks(
          accessToken: accessToken);

      // Muat screening per pasien secara paralel. `loadScreenings` menelan
      // 403 (consent) dan error lain menjadi daftar kosong + penanda, agar
      // satu pasien tidak mematikan Future.wait.
      final groups = await Future.wait(links.map((link) async {
        var notShared = false;
        List<BackendScreeningSession> screenings =
            const <BackendScreeningSession>[];
        try {
          screenings = await apiClient.listScreenings(
            accessToken: accessToken,
            patientId: link.patientId,
            limit: 20,
          );
        } on MalvaApiException catch (error) {
          if (error.statusCode == 403) {
            notShared = true;
          }
        } on Object {
          // Jaringan/error lain: biarkan daftar kosong, jangan gagalkan semua.
        }
        return _PatientAssessments(
          patientId: link.patientId,
          patientName: link.patientDisplayName.trim().isEmpty
              ? 'Pasien Malva'
              : link.patientDisplayName,
          screenings: screenings,
          notShared: notShared,
        );
      }));

      // Urutkan pasien sesuai urutan link; urutkan screening terbaru dulu.
      for (final group in groups) {
        group.screenings.sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
      }

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _isLoading = false;
      });
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyServerMessage(error.message);
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(error);
        _isLoading = false;
      });
    }
  }

  /// Filter grup berdasarkan nama pasien (case-insensitive).
  List<_PatientAssessments> get _filteredGroups {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _groups;
    return _groups
        .where((group) => group.patientName.toLowerCase().contains(query))
        .toList(growable: false);
  }

  int get _totalScreenings =>
      _groups.fold<int>(0, (sum, group) => sum + group.screenings.length);

  @override
  Widget build(BuildContext context) {
    final groups = _filteredGroups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Asesmen'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (!_isLoading && _error == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: const InputDecoration(
                    labelText: 'Cari pasien',
                    hintText: 'Cari nama pasien',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SoftCard(
                child: Column(
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: MalvaColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              )
            else if (groups.isEmpty)
              EmptyState(
                icon: Icons.fact_check_outlined,
                title: _searchQuery.trim().isEmpty
                    ? 'Belum ada riwayat asesmen'
                    : 'Pasien tidak ditemukan',
                subtitle: _searchQuery.trim().isEmpty
                    ? 'Riwayat PHQ-9 & GAD-7 dari pasien terhubung akan tampil di sini.'
                    : 'Coba kata kunci lain atau kosongkan pencarian.',
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '$_totalScreenings asesmen dari ${_groups.length} pasien terhubung',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
              for (final group in groups) ...[
                _PatientGroupSection(group: group),
                const SizedBox(height: 18),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PatientGroupSection extends StatelessWidget {
  const _PatientGroupSection({required this.group});

  final _PatientAssessments group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            InitialAvatar(name: group.patientName, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                group.patientName,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${group.screenings.length} asesmen',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (group.notShared)
          const SoftCard(
            bordered: true,
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: Colors.black45),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Pasien belum membagikan data asesmen.',
                    style: TextStyle(
                        color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        else if (group.screenings.isEmpty)
          const SoftCard(
            bordered: true,
            child: Row(
              children: [
                Icon(Icons.inbox_outlined, color: Colors.black45),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Belum ada asesmen dari pasien ini.',
                    style: TextStyle(
                        color: Colors.black54, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        else
          for (final screening in group.screenings) ...[
            _ScreeningRow(
              patientName: group.patientName,
              screening: screening,
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _ScreeningRow extends StatelessWidget {
  const _ScreeningRow({
    required this.patientName,
    required this.screening,
  });

  final String patientName;
  final BackendScreeningSession screening;

  @override
  Widget build(BuildContext context) {
    final phq9 = screening.phq9;
    final gad7 = screening.gad7;
    final overallColor = _assessmentRiskColor(screening.overallLevel);
    return SoftCard(
      bordered: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => _showDetailSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _screeningDateLabel(screening.createdAt),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
              if (screening.crisisFlag)
                const StatusPill(
                  label: 'Krisis',
                  color: MalvaColors.danger,
                  icon: Icons.warning_amber_rounded,
                )
              else
                StatusPill(
                  label: _assessmentRiskLabel(screening.overallLevel),
                  color: overallColor,
                  icon: Icons.fact_check_rounded,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ScoreChip(
                  label: 'PHQ-9',
                  score: phq9.score,
                  maxScore: phq9.maxScore,
                  level: phq9.level,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ScoreChip(
                  label: 'GAD-7',
                  score: gad7.score,
                  maxScore: gad7.maxScore,
                  level: gad7.level,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetailSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * .85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: SharedRecordDetail.screening(screening: screening),
          ),
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({
    required this.label,
    required this.score,
    required this.maxScore,
    required this.level,
  });

  final String label;
  final int score;
  final int maxScore;
  final String level;

  @override
  Widget build(BuildContext context) {
    final color = _assessmentRiskColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: Colors.black54),
          ),
          const SizedBox(height: 2),
          Text(
            score < 0 || maxScore <= 0 || score > maxScore
                ? 'Belum tersedia'
                : '$score/$maxScore',
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 15, color: color),
          ),
          Text(
            _assessmentRiskLabel(level),
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

/// Label tanggal screening (`dd/MM/yyyy`, WIB) untuk TAMPILAN.
///
/// `createdAt` dari server bisa UTC; laporan klinis harus mengikuti kalender
/// WIB, jadi `formatWibDate` (yang memanggil `toWib` internal) dipakai.
String _screeningDateLabel(DateTime? value) {
  if (value == null) return 'Belum ada tanggal';
  return formatWibDate(value);
}

/// Missing/invalid results do not imply a symptom severity.
String _assessmentRiskLabel(String value) {
  return switch (value.toLowerCase()) {
    'minimal' => 'Minimal',
    'mild' => 'Ringan',
    'moderate' => 'Sedang',
    'moderately_severe' => 'Cukup Berat',
    'severe' => 'Berat',
    'crisis' => 'Krisis',
    _ => 'Belum tersedia',
  };
}

Color _assessmentRiskColor(String value) {
  return switch (value.toLowerCase()) {
    'minimal' => MalvaColors.seed,
    'mild' => MalvaColors.mint,
    'moderate' => const Color(0xFFFFBE55),
    'moderately_severe' => const Color(0xFFE8873C),
    'severe' => MalvaColors.danger,
    'crisis' => MalvaColors.danger,
    _ => Colors.grey,
  };
}
