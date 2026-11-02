import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../services/web_assessment_service.dart';
import '../../web_theme.dart';
import '../../widgets/web_scale_question.dart';

/// Runner asesmen web: daftar pertanyaan + panel kemajuan.
///
/// Panel kiri "sticky" pada layar >= [WebBreakpoints.splitPanel]; di bawah itu
/// panel berubah menjadi bar bawah agar pertanyaan tetap lega di jendela sempit.
class WebAssessmentRunner extends StatefulWidget {
  const WebAssessmentRunner({
    super.key,
    required this.instrument,
    required this.onSubmit,
    required this.onCancel,
    this.submitting = false,
  });

  final WebAssessmentInstrument instrument;

  /// Dipanggil hanya ketika SELURUH pertanyaan terjawab.
  final ValueChanged<List<int>> onSubmit;
  final VoidCallback onCancel;

  /// True saat pengiriman ke server berjalan (tombol dinonaktifkan).
  final bool submitting;

  @override
  State<WebAssessmentRunner> createState() => _WebAssessmentRunnerState();
}

class _WebAssessmentRunnerState extends State<WebAssessmentRunner> {
  late final List<WebAssessmentItem> _items =
      webAssessmentItems(widget.instrument);
  late final List<int?> _answers = List<int?>.filled(_items.length, null);

  int get _answeredCount => _answers.where((int? v) => v != null).length;

  bool get _complete => _answeredCount == _items.length;

  /// Kirim hanya bila lengkap. Penjaga ganda: tombol sudah dinonaktifkan saat
  /// belum lengkap, dan method ini tetap menolak bila dipanggil langsung.
  void _submit() {
    if (!_complete || widget.submitting) return;
    widget.onSubmit(_answers.map((int? v) => v ?? 0).toList(growable: false));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final wide = constraints.maxWidth >= WebBreakpoints.splitPanel;
        final questions = _buildQuestions();
        if (!wide) {
          return Column(
            children: <Widget>[
              Expanded(child: questions),
              _BottomBar(
                instrument: widget.instrument,
                answered: _answeredCount,
                total: _items.length,
                complete: _complete,
                submitting: widget.submitting,
                onSubmit: _submit,
                onCancel: widget.onCancel,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 300,
              child: _ProgressPanel(
                instrument: widget.instrument,
                answered: _answeredCount,
                total: _items.length,
                complete: _complete,
                submitting: widget.submitting,
                onSubmit: _submit,
                onCancel: widget.onCancel,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(child: questions),
          ],
        );
      },
    );
  }

  Widget _buildQuestions() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < _items.length; index++) ...<Widget>[
            if (_items[index].sectionTitle != null) ...<Widget>[
              _SectionHeader(title: _items[index].sectionTitle!),
              const SizedBox(height: 10),
            ],
            WebScaleQuestion(
              item: _items[index],
              value: _answers[index],
              enabled: !widget.submitting,
              onChanged: (int value) => setState(() => _answers[index] = value),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MalvaColors.seed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MalvaColors.seed.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.segment_rounded, size: 16, color: MalvaColors.seed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: MalvaColors.plum,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({
    required this.instrument,
    required this.answered,
    required this.total,
    required this.complete,
    required this.submitting,
    required this.onSubmit,
    required this.onCancel,
  });

  final WebAssessmentInstrument instrument;
  final int answered;
  final int total;
  final bool complete;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WebSpacing.card),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        border: Border.all(color: const Color(0xFFEDE6F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            instrument.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            instrument.description,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF6B6377),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$answered/$total terjawab',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : answered / total,
              minHeight: 7,
              backgroundColor: const Color(0xFFF0E9F6),
              valueColor: const AlwaysStoppedAnimation<Color>(
                MalvaColors.seed,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('web-runner-submit'),
            onPressed: complete && !submitting ? onSubmit : null,
            child: Text(submitting ? 'Mengirim...' : 'Kirim jawaban'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('web-runner-cancel'),
            onPressed: submitting ? null : onCancel,
            child: const Text('Batal'),
          ),
          const SizedBox(height: 10),
          Text(
            complete
                ? 'Semua pertanyaan terjawab. Hasil dihitung otomatis setelah '
                    'dikirim.'
                : 'Jawab semua pertanyaan untuk mengaktifkan tombol kirim.',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.instrument,
    required this.answered,
    required this.total,
    required this.complete,
    required this.submitting,
    required this.onSubmit,
    required this.onCancel,
  });

  final WebAssessmentInstrument instrument;
  final int answered;
  final int total;
  final bool complete;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDE6F1))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${instrument.shortTitle} · $answered/$total terjawab',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const Key('web-runner-cancel'),
                onPressed: submitting ? null : onCancel,
                child: const Text('Batal'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                key: const Key('web-runner-submit'),
                onPressed: complete && !submitting ? onSubmit : null,
                child: Text(submitting ? 'Mengirim...' : 'Kirim'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : answered / total,
              minHeight: 6,
              backgroundColor: const Color(0xFFF0E9F6),
              valueColor: const AlwaysStoppedAnimation<Color>(
                MalvaColors.seed,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
