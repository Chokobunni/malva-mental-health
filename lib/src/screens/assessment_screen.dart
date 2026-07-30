import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assessment_engine.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class AssessmentScreen extends ConsumerStatefulWidget {
  const AssessmentScreen({
    super.key,
    this.session,
    this.isInitialScreening = false,
    this.onComplete,
    this.onBack,
  });

  final AuthSession? session;
  final bool isInitialScreening;
  final VoidCallback? onComplete;
  final VoidCallback? onBack;

  @override
  ConsumerState<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends ConsumerState<AssessmentScreen> {
  late final List<int?> _phq9Answers;
  late final List<int?> _gad7Answers;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _phq9Answers =
        List<int?>.filled(AssessmentEngine.phq9Questions.length, null);
    _gad7Answers =
        List<int?>.filled(AssessmentEngine.gad7Questions.length, null);
  }

  bool get _isComplete =>
      !_phq9Answers.contains(null) && !_gad7Answers.contains(null);

  int get _answeredCount =>
      _phq9Answers.whereType<int>().length +
      _gad7Answers.whereType<int>().length;

  int get _questionCount => _phq9Answers.length + _gad7Answers.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            title: widget.isInitialScreening
                ? 'Screening Awal'
                : 'Self Assessments',
            subtitle: 'PHQ-9 + GAD-7 • 16 pertanyaan dalam satu halaman',
            leading: IconButton(
              onPressed: widget.onBack ?? () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoftCard(
                  color: MalvaColors.seed.withValues(alpha: 0.08),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Jawab sesuai 2 minggu terakhir',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Hasil ini adalah screening, bukan diagnosis. Data akan tersimpan sebagai pertimbangan tambahan profesional.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$_answeredCount dari $_questionCount terjawab',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text(
                            '${(_answeredCount / _questionCount * 100).round()}%',
                            style: const TextStyle(
                              color: MalvaColors.plum,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _answeredCount / _questionCount,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor:
                            MalvaColors.seed.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const _ResponseScaleGuide(),
                const SizedBox(height: 18),
                _AssessmentSection(
                  key: const ValueKey('phq9-section'),
                  title: 'PHQ-9',
                  subtitle: AssessmentType.phq9.subtitle,
                  questions: AssessmentEngine.phq9Questions,
                  answers: _phq9Answers,
                  icon: Icons.sentiment_dissatisfied_rounded,
                  color: MalvaColors.seed,
                  onChanged: (index, value) =>
                      setState(() => _phq9Answers[index] = value),
                ),
                const SizedBox(height: 28),
                _AssessmentSection(
                  key: const ValueKey('gad7-section'),
                  title: 'GAD-7',
                  subtitle: AssessmentType.gad7.subtitle,
                  questions: AssessmentEngine.gad7Questions,
                  answers: _gad7Answers,
                  icon: Icons.psychology_alt_rounded,
                  color: MalvaColors.mint,
                  onChanged: (index, value) =>
                      setState(() => _gad7Answers[index] = value),
                ),
                const SizedBox(height: 24),
                SoftCard(
                  key: const ValueKey('screening-submit-panel'),
                  color: _isComplete
                      ? MalvaColors.mint.withValues(alpha: 0.1)
                      : MalvaColors.seed.withValues(alpha: 0.06),
                  child: Column(
                    children: [
                      Icon(
                        _isComplete
                            ? Icons.check_circle_rounded
                            : Icons.fact_check_outlined,
                        color:
                            _isComplete ? MalvaColors.mint : MalvaColors.seed,
                        size: 38,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isComplete
                            ? 'PHQ-9 dan GAD-7 sudah lengkap'
                            : '${_questionCount - _answeredCount} pertanyaan belum dijawab',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Periksa kembali jawabanmu sebelum mengirim kedua screening.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const ValueKey('screening-submit-button'),
                        onPressed: _isComplete && !_isSubmitting
                            ? _submitResult
                            : null,
                        icon: _isSubmitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(_isSubmitting
                            ? 'Mengirim...'
                            : 'Kirim hasil PHQ-9 + GAD-7'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitResult() async {
    if (_isSubmitting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fact_check_rounded, color: MalvaColors.seed),
        title: const Text('Ringkasan Jawaban'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PHQ-9:',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              for (var i = 0; i < _phq9Answers.length; i++)
                Text(
                    '  ${i + 1}. Skor: ${_phq9Answers[i] ?? 0} — ${_phq9Answers[i] != null ? AssessmentEngine.responseLabels[_phq9Answers[i]!] : "Belum dijawab"}'),
              const SizedBox(height: 12),
              const Text('GAD-7:',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              for (var i = 0; i < _gad7Answers.length; i++)
                Text(
                    '  ${i + 1}. Skor: ${_gad7Answers[i] ?? 0} — ${_gad7Answers[i] != null ? AssessmentEngine.responseLabels[_gad7Answers[i]!] : "Belum dijawab"}'),
              const SizedBox(height: 12),
              Text(
                'Total: $_answeredCount/$_questionCount terjawab',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Kembali Edit'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Ya, Kirim'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    late final ScreeningBundle bundle;
    try {
      bundle =
          await ref.read(malvaStoreProvider.notifier).submitScreeningBundle(
                phq9Answers: _phq9Answers.map((answer) => answer ?? 0).toList(),
                gad7Answers: _gad7Answers.map((answer) => answer ?? 0).toList(),
                isInitial: widget.isInitialScreening,
                source: widget.isInitialScreening
                    ? 'Initial patient screening'
                    : 'Self assessment',
                session: widget.session,
              );
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showSubmitError(error.message);
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Screening berhasil dikirim. ID: ${bundle.id}',
        ),
        backgroundColor: MalvaColors.mint,
      ),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssessmentResultScreen(
          bundle: bundle,
          onDone: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            widget.onComplete?.call();
          },
        ),
      ),
    );
  }

  void _showSubmitError(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cloud_off_rounded, color: MalvaColors.danger),
        title: const Text('Gagal mengirim screening'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _submitResult();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}

class _AssessmentSection extends StatelessWidget {
  const _AssessmentSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.questions,
    required this.answers,
    required this.icon,
    required this.color,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<AssessmentQuestion> questions;
  final List<int?> answers;
  final IconData icon;
  final Color color;
  final void Function(int index, int value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.28)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color,
                foregroundColor: Colors.white,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: MalvaColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${questions.length} soal',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < questions.length; i++) ...[
          _QuestionCard(
            key: ValueKey('${title.toLowerCase()}-question-${i + 1}'),
            number: i + 1,
            question: questions[i].label,
            selected: answers[i],
            color: color,
            onChanged: (value) => onChanged(i, value),
          ),
          if (i != questions.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ResponseScaleGuide extends StatelessWidget {
  const _ResponseScaleGuide();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: MalvaColors.plum),
              SizedBox(width: 8),
              Text(
                'Panduan pilihan jawaban',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var value = 0;
              value < AssessmentEngine.responseLabels.length;
              value++) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
                  foregroundColor: MalvaColors.plum,
                  child: Text(
                    '$value',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AssessmentEngine.responseLabels[value],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (value != AssessmentEngine.responseLabels.length - 1)
              const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.number,
    required this.question,
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  final int number;
  final String question;
  final int? selected;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number. $question',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var value = 0;
                  value < AssessmentEngine.responseLabels.length;
                  value++)
                Semantics(
                  label: '$value, ${AssessmentEngine.responseLabels[value]}',
                  button: true,
                  selected: selected == value,
                  child: ChoiceChip(
                    label: Text('$value'),
                    tooltip: AssessmentEngine.responseLabels[value],
                    selected: selected == value,
                    selectedColor: color.withValues(alpha: 0.2),
                    onSelected: (_) => onChanged(value),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Row(
              key: ValueKey(selected),
              children: [
                Icon(
                  selected == null
                      ? Icons.radio_button_unchecked_rounded
                      : Icons.check_circle_rounded,
                  size: 18,
                  color: selected == null ? Colors.black45 : color,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    selected == null
                        ? 'Pilih jawaban 0–3'
                        : '$selected — ${AssessmentEngine.responseLabels[selected!]}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: selected == null ? Colors.black54 : color,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AssessmentResultScreen extends StatelessWidget {
  const AssessmentResultScreen({
    super.key,
    required this.bundle,
    required this.onDone,
  });

  final ScreeningBundle bundle;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const GradientHeader(
            title: 'Terima Kasih',
            subtitle: 'Hasil screening sudah tersimpan',
            leading: Icon(Icons.local_florist_rounded,
                color: Colors.white, size: 34),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoftCard(
                  color: bundle.overallLevel.color.withValues(alpha: 0.1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Terima kasih sudah membagikan isi hatimu.',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(bundle.summary,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          StatusPill(
                            label:
                                'PHQ-9 ${bundle.phq9.score}/${bundle.phq9.maxScore} ${bundle.phq9.level.label}',
                            color: bundle.phq9.level.color,
                          ),
                          StatusPill(
                            label:
                                'GAD-7 ${bundle.gad7.score}/${bundle.gad7.maxScore} ${bundle.gad7.level.label}',
                            color: bundle.gad7.level.color,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (bundle.crisisFlag) ...[
                  const SizedBox(height: 12),
                  SoftCard(
                    color: MalvaColors.danger.withValues(alpha: 0.1),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: MalvaColors.danger),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Jika ada dorongan menyakiti diri atau merasa tidak aman, segera hubungi orang terdekat, profesional yang menangani, atau layanan darurat setempat.',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const SectionLabel('Tips dukungan'),
                const _TipCard(
                  icon: Icons.psychology_alt_rounded,
                  title: 'Konsultasi psikiater',
                  body:
                      'Psikiater dapat diakses menggunakan BPJS sesuai alur faskes dan rujukan yang berlaku. Bawa hasil screening ini saat konsultasi.',
                  color: MalvaColors.seed,
                ),
                const SizedBox(height: 10),
                const _TipCard(
                  icon: Icons.health_and_safety_rounded,
                  title: 'Psikolog dan konseling',
                  body:
                      'Layanan psikolog atau konseling kesehatan jiwa tersedia di sebagian Puskesmas atau layanan daerah dengan biaya lebih terjangkau. Cek Puskesmas terdekat.',
                  color: MalvaColors.mint,
                ),
                const SizedBox(height: 10),
                const _TipCard(
                  icon: Icons.edit_note_rounded,
                  title: 'Pantau pola harian',
                  body:
                      'Catat mood, tidur, obat, dan trigger harian. Pola ini membantu profesional memahami kondisi dari waktu ke waktu.',
                  color: MalvaColors.amber,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onDone,
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Lanjut ke Home'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
