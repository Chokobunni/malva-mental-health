import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/initial_screening.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../widgets/friendly_error.dart';
import '../widgets/therapy_library.dart';
import 'assessment_screen.dart';
import 'initial_screening_consent_screen.dart';

/// Initial patient screening saves WHO-5 before applying the entry rules.
class InitialSymptomsScreen extends ConsumerStatefulWidget {
  const InitialSymptomsScreen({
    super.key,
    required this.session,
    required this.apiClient,
    required this.onComplete,
    required this.onBack,
  });

  final AuthSession? session;
  final MalvaApiClient apiClient;
  final VoidCallback onComplete;
  final VoidCallback onBack;

  @override
  ConsumerState<InitialSymptomsScreen> createState() =>
      _InitialSymptomsScreenState();
}

class _InitialSymptomsScreenState extends ConsumerState<InitialSymptomsScreen> {
  final _answers = List<int?>.filled(5, null);
  bool _saving = false;
  String? _error;
  InitialScreeningDecision? _decision;
  bool _showFurtherScreening = false;

  bool _isCurrentAccount(AuthSession? owner) {
    final current = ref.read(currentSessionProvider);
    return owner != null &&
        current != null &&
        current.backendUserId == owner.backendUserId &&
        current.identifier == owner.identifier &&
        current.role == owner.role;
  }

  Map<String, dynamic> get _submissionAnswers => {
        for (var i = 0; i < 5; i++) 'q${i + 1}': _answers[i],
        scaleVersionKey: standardizedScaleVersion,
        scaleMinKey: 0,
        scaleMaxKey: 5,
      };

  Future<void> _save() async {
    if (_saving || _decision != null || _answers.contains(null)) return;
    final owner = widget.session;
    if (!_isCurrentAccount(owner)) return;
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() =>
          _error = 'WHO-5 belum tersimpan. Masuk kembali lalu coba lagi.');
      return;
    }
    final decision = inferInitialScreening(_answers);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final submission = await widget.apiClient.createTherapySubmission(
        accessToken: token,
        moduleId: 'who5',
        title: who5Module.title,
        answers: _submissionAnswers,
        summary: who5Summary(_submissionAnswers),
      );
      if (!mounted || !_isCurrentAccount(owner)) return;
      if (submission.id.isEmpty)
        throw StateError('Server tidak mengembalikan ID hasil.');
      setState(() {
        _saving = false;
        _decision = decision;
      });
    } on Object catch (error) {
      if (!mounted || !_isCurrentAccount(owner)) return;
      setState(() {
        _saving = false;
        _error =
            'WHO-5 belum tersimpan. ${friendlyErrorMessage(error)} Coba kirim ulang.';
      });
    }
  }

  void _finish() {
    if (!_isCurrentAccount(widget.session)) return;
    ref.read(malvaStoreProvider.notifier).completeInitialScreening();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    if (_showFurtherScreening) {
      return AssessmentScreen(
        session: widget.session,
        apiClient: widget.apiClient,
        isInitialScreening: true,
        onComplete: widget.onComplete,
        onBack: () => setState(() => _showFurtherScreening = false),
      );
    }
    final decision = _decision;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: symptomsGradient),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                      onPressed: _saving ? null : widget.onBack,
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white))),
              const Icon(Icons.local_florist_rounded,
                  color: Colors.white, size: 54),
              const SizedBox(height: 16),
              Text('Symptoms Assessment',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(height: 20),
              if (decision == null) ...[
                _card(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(who5Module.title,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      const Text(
                          'WHO-5 mengukur kesejahteraan psikologis selama 2 minggu terakhir. Jawab kelima pernyataan sesuai pengalamanmu. Hasil ini bukan diagnosis.'),
                      const SizedBox(height: 8),
                    ])),
                for (var i = 0; i < who5WorksheetFields.length; i++) ...[
                  const SizedBox(height: 12),
                  _card(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ${who5WorksheetFields[i].label}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        for (var value = 0; value <= 5; value++)
                          Text(
                              '$value = ${who5WorksheetFields[i].scaleLabels[value]}',
                              style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          for (var value = 0; value <= 5; value++)
                            ChoiceChip(
                                key: ValueKey('initial-who5-q${i + 1}-$value'),
                                label: Text('$value'),
                                tooltip:
                                    '$value — ${who5WorksheetFields[i].scaleLabels[value]}',
                                selected: _answers[i] == value,
                                onSelected: _saving
                                    ? null
                                    : (_) =>
                                        setState(() => _answers[i] = value)),
                        ]),
                      ])),
                ],
                const SizedBox(height: 18),
                _card(Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          '${_answers.whereType<int>().length} dari 5 terjawab',
                          textAlign: TextAlign.center),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                            semanticsLabel: _error),
                      ],
                      const SizedBox(height: 10),
                      FilledButton(
                          key: const ValueKey('initial-who5-submit'),
                          onPressed:
                              _saving || _answers.contains(null) ? null : _save,
                          child:
                              Text(_saving ? 'Menyimpan...' : 'Simpan WHO-5')),
                    ])),
              ] else
                _conclusion(context, decision),
            ],
          ),
        ),
      ),
    );
  }

  Widget _conclusion(BuildContext context, InitialScreeningDecision decision) {
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          decision.needsFurtherScreening
              ? 'Lanjutkan screening'
              : 'Kondisi Mental Sangat Baik',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      Text(decision.needsFurtherScreening
          ? 'Kami mendeteksi kondisi emosional anda sedang kurang baik. Mohon lanjut mengisi asesmen berikut untuk analisis lebih dalam.'
          : 'Kondisi psikologis Anda stabil dan luar biasa minggu ini!'),
      const SizedBox(height: 16),
      Text('WHO-5: ${decision.percent}%',
          style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Apa arti skormu?'),
        children: [
          Text(decision.needsFurtherScreening
              ? 'Kesejahteraanmu perlu diperhatikan. Lanjutkan PHQ-9 dan GAD-7 untuk memahami gejala lebih jauh.'
              : 'Kesejahteraanmu berada dalam rentang baik. Pantau perubahan perasaanmu dan cari dukungan bila perlu.'),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
          'Hasil WHO-5 tersimpan untuk 2 minggu terakhir dan bukan diagnosis. Kamu tetap dapat berkonsultasi atau mengisi screening lagi bila membutuhkan dukungan.'),
      const SizedBox(height: 18),
      FilledButton(
          onPressed: decision.needsFurtherScreening
              ? () => setState(() => _showFurtherScreening = true)
              : _finish,
          child: Text(decision.needsFurtherScreening
              ? 'Lanjut PHQ-9 + GAD-7'
              : 'Lanjut ke Home')),
    ]));
  }

  Widget _card(Widget child) => Card(
      color: Colors.white,
      child: Padding(padding: const EdgeInsets.all(18), child: child));
}
