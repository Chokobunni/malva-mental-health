import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../services/web_assessment_service.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// Riwayat asesmen web: gabungan screening (PHQ-9 + GAD-7) dan therapy
/// submission (DASS-21 / WHO-5), dengan filter instrumen dan dialog detail.
class WebAssessmentHistoryView extends StatefulWidget {
  const WebAssessmentHistoryView({
    super.key,
    required this.entries,
    required this.loading,
    required this.onRefresh,
    required this.onBack,
    this.error,
  });

  final List<WebAssessmentHistoryEntry> entries;
  final bool loading;
  final Object? error;
  final VoidCallback onRefresh;
  final VoidCallback onBack;

  @override
  State<WebAssessmentHistoryView> createState() =>
      _WebAssessmentHistoryViewState();
}

class _WebAssessmentHistoryViewState extends State<WebAssessmentHistoryView> {
  /// `null` = semua instrumen.
  WebAssessmentInstrument? _filter;

  List<WebAssessmentHistoryEntry> get _filtered {
    final filter = _filter;
    if (filter == null) return widget.entries;
    return widget.entries
        .where((WebAssessmentHistoryEntry entry) => entry.instrument == filter)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Riwayat asesmen',
          subtitle: 'Semua hasil asesmen Anda dalam WIB, terbaru di atas.',
          trailing: Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: widget.loading ? null : widget.onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Muat ulang'),
              ),
              TextButton(
                key: const Key('web-history-back'),
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
              width: 220,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Instrumen',
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<WebAssessmentInstrument?>(
                    key: const Key('web-history-filter'),
                    value: _filter,
                    isExpanded: true,
                    isDense: true,
                    items: const <DropdownMenuItem<WebAssessmentInstrument?>>[
                      DropdownMenuItem<WebAssessmentInstrument?>(
                        value: null,
                        child: Text('Semua instrumen'),
                      ),
                      DropdownMenuItem<WebAssessmentInstrument?>(
                        value: WebAssessmentInstrument.screening,
                        child: Text('PHQ-9 + GAD-7'),
                      ),
                      DropdownMenuItem<WebAssessmentInstrument?>(
                        value: WebAssessmentInstrument.dass21,
                        child: Text('DASS-21'),
                      ),
                      DropdownMenuItem<WebAssessmentInstrument?>(
                        value: WebAssessmentInstrument.who5,
                        child: Text('WHO-5'),
                      ),
                    ],
                    onChanged: (WebAssessmentInstrument? value) =>
                        setState(() => _filter = value),
                  ),
                ),
              ),
            ),
            Text(
              '${_filtered.length} hasil',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildBody(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (widget.loading) {
      return const WebAdminLoading(label: 'Memuat riwayat...');
    }
    if (widget.error != null) {
      return WebAdminError(error: widget.error!, onRetry: widget.onRefresh);
    }
    final entries = _filtered;
    return WebAdminTable(
      minWidth: 1120,
      emptyMessage: 'Belum ada hasil asesmen pada filter ini.',
      columns: const <WebAdminColumn>[
        WebAdminColumn('TANGGAL (WIB)', 160),
        WebAdminColumn('INSTRUMEN', 170),
        WebAdminColumn('SKOR', 280),
        WebAdminColumn('LEVEL', 130),
        WebAdminColumn('CF', 80),
        WebAdminColumn('DIBAGIKAN', 130),
        WebAdminColumn('', 100, align: Alignment.centerRight),
      ],
      rowKeyBuilder: (int index) => Key('history-row-${entries[index].id}'),
      rows: entries
          .map(
            (WebAssessmentHistoryEntry entry) => <Widget>[
              Text(
                formatWibDateTimeOrDash(entry.createdAt),
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                entry.instrument.shortTitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                entry.scoreText,
                style: const TextStyle(fontSize: 12),
              ),
              WebStatusPill(
                label: entry.level,
                color: entry.level.toLowerCase() == 'krisis'
                    ? MalvaColors.danger
                    : MalvaColors.seed,
              ),
              Text(
                '${entry.certaintyPercent}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                entry.shared ? 'Sudah' : 'Belum',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: entry.shared
                      ? const Color(0xFF1F7A66)
                      : const Color(0xFF8B8194),
                ),
              ),
              TextButton(
                onPressed: () => _openDetail(entry),
                child: const Text('Detail'),
              ),
            ],
          )
          .toList(growable: false),
    );
  }

  void _openDetail(WebAssessmentHistoryEntry entry) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _WebHistoryDetailDialog(entry: entry),
    );
  }
}

class _WebHistoryDetailDialog extends StatelessWidget {
  const _WebHistoryDetailDialog({required this.entry});

  final WebAssessmentHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 560,
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
                      '${entry.instrument.shortTitle} · '
                      '${formatWibDateTimeOrDash(entry.createdAt)}',
                      style: const TextStyle(
                        fontSize: 15,
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
              const SizedBox(height: 10),
              _DetailRow(label: 'Skor', value: entry.scoreText),
              _DetailRow(label: 'Level', value: entry.level),
              _DetailRow(
                label: 'Keyakinan (CF)',
                value: '${entry.certaintyPercent}%',
              ),
              _DetailRow(
                label: 'Sumber',
                value: entry.isScreening
                    ? 'POST /v1/screenings'
                    : 'Therapy submission',
              ),
              _DetailRow(
                label: 'Dibagikan',
                value: entry.shared ? 'Sudah dibagikan' : 'Belum dibagikan',
              ),
              if (entry.reasons.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                const Text(
                  'ALASAN / RULE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Color(0xFF8B8194),
                  ),
                ),
                const SizedBox(height: 6),
                ...entry.reasons.map(
                  (String reason) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• $reason',
                      style: const TextStyle(fontSize: 12, height: 1.45),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8B8194),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
