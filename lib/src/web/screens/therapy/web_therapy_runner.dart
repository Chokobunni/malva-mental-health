import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../widgets/therapy_library.dart';
import '../../services/web_therapy_service.dart';
import '../../web_theme.dart';
import '../../widgets/web_worksheet_field.dart';

/// Runner worksheet terapi web — generik untuk SEMUA [TherapyFieldKind].
///
/// Panel panduan langkah tampil sebagai kolom kiri pada layar lebar dan sebagai
/// accordion di atas form pada jendela sempit. Validasi dilakukan di sini;
/// penyimpanan ke server dilakukan induk lewat [onSave] (payload siap kirim).
class WebTherapyRunner extends StatefulWidget {
  const WebTherapyRunner({
    super.key,
    required this.module,
    required this.onSave,
    required this.onCancel,
    this.saving = false,
    this.saveError,
  });

  final TherapyModule module;

  /// Dipanggil dengan payload `answers` (bentuknya sama dengan mobile).
  final ValueChanged<Map<String, dynamic>> onSave;
  final VoidCallback onCancel;
  final bool saving;

  /// Pesan kegagalan simpan dari induk (bila ada).
  final String? saveError;

  @override
  State<WebTherapyRunner> createState() => _WebTherapyRunnerState();
}

class _WebTherapyRunnerState extends State<WebTherapyRunner> {
  final WebWorksheetAnswers _answers = WebWorksheetAnswers();
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  final Map<String, List<TextEditingController>> _pointControllers =
      <String, List<TextEditingController>>{};
  String? _validationError;

  @override
  void initState() {
    super.initState();
    for (final TherapyWorksheetField field in widget.module.worksheetFields) {
      if (field.kind == TherapyFieldKind.text) {
        _textControllers[field.id] = TextEditingController();
      }
      if (field.kind == TherapyFieldKind.points) {
        _pointControllers[field.id] = List<TextEditingController>.generate(
          field.pointCount,
          (_) => TextEditingController(),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _textControllers.values) {
      controller.dispose();
    }
    for (final List<TextEditingController> controllers
        in _pointControllers.values) {
      for (final TextEditingController controller in controllers) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  void _submit() {
    final error = _answers.validationError(widget.module);
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    setState(() => _validationError = null);
    widget.onSave(_answers.toPayload(widget.module));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final wide = constraints.maxWidth >= WebBreakpoints.splitPanel;
        final form = _buildForm();
        if (!wide) {
          return Column(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _StepsAccordion(module: widget.module),
                      const SizedBox(height: 12),
                      form,
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              _BottomBar(
                module: widget.module,
                filled: _answers.filledCount(widget.module),
                saving: widget.saving,
                error: _validationError ?? widget.saveError,
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
              width: 320,
              // Panduan bisa lebih tinggi dari viewport (modul 7 langkah):
              // dibungkus scroll agar tidak overflow di layar 900 px.
              child: SingleChildScrollView(
                child: _GuidePanel(
                  module: widget.module,
                  filled: _answers.filledCount(widget.module),
                  saving: widget.saving,
                  error: _validationError ?? widget.saveError,
                  onSubmit: _submit,
                  onCancel: widget.onCancel,
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(child: SingleChildScrollView(child: form)),
          ],
        );
      },
    );
  }

  Widget _buildForm() {
    final fields = widget.module.worksheetFields;
    if (fields.isEmpty) {
      return const WebAdminPlaceholderNote(
        message: 'Modul ini belum memiliki kolom isian.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final TherapyWorksheetField field in fields) ...<Widget>[
          WebWorksheetFieldInput(
            field: field,
            answers: _answers,
            enabled: !widget.saving,
            textController: _textControllers[field.id],
            pointControllers:
                _pointControllers[field.id] ?? const <TextEditingController>[],
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Catatan netral (dipakai modul tanpa kolom isian).
class WebAdminPlaceholderNote extends StatelessWidget {
  const WebAdminPlaceholderNote({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WebSpacing.card),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        border: Border.all(color: const Color(0xFFEDE6F1)),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B6377)),
      ),
    );
  }
}

class _GuidePanel extends StatelessWidget {
  const _GuidePanel({
    required this.module,
    required this.filled,
    required this.saving,
    required this.error,
    required this.onSubmit,
    required this.onCancel,
  });

  final TherapyModule module;
  final int filled;
  final bool saving;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final total = module.worksheetFields.length;
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
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (module.color ?? MalvaColors.seed)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  module.icon ?? Icons.self_improvement_rounded,
                  size: 20,
                  color: module.color ?? MalvaColors.seed,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  module.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            module.description,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF6B6377),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'LANGKAH',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Color(0xFF8B8194),
            ),
          ),
          const SizedBox(height: 8),
          ...List<Widget>.generate(module.steps.length, (int index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(top: 1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3EDF8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      module.steps[index],
                      style: const TextStyle(fontSize: 12, height: 1.45),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Text(
            '$filled/$total kolom terisi',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : filled / total,
              minHeight: 7,
              backgroundColor: const Color(0xFFF0E9F6),
              valueColor: const AlwaysStoppedAnimation<Color>(MalvaColors.seed),
            ),
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              key: const Key('web-therapy-runner-error'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: MalvaColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: MalvaColors.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                error!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: MalvaColors.danger,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('web-therapy-save'),
            onPressed: saving ? null : onSubmit,
            child: Text(saving ? 'Menyimpan...' : 'Simpan worksheet'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('web-therapy-cancel'),
            onPressed: saving ? null : onCancel,
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }
}

class _StepsAccordion extends StatelessWidget {
  const _StepsAccordion({required this.module});

  final TherapyModule module;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        border: Border.all(color: const Color(0xFFEDE6F1)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('web-therapy-steps'),
          initiallyExpanded: false,
          title: Text(
            'Panduan langkah (${module.steps.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: <Widget>[
            for (var i = 0; i < module.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${i + 1}. ',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        module.steps[i],
                        style: const TextStyle(fontSize: 12, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.module,
    required this.filled,
    required this.saving,
    required this.error,
    required this.onSubmit,
    required this.onCancel,
  });

  final TherapyModule module;
  final int filled;
  final bool saving;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final total = module.worksheetFields.length;
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
          if (error != null) ...<Widget>[
            Text(
              error!,
              key: const Key('web-therapy-runner-error'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MalvaColors.danger,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$filled/$total kolom terisi',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const Key('web-therapy-cancel'),
                onPressed: saving ? null : onCancel,
                child: const Text('Batal'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                key: const Key('web-therapy-save'),
                onPressed: saving ? null : onSubmit,
                child: Text(saving ? 'Menyimpan...' : 'Simpan'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
