import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../../../time/wib.dart';
import '../../services/web_assessment_service.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// Tampilan hasil satu sesi asesmen web.
///
/// Hasil SELALU ditampilkan walau penyimpanan ke server gagal — kegagalan
/// hanya menambah banner "Hasil belum terkirim ke server" beserta tombol coba
/// lagi, bukan menghilangkan skor yang sudah dihitung.
class WebAssessmentResultView extends StatelessWidget {
  const WebAssessmentResultView({
    super.key,
    required this.outcome,
    required this.saved,
    this.saveError,
    this.onRetrySave,
    required this.onRepeat,
    required this.onOpenHistory,
    this.onShare,
    this.shareNote,
  });

  final WebAssessmentOutcome outcome;

  /// True bila hasil sudah tersimpan di server.
  final bool saved;

  /// Pesan ramah bila penyimpanan gagal.
  final String? saveError;
  final VoidCallback? onRetrySave;
  final VoidCallback onRepeat;
  final VoidCallback onOpenHistory;

  /// Null bila instrumen tidak bisa dibagikan atau belum tersimpan.
  final VoidCallback? onShare;

  /// Keterangan tambahan setelah aksi bagikan (mis. "Sudah dibagikan").
  final String? shareNote;

  @override
  Widget build(BuildContext context) {
    final saveErrorText = saveError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Hasil ${outcome.instrument.title}',
          subtitle: 'Dihitung ${formatWibDateTime(outcome.createdAt)} WIB · '
              'mesin Forward Chaining + Certainty Factor',
        ),
        const SizedBox(height: WebSpacing.section),
        if (outcome.crisisFlag) ...<Widget>[
          _CrisisBanner(instrument: outcome.instrument),
          const SizedBox(height: 16),
        ],
        _TriageCard(outcome: outcome),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final columns = constraints.maxWidth >= 900
                ? outcome.cards.length.clamp(1, 3)
                : (constraints.maxWidth >= 600 ? 2 : 1);
            final width =
                (constraints.maxWidth - WebSpacing.cardGap * (columns - 1)) /
                    columns;
            return Wrap(
              spacing: WebSpacing.cardGap,
              runSpacing: WebSpacing.cardGap,
              children: outcome.cards
                  .map(
                    (WebAssessmentScoreCard card) => SizedBox(
                      width: width,
                      child: _ScoreCard(card: card),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
        if (outcome.reasons.isNotEmpty) ...<Widget>[
          const SizedBox(height: WebSpacing.section),
          const WebSectionTitle(text: 'ALASAN / RULE YANG MENEMBAK'),
          const SizedBox(height: 10),
          WebAdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: outcome.reasons
                  .map(
                    (String reason) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Padding(
                            padding: EdgeInsets.only(top: 3),
                            child: Icon(Icons.chevron_right_rounded,
                                size: 16, color: MalvaColors.seed),
                          ),
                          Expanded(
                            child: Text(
                              reason,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
        const SizedBox(height: WebSpacing.section),
        if (saveErrorText != null)
          _SaveErrorBanner(message: saveErrorText, onRetry: onRetrySave)
        else if (saved)
          const _SavedBanner()
        else
          const _SavingBanner(),
        const SizedBox(height: WebSpacing.section),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            FilledButton.icon(
              key: const Key('web-result-repeat'),
              onPressed: onRepeat,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Ulangi'),
            ),
            OutlinedButton.icon(
              key: const Key('web-result-history'),
              onPressed: onOpenHistory,
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('Lihat riwayat'),
            ),
            if (onShare != null)
              OutlinedButton.icon(
                key: const Key('web-result-share'),
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Bagikan ke profesional'),
              ),
          ],
        ),
        if (shareNote != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            shareNote!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F7A66),
            ),
          ),
        ],
      ],
    );
  }
}

class _TriageCard extends StatelessWidget {
  const _TriageCard({required this.outcome});

  final WebAssessmentOutcome outcome;

  @override
  Widget build(BuildContext context) {
    return WebAdminCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _levelColor(outcome.triageLabel).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              outcome.crisisFlag
                  ? Icons.health_and_safety_rounded
                  : Icons.insights_rounded,
              color: _levelColor(outcome.triageLabel),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'TINGKAT TRIAGE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: Color(0xFF8B8194),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Text(
                      outcome.triageLabel,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 10),
                    WebStatusPill(
                      label: 'CF ${outcome.certaintyPercent}%',
                      color: _levelColor(outcome.triageLabel),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  outcome.summaryText,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Color(0xFF6B6377),
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

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.card});

  final WebAssessmentScoreCard card;

  @override
  Widget build(BuildContext context) {
    final note = card.note;
    return WebAdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            card.title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B6377),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                card.scoreText,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: WebStatusPill(
                  label: card.level,
                  color: _levelColor(card.level),
                ),
              ),
            ],
          ),
          if (card.certaintyPercent != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Keyakinan mesin: ${card.certaintyPercent}%',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
            ),
          ],
          if (note != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              note,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Color(0xFF6B6377),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CrisisBanner extends StatelessWidget {
  const _CrisisBanner({required this.instrument});

  final WebAssessmentInstrument instrument;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('web-assessment-crisis'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MalvaColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        border: Border.all(color: MalvaColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded,
              color: MalvaColors.danger, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Perlu perhatian segera',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: MalvaColors.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Jawaban Anda memuat indikator keselamatan diri. Bila Anda '
                  'berpikir untuk menyakiti diri, segera hubungi layanan '
                  'darurat (119) atau orang terdekat. Hasil ini sebaiknya '
                  'ditinjau profesional.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: MalvaColors.danger.withValues(alpha: 0.95),
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

class _SavedBanner extends StatelessWidget {
  const _SavedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('web-assessment-saved'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MalvaColors.mint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.cloud_done_rounded, size: 18, color: MalvaColors.mint),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hasil tersimpan di riwayat dan bisa dilihat profesional yang '
              'terhubung dengan Anda.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F7A66),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavingBanner extends StatelessWidget {
  const _SavingBanner();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text(
          'Menyimpan hasil ke server...',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF6B6377)),
        ),
      ],
    );
  }
}

class _SaveErrorBanner extends StatelessWidget {
  const _SaveErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('web-assessment-save-error'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MalvaColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MalvaColors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.cloud_off_rounded,
              size: 18, color: Color(0xFF8A5A00)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Hasil belum terkirim ke server',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A5A00),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(fontSize: 12, height: 1.45),
                ),
                const SizedBox(height: 6),
                Text(
                  'Skor di atas tetap sah dan bisa dicatat manual. Coba kirim '
                  'ulang saat koneksi membaik.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: const Color(0xFF8A5A00).withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('web-assessment-retry-save'),
              onPressed: onRetry,
              child: const Text('Kirim ulang'),
            ),
          ],
        ],
      ),
    );
  }
}

Color _levelColor(String label) => switch (label.toLowerCase()) {
      'minimal' || 'normal' || 'baik' => MalvaColors.mint,
      'ringan' || 'cukup' => const Color(0xFF6CBF57),
      'sedang' => MalvaColors.amber,
      'cukup berat' => const Color(0xFFE8873C),
      'berat' || 'sangat berat' || 'sangat rendah' => MalvaColors.danger,
      'krisis' => const Color(0xFFB00020),
      'rendah' => MalvaColors.amber,
      'tinggi' => const Color(0xFFE8873C),
      _ => MalvaColors.seed,
    };
