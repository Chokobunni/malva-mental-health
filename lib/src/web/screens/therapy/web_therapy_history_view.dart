import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../time/wib.dart';
import '../../../widgets/friendly_error.dart';
import '../../../widgets/therapy_library.dart';
import '../../services/web_therapy_service.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// Riwayat worksheet terapi web: daftar `listTherapySubmissions` (hanya
/// worksheet, bukan asesmen), detail read-only, unduh ringkasan, dan hapus
/// dengan konfirmasi.
class WebTherapyHistoryView extends ConsumerStatefulWidget {
  const WebTherapyHistoryView({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<WebTherapyHistoryView> createState() =>
      _WebTherapyHistoryViewState();
}

class _WebTherapyHistoryViewState extends ConsumerState<WebTherapyHistoryView> {
  List<BackendTherapySubmission> _items = const <BackendTherapySubmission>[];
  bool _loading = true;
  Object? _error;
  String _moduleFilter = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

  String get _patientId =>
      ref.read(authStateProvider).session?.backendUserId ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final submissions =
          await ref.read(apiClientProvider).listTherapySubmissions(
                accessToken: _token,
                patientId: _patientId.isEmpty ? null : _patientId,
              );
      if (!mounted) return;
      setState(() {
        // Hanya worksheet terapi; hasil asesmen tampil di /asesmen.
        _items = submissions
            .where(isTherapyRecordSubmission)
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  List<BackendTherapySubmission> get _filtered {
    if (_moduleFilter.isEmpty) return _items;
    return _items
        .where(
            (BackendTherapySubmission item) => item.moduleId == _moduleFilter)
        .toList(growable: false);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _download(BackendTherapySubmission item) async {
    final owner = ref.read(currentSessionProvider);
    final module = webTherapyModuleById(item.moduleId);
    final createdAt = parseWibStored(item.createdAt);
    final content = module == null
        ? item.summary
        : webWorksheetSummaryText(
            module: module,
            answers: item.answers,
            createdAt: createdAt,
          );
    try {
      await ref.read(exportServiceProvider).sharePdf(
            title: 'Worksheet ${item.title} — Malva',
            filename: webWorksheetFileName(
              module ??
                  TherapyModule(
                    title: item.title.isEmpty ? 'worksheet' : item.title,
                    description: '',
                    steps: const <String>[],
                  ),
              createdAt ?? wibNow(),
            ),
            lines: [
              if (createdAt == null) 'Tanggal tidak tercatat',
              ...content.split('\n')
            ],
            canShare: () =>
                mounted && ref.read(currentSessionProvider) == owner,
          );
      if (!mounted || ref.read(currentSessionProvider) != owner) return;
      _showMessage('Ringkasan diunduh.');
    } catch (error) {
      if (!mounted || ref.read(currentSessionProvider) != owner) return;
      _showMessage('Gagal mengunduh. ${friendlyErrorMessage(error)}');
    }
  }

  Future<void> _delete(BackendTherapySubmission item) async {
    final confirmed = await showWebConfirmDialog(
      context,
      title: 'Hapus worksheet',
      message: 'Worksheet "${item.title}" akan dihapus dari riwayat dan tidak '
          'bisa dikembalikan. Profesional yang pernah menerimanya tidak lagi '
          'bisa membuka salinan baru.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(apiClientProvider).deleteTherapySubmission(
            accessToken: _token,
            submissionId: item.id,
          );
      if (!mounted) return;
      _showMessage('Worksheet dihapus.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal menghapus. ${friendlyErrorMessage(error)}');
    }
  }

  void _openDetail(BackendTherapySubmission item) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => _WebTherapyDetailDialog(
        item: item,
        onDownload: () => unawaited(_download(item)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modules = <String, String>{
      for (final BackendTherapySubmission item in _items)
        item.moduleId: webTherapyModuleById(item.moduleId)?.title ??
            (item.title.isEmpty ? item.moduleId : item.title),
    };
    final entries = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Riwayat worksheet',
          subtitle: 'Latihan yang sudah Anda simpan. Hasil asesmen ada di menu '
              'Asesmen.',
          trailing: Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _loading ? null : () => unawaited(_load()),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Muat ulang'),
              ),
              TextButton(
                key: const Key('web-therapy-history-back'),
                onPressed: widget.onBack,
                child: const Text('Kembali'),
              ),
            ],
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 240,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Modul',
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('web-therapy-history-filter'),
                    value: _moduleFilter,
                    isExpanded: true,
                    isDense: true,
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Semua modul'),
                      ),
                      ...modules.entries.map(
                        (MapEntry<String, String> entry) =>
                            DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      ),
                    ],
                    onChanged: (String? value) =>
                        setState(() => _moduleFilter = value ?? ''),
                  ),
                ),
              ),
            ),
            Text(
              '${entries.length} worksheet',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildBody(entries),
        ),
      ],
    );
  }

  Widget _buildBody(List<BackendTherapySubmission> entries) {
    if (_loading) return const WebAdminLoading(label: 'Memuat worksheet...');
    if (_error != null) {
      return WebAdminError(error: _error!, onRetry: () => unawaited(_load()));
    }
    return WebAdminTable(
      minWidth: 1040,
      emptyMessage: 'Belum ada worksheet tersimpan.',
      columns: const <WebAdminColumn>[
        WebAdminColumn('TANGGAL (WIB)', 160),
        WebAdminColumn('MODUL', 220),
        WebAdminColumn('RINGKASAN', 320),
        WebAdminColumn('DIBAGIKAN', 120),
        WebAdminColumn('AKSI', 200, align: Alignment.centerRight),
      ],
      rowKeyBuilder: (int index) => Key('therapy-row-${entries[index].id}'),
      rows: entries.map((BackendTherapySubmission item) {
        final module = webTherapyModuleById(item.moduleId);
        final shared = (item.sharedWithProfessionalId ?? '').isNotEmpty;
        return <Widget>[
          Text(
            formatWibDateTimeOrDash(parseWibStored(item.createdAt)),
            style: const TextStyle(fontSize: 12),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                module?.title ??
                    (item.title.isEmpty ? item.moduleId : item.title),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (module?.category != null)
                Text(
                  module!.category!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8B8194),
                  ),
                ),
            ],
          ),
          Text(
            item.summary.isEmpty ? _firstAnswerPreview(item) : item.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            shared ? 'Sudah' : 'Belum',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: shared ? const Color(0xFF1F7A66) : const Color(0xFF8B8194),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: <Widget>[
              TextButton(
                onPressed: () => _openDetail(item),
                child: const Text('Detail'),
              ),
              TextButton(
                key: Key('therapy-delete-${item.id}'),
                onPressed: () => unawaited(_delete(item)),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ];
      }).toList(growable: false),
    );
  }

  /// Cuplikan jawaban pertama (untuk submission tanpa `summary`).
  String _firstAnswerPreview(BackendTherapySubmission item) {
    final entries = therapyAnswerEntries(
      moduleId: item.moduleId,
      answers: item.answers,
    );
    if (entries.isEmpty) return '—';
    return entries.first.answer.replaceAll('\n', ' · ');
  }
}

/// Dialog detail worksheet (read-only) + unduh ringkasan.
class _WebTherapyDetailDialog extends StatelessWidget {
  const _WebTherapyDetailDialog({required this.item, required this.onDownload});

  final BackendTherapySubmission item;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final module = webTherapyModuleById(item.moduleId);
    final entries = therapyAnswerEntries(
      moduleId: item.moduleId,
      answers: item.answers,
    );
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      module?.title ?? item.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'Disimpan ${formatWibDateTimeOrDash(parseWibStored(item.createdAt))} WIB',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B6377),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (item.summary.isNotEmpty) ...<Widget>[
                        const WebSectionTitle(text: 'RINGKASAN'),
                        const SizedBox(height: 6),
                        Text(
                          item.summary,
                          style: const TextStyle(fontSize: 12.5, height: 1.5),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (entries.isEmpty)
                        const Text(
                          'Worksheet ini belum berisi jawaban.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF8B8194),
                          ),
                        )
                      else
                        ...entries.map(
                          (TherapyAnswerEntry entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  entry.label,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF6B6377),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  entry.answer,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton.icon(
                    key: const Key('web-therapy-detail-download'),
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded, size: 17),
                    label: const Text('Unduh ringkasan'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
