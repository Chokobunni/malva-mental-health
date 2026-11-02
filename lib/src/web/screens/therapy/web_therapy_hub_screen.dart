import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/platform_providers.dart';
import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../theme.dart';
import '../../../time/wib.dart';
import '../../../widgets/friendly_error.dart';
import '../../../widgets/therapy_library.dart';
import '../../services/web_therapy_service.dart';
import '../../web_routes.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';
import '../../widgets/web_share_professional_dialog.dart';
import 'web_therapy_history_view.dart';
import 'web_therapy_runner.dart';

/// Alur Perpustakaan Terapi web (`/terapi`).
///
/// Hub mengelompokkan modul per kategori dari `therapy_library` (read-only).
/// Modul asesmen (DASS-21, WHO-5) TIDAK punya runner skor kedua di sini —
/// kartunya mengarah ke `/asesmen`. Delapan worksheet lain memakai runner
/// generik yang mendukung semua jenis field.
class WebTherapyHubScreen extends ConsumerStatefulWidget {
  const WebTherapyHubScreen({super.key, required this.onNavigate});

  /// Navigasi rute tingkat atas (dipakai untuk mengarahkan ke `/asesmen`).
  final ValueChanged<String> onNavigate;

  @override
  ConsumerState<WebTherapyHubScreen> createState() =>
      _WebTherapyHubScreenState();
}

enum _WebTherapyView { hub, runner, history }

/// Aksi yang dipilih pada dialog sukses simpan.
enum _WebSavedAction { close, share, download }

class _WebTherapyHubScreenState extends ConsumerState<WebTherapyHubScreen> {
  _WebTherapyView _view = _WebTherapyView.hub;
  TherapyModule? _module;
  bool _saving = false;
  String? _saveError;

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

  void _openModule(TherapyModule module) {
    if (module.isAssessment) {
      widget.onNavigate(WebRoutes.assessment);
      return;
    }
    setState(() {
      _module = module;
      _saveError = null;
      _saving = false;
      _view = _WebTherapyView.runner;
    });
  }

  void _backToHub() {
    setState(() {
      _view = _WebTherapyView.hub;
      _module = null;
      _saveError = null;
      _saving = false;
    });
  }

  Future<void> _save(Map<String, dynamic> answers) async {
    final module = _module;
    if (module == null || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final submission =
          await ref.read(apiClientProvider).createTherapySubmission(
                accessToken: _token,
                moduleId: module.id.isEmpty ? module.title : module.id,
                title: module.title,
                answers: answers,
                summary: assessmentSummary(module.id, answers),
              );
      if (!mounted) return;
      setState(() => _saving = false);
      final action = await _showSavedDialog(module, answers);
      if (!mounted) return;
      if (action == _WebSavedAction.share) {
        await _share(submission);
      } else if (action == _WebSavedAction.download) {
        await _download(module, answers);
      }
      if (!mounted) return;
      _backToHub();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = friendlyErrorMessage(error);
      });
    }
  }

  Future<_WebSavedAction?> _showSavedDialog(
    TherapyModule module,
    Map<String, dynamic> answers,
  ) {
    final summary = webWorksheetSummaryText(
      module: module,
      answers: answers,
      createdAt: wibNow(),
    );
    return showDialog<_WebSavedAction>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Row(
          children: <Widget>[
            WebDialogBadge(icon: Icons.check_rounded),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Worksheet tersimpan',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${module.title} sudah masuk ke riwayat Anda. Anda bisa '
                'membagikannya ke profesional yang terhubung.',
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F4FB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      summary,
                      style: const TextStyle(fontSize: 11.5, height: 1.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('web-therapy-saved-close'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_WebSavedAction.close),
            child: const Text('Tutup'),
          ),
          OutlinedButton.icon(
            key: const Key('web-therapy-saved-download'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_WebSavedAction.download),
            icon: const Icon(Icons.download_rounded, size: 17),
            label: const Text('Unduh ringkasan'),
          ),
          FilledButton.icon(
            key: const Key('web-therapy-saved-share'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(_WebSavedAction.share),
            icon: const Icon(Icons.share_outlined, size: 17),
            label: const Text('Bagikan ke profesional'),
          ),
        ],
      ),
    );
  }

  Future<void> _download(
    TherapyModule module,
    Map<String, dynamic> answers,
  ) async {
    final now = wibNow();
    try {
      await ref.read(fileExporterProvider).saveText(
            filename: webWorksheetFileName(module, now),
            content: webWorksheetSummaryText(
              module: module,
              answers: answers,
              createdAt: now,
            ),
            mimeType: 'text/plain',
            subject: module.title,
          );
      if (!mounted) return;
      _showMessage('Ringkasan diunduh.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal mengunduh. ${friendlyErrorMessage(error)}');
    }
  }

  Future<void> _share(BackendTherapySubmission submission) async {
    try {
      final api = ref.read(apiClientProvider);
      final links = await api.listPatientProfessionalLinks(accessToken: _token);
      if (!mounted) return;
      if (links.isEmpty) {
        _showMessage('Belum ada profesional terhubung. Hubungkan dulu dari '
            'menu Profesional.');
        return;
      }
      final selected = await showWebShareProfessionalDialog(
        context,
        links: links,
        title: 'Bagikan worksheet',
        description: 'Pilih profesional yang boleh melihat worksheet ini.',
      );
      if (selected == null || !mounted) return;
      await api.shareTherapySubmission(
        accessToken: _token,
        submissionId: submission.id,
        professionalId: selected.professionalUserId.isNotEmpty
            ? selected.professionalUserId
            : selected.professionalId,
      );
      if (!mounted) return;
      _showMessage(
          'Worksheet dibagikan ke ${selected.professionalDisplayName}.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(webShareErrorMessage(error));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    switch (_view) {
      case _WebTherapyView.history:
        return WebTherapyHistoryView(onBack: _backToHub);
      case _WebTherapyView.runner:
        final module = _module;
        if (module == null) return _buildHub(context);
        return WebTherapyRunner(
          key: ValueKey<String>(module.id),
          module: module,
          saving: _saving,
          saveError: _saveError,
          onSave: (Map<String, dynamic> answers) => unawaited(_save(answers)),
          onCancel: _backToHub,
        );
      case _WebTherapyView.hub:
        return _buildHub(context);
    }
  }

  Widget _buildHub(BuildContext context) {
    final groups = webTherapyGroups();
    final totalModules = webTherapyModules().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Terapi',
          subtitle: 'Perpustakaan latihan mandiri: $totalModules modul '
              'terstruktur untuk membantu Anda memahami dan mengelola '
              'pikiran, emosi, serta tubuh.',
          trailing: OutlinedButton.icon(
            key: const Key('web-therapy-open-history'),
            onPressed: () => setState(() => _view = _WebTherapyView.history),
            icon: const Icon(Icons.history_rounded, size: 17),
            label: const Text('Riwayat worksheet'),
          ),
        ),
        for (final WebTherapyGroup group in groups) ...<Widget>[
          const SizedBox(height: WebSpacing.section),
          WebSectionTitle(text: group.category.toUpperCase()),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final columns = constraints.maxWidth >= 1280
                  ? 3
                  : (constraints.maxWidth >= 900 ? 2 : 1);
              final width =
                  (constraints.maxWidth - WebSpacing.cardGap * (columns - 1)) /
                      columns;
              return Wrap(
                spacing: WebSpacing.cardGap,
                runSpacing: WebSpacing.cardGap,
                children: group.modules
                    .map(
                      (TherapyModule module) => SizedBox(
                        width: width,
                        child: _TherapyModuleCard(
                          module: module,
                          onOpen: () => _openModule(module),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
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
                  'Latihan di sini bersifat edukatif dan bukan pengganti '
                  'terapi profesional. Bila kondisi Anda memburuk, hubungi '
                  'profesional atau layanan darurat 119.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Kartu satu modul terapi.
class _TherapyModuleCard extends StatelessWidget {
  const _TherapyModuleCard({required this.module, required this.onOpen});

  final TherapyModule module;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = module.color ?? MalvaColors.seed;
    final isAssessment = module.isAssessment;
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  module.icon ?? Icons.self_improvement_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  module.title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            module.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF6B6377),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              WebStatusPill(
                label: module.category ?? 'Lainnya',
                color: accent,
              ),
              WebStatusPill(
                label: '${module.steps.length} langkah',
                color: const Color(0xFF8B8194),
              ),
              if (isAssessment)
                const WebStatusPill(
                  label: 'Berskor',
                  color: MalvaColors.mint,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: Key('therapy-start-${module.id}'),
              onPressed: onOpen,
              icon: Icon(
                isAssessment
                    ? Icons.arrow_forward_rounded
                    : Icons.edit_note_rounded,
                size: 18,
              ),
              label: Text(isAssessment ? 'Buka asesmen' : 'Mulai'),
            ),
          ),
        ],
      ),
    );
  }
}
