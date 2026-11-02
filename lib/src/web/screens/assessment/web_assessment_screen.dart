import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../theme.dart';
import '../../../time/wib.dart';
import '../../../widgets/friendly_error.dart';
import '../../services/web_assessment_service.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';
import 'web_assessment_history_view.dart';
import 'web_assessment_result_view.dart';
import 'web_assessment_runner.dart';

/// Alur asesmen web (`/asesmen`).
///
/// Satu layar dengan empat tampilan internal (hub → runner → hasil → riwayat)
/// agar URL tetap satu (`/asesmen`) dan tidak ada Navigator bertumpuk.
class WebAssessmentScreen extends ConsumerStatefulWidget {
  const WebAssessmentScreen({super.key});

  @override
  ConsumerState<WebAssessmentScreen> createState() =>
      _WebAssessmentScreenState();
}

enum _WebAssessmentView { hub, runner, result, history }

class _WebAssessmentScreenState extends ConsumerState<WebAssessmentScreen> {
  _WebAssessmentView _view = _WebAssessmentView.hub;
  WebAssessmentInstrument _instrument = WebAssessmentInstrument.screening;
  WebAssessmentOutcome? _outcome;
  List<int> _lastAnswers = const <int>[];

  List<WebAssessmentHistoryEntry> _entries =
      const <WebAssessmentHistoryEntry>[];
  bool _historyLoading = true;
  Object? _historyError;

  bool _saving = false;
  bool _saved = false;
  String? _saveError;
  String? _savedSubmissionId;
  String? _shareNote;
  bool _sharing = false;

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

  String get _patientId =>
      ref.read(authStateProvider).session?.backendUserId ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  /// Memuat riwayat gabungan: screening (PHQ-9 + GAD-7) dan therapy submission
  /// (DASS-21 / WHO-5). Kegagalan hanya ditampilkan di kartu riwayat — hub tetap
  /// bisa dipakai untuk memulai asesmen baru.
  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final screenings = await api.listScreenings(
        accessToken: _token,
        patientId: _patientId,
        limit: 50,
      );
      final submissions = await api.listTherapySubmissions(
        accessToken: _token,
        patientId: _patientId.isEmpty ? null : _patientId,
      );
      final entries = <WebAssessmentHistoryEntry>[
        ...screenings.map(webHistoryFromScreening),
        ...submissions
            .map(webHistoryFromTherapy)
            .whereType<WebAssessmentHistoryEntry>(),
      ];
      entries.sort((WebAssessmentHistoryEntry a, WebAssessmentHistoryEntry b) {
        final aTime = a.createdAt;
        final bTime = b.createdAt;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _historyLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = error;
        _historyLoading = false;
      });
    }
  }

  void _start(WebAssessmentInstrument instrument) {
    setState(() {
      _instrument = instrument;
      _outcome = null;
      _lastAnswers = const <int>[];
      _saved = false;
      _saving = false;
      _saveError = null;
      _savedSubmissionId = null;
      _shareNote = null;
      _view = _WebAssessmentView.runner;
    });
  }

  void _cancelRunner() {
    setState(() => _view = _WebAssessmentView.hub);
  }

  /// Hitung hasil (mesin lokal) lalu tampilkan segera; penyimpanan berjalan di
  /// belakang dan kegagalannya tidak menghapus hasil.
  void _submitAnswers(List<int> answers) {
    final now = wibNow();
    final outcome = switch (_instrument) {
      WebAssessmentInstrument.screening => buildScreeningOutcome(
          phq9Answers: answers.sublist(0, 9),
          gad7Answers: answers.sublist(9, 16),
          createdAt: now,
        ),
      WebAssessmentInstrument.dass21 =>
        buildDass21Outcome(answers: answers, createdAt: now),
      WebAssessmentInstrument.who5 =>
        buildWho5Outcome(answers: answers, createdAt: now),
    };
    setState(() {
      _outcome = outcome;
      _lastAnswers = answers;
      _view = _WebAssessmentView.result;
      _saving = true;
      _saved = false;
      _saveError = null;
      _savedSubmissionId = null;
      _shareNote = null;
    });
    unawaited(_persist(outcome));
  }

  Future<void> _persist(WebAssessmentOutcome outcome) async {
    try {
      final api = ref.read(apiClientProvider);
      if (outcome.instrument == WebAssessmentInstrument.screening) {
        final bundle = outcome.screeningBundle;
        if (bundle == null) {
          throw const MalvaApiException('Hasil screening tidak lengkap.');
        }
        await api.submitScreening(
          accessToken: _token,
          bundle: bundle,
          phq9Answers: _lastAnswers.sublist(0, 9),
          gad7Answers: _lastAnswers.sublist(9, 16),
          patientId: _patientId,
        );
      } else {
        final submission = await api.createTherapySubmission(
          accessToken: _token,
          moduleId: outcome.instrument.moduleId,
          title:
              '${outcome.instrument.title} — ${formatWibDate(outcome.createdAt)}',
          answers: outcome.therapyAnswers ?? const <String, dynamic>{},
          summary: outcome.summaryText,
        );
        if (!mounted) return;
        setState(() => _savedSubmissionId = submission.id);
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
        _saveError = null;
      });
      unawaited(_loadHistory());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = false;
        _saveError = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _retrySave() async {
    final outcome = _outcome;
    if (outcome == null || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    await _persist(outcome);
  }

  /// Bagikan hasil DASS-21/WHO-5 ke profesional yang terhubung.
  Future<void> _share() async {
    final submissionId = _savedSubmissionId;
    if (submissionId == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final api = ref.read(apiClientProvider);
      final links = await api.listPatientProfessionalLinks(accessToken: _token);
      if (!mounted) return;
      if (links.isEmpty) {
        setState(() => _shareNote =
            'Belum ada profesional terhubung. Hubungkan dulu dari menu '
                'Profesional.');
        return;
      }
      final selected = await showDialog<BackendPatientProfessionalLink>(
        context: context,
        builder: (BuildContext dialogContext) => _ShareDialog(links: links),
      );
      if (selected == null || !mounted) return;
      await api.shareTherapySubmission(
        accessToken: _token,
        submissionId: submissionId,
        professionalId: selected.professionalUserId.isNotEmpty
            ? selected.professionalUserId
            : selected.professionalId,
      );
      if (!mounted) return;
      setState(() => _shareNote =
          'Hasil dibagikan ke ${selected.professionalDisplayName}.');
      unawaited(_loadHistory());
    } catch (error) {
      if (!mounted) return;
      // 403 = belum ada paket sesi aktif (server menolak berbagi). Beri pesan
      // yang bisa ditindaklanjuti, bukan error mentah.
      final isForbidden = error is MalvaApiException &&
          (error.statusCode == 403 || error.statusCode == 402);
      setState(() => _shareNote = isForbidden
          ? 'Butuh paket sesi aktif untuk membagikan hasil ke profesional. '
              'Aktifkan paket lalu coba lagi.'
          : friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_view) {
      case _WebAssessmentView.runner:
        return WebAssessmentRunner(
          key: ValueKey<WebAssessmentInstrument>(_instrument),
          instrument: _instrument,
          submitting: false,
          onSubmit: _submitAnswers,
          onCancel: _cancelRunner,
        );
      case _WebAssessmentView.result:
        final outcome = _outcome;
        if (outcome == null) return _buildHub(context);
        return WebAssessmentResultView(
          outcome: outcome,
          saved: _saved,
          saveError: _saveError,
          onRetrySave: _saving ? null : () => unawaited(_retrySave()),
          onRepeat: () => _start(outcome.instrument),
          onOpenHistory: () =>
              setState(() => _view = _WebAssessmentView.history),
          onShare: outcome.instrument.canShare &&
                  _saved &&
                  _savedSubmissionId != null &&
                  !_sharing
              ? () => unawaited(_share())
              : null,
          shareNote: _shareNote,
        );
      case _WebAssessmentView.history:
        return WebAssessmentHistoryView(
          entries: _entries,
          loading: _historyLoading,
          error: _historyError,
          onRefresh: () => unawaited(_loadHistory()),
          onBack: () => setState(() => _view = _WebAssessmentView.hub),
        );
      case _WebAssessmentView.hub:
        return _buildHub(context);
    }
  }

  Widget _buildHub(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Asesmen',
          subtitle: 'Empat instrumen tervalidasi dengan skoring otomatis, '
              'Forward Chaining, dan Certainty Factor. Hasil ditinjau bersama '
              'profesional saat sesi.',
          trailing: OutlinedButton.icon(
            key: const Key('web-assessment-open-history'),
            onPressed: () => setState(() => _view = _WebAssessmentView.history),
            icon: const Icon(Icons.history_rounded, size: 17),
            label: const Text('Riwayat'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        _buildLastConfidence(),
        const SizedBox(height: WebSpacing.section),
        const WebSectionTitle(text: 'PILIH INSTRUMEN'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final columns = constraints.maxWidth >= 900 ? 2 : 1;
            final width =
                (constraints.maxWidth - WebSpacing.cardGap * (columns - 1)) /
                    columns;
            return Wrap(
              spacing: WebSpacing.cardGap,
              runSpacing: WebSpacing.cardGap,
              children: WebAssessmentInstrument.values
                  .map(
                    (WebAssessmentInstrument instrument) => SizedBox(
                      width: width,
                      child: _InstrumentCard(
                        instrument: instrument,
                        lastEntry: _lastEntryFor(instrument),
                        loading: _historyLoading,
                        onStart: () => _start(instrument),
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
        const SizedBox(height: WebSpacing.section),
        WebAdminCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.info_outline_rounded,
                  color: MalvaColors.plum, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hasil asesmen bukan diagnosis. Instrumen ini membantu '
                  'memetakan gejala; keputusan klinis tetap di tangan '
                  'profesional. Untuk kondisi darurat, hubungi 119.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  WebAssessmentHistoryEntry? _lastEntryFor(
    WebAssessmentInstrument instrument,
  ) {
    for (final WebAssessmentHistoryEntry entry in _entries) {
      if (entry.instrument == instrument) return entry;
    }
    return null;
  }

  Widget _buildLastConfidence() {
    final latest = _entries.isEmpty ? null : _entries.first;
    if (_historyLoading) {
      return const WebAdminCard(
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Memuat hasil terakhir...',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF6B6377)),
            ),
          ],
        ),
      );
    }
    if (_historyError != null) {
      return WebAdminCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded,
                size: 18, color: Color(0xFF8A5A00)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Riwayat belum bisa dimuat: ${friendlyErrorMessage(_historyError!)} '
                'Anda tetap bisa memulai asesmen baru.',
                style: const TextStyle(fontSize: 12.5, height: 1.45),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_loadHistory()),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }
    if (latest == null) {
      return const WebAdminCard(
        child: Row(
          children: <Widget>[
            Icon(Icons.auto_awesome_outlined,
                size: 18, color: MalvaColors.seed),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Belum ada hasil asesmen. Mulai dari PHQ-9 + GAD-7 untuk '
                'gambaran awal.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF6B6377)),
              ),
            ),
          ],
        ),
      );
    }
    return WebAdminCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: MalvaColors.seed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.insights_rounded,
                color: MalvaColors.seed, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'CF TERAKHIR',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Color(0xFF8B8194),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${latest.instrument.shortTitle} · ${latest.level} · '
                  'CF ${latest.certaintyPercent}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatWibDateTimeOrDash(latest.createdAt),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF8B8194),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _view = _WebAssessmentView.history),
            child: const Text('Lihat riwayat'),
          ),
        ],
      ),
    );
  }
}

/// Kartu instrumen pada hub (2×2).
class _InstrumentCard extends StatelessWidget {
  const _InstrumentCard({
    required this.instrument,
    required this.lastEntry,
    required this.loading,
    required this.onStart,
  });

  final WebAssessmentInstrument instrument;
  final WebAssessmentHistoryEntry? lastEntry;
  final bool loading;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final entry = lastEntry;
    return Container(
      padding: const EdgeInsets.all(WebSpacing.card),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        border: Border.all(color: const Color(0xFFEDE6F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(_icon, color: _accent, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      instrument.title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${instrument.itemCount} soal · ± ${instrument.estimatedMinutes} menit',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF8B8194),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            instrument.description,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Color(0xFF6B6377),
            ),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Text(
              'Memuat hasil terakhir...',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
            )
          else if (entry == null)
            const Text(
              'Belum pernah dikerjakan.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4FB),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.history_rounded,
                      size: 14, color: Color(0xFF8B8194)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Terakhir: ${entry.level} · ${entry.scoreText} · '
                      '${formatWibDateTimeOrDash(entry.createdAt)}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: Key('web-assessment-start-${instrument.name}'),
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(entry == null ? 'Mulai' : 'Ulangi'),
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon => switch (instrument) {
        WebAssessmentInstrument.screening => Icons.psychology_alt_outlined,
        WebAssessmentInstrument.dass21 => Icons.assignment_outlined,
        WebAssessmentInstrument.who5 => Icons.favorite_outline_rounded,
      };

  Color get _accent => switch (instrument) {
        WebAssessmentInstrument.screening => MalvaColors.seed,
        WebAssessmentInstrument.dass21 => MalvaColors.orchid,
        WebAssessmentInstrument.who5 => MalvaColors.mint,
      };
}

/// Dialog memilih profesional tujuan berbagi hasil.
class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.links});

  final List<BackendPatientProfessionalLink> links;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late BackendPatientProfessionalLink _selected = widget.links.first;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bagikan hasil',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Pilih profesional yang boleh melihat hasil asesmen ini.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('web-share-professional'),
              initialValue: _selected.professionalUserId.isNotEmpty
                  ? _selected.professionalUserId
                  : _selected.professionalId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Profesional'),
              items: widget.links
                  .map(
                    (BackendPatientProfessionalLink link) =>
                        DropdownMenuItem<String>(
                      value: link.professionalUserId.isNotEmpty
                          ? link.professionalUserId
                          : link.professionalId,
                      child: Text(link.professionalDisplayName),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (String? value) {
                if (value == null) return;
                setState(() {
                  _selected = widget.links.firstWhere(
                    (BackendPatientProfessionalLink link) =>
                        (link.professionalUserId.isNotEmpty
                            ? link.professionalUserId
                            : link.professionalId) ==
                        value,
                    orElse: () => widget.links.first,
                  );
                });
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('web-share-confirm'),
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Bagikan'),
        ),
      ],
    );
  }
}
