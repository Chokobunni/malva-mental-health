import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/assessment_reference.dart';
import '../widgets/malva_components.dart';
import '../widgets/therapy_library.dart';
import 'assessment_history_screen.dart';
import 'assessment_screen.dart';

class AssessmentListScreen extends StatefulWidget {
  const AssessmentListScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  State<AssessmentListScreen> createState() => _AssessmentListScreenState();
}

class _AssessmentListScreenState extends State<AssessmentListScreen> {
  int _historyRevision = 0;

  Future<void> _openAssessment(AssessmentInstrument instrument) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => switch (instrument) {
        AssessmentInstrument.who5 =>
          const TherapyDetailScreen(module: who5Module),
        AssessmentInstrument.phqGad => AssessmentScreen(
            session: widget.session, apiClient: widget.apiClient),
        AssessmentInstrument.dass21 =>
          const TherapyDetailScreen(module: dass21Module),
      },
    ));
    if (mounted) setState(() => _historyRevision++);
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => const AssessmentHistoryScreen(),
    ));
    if (mounted) setState(() => _historyRevision++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f7f9),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xff643e88),
                  Color(0xffa262c1),
                  Color(0xffd588ed)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                    color: Color(0x20645278),
                    blurRadius: 14,
                    offset: Offset(0, 5)),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    IconButton.filledTonal(
                      tooltip: 'Kembali',
                      onPressed: () => Navigator.maybePop(context),
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.white24,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 12),
                    const Spacer(),
                    Flexible(
                        flex: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            child: Text('KESEHATAN MENTAL',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        )),
                  ]),
                  const SizedBox(height: 17),
                  const Text('Asesmen Mandiri',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text(
                    'Pahami kondisi emosionalmu lebih baik. Pilih instrumen skrining yang sesuai dengan kebutuhanmu saat ini.',
                    style: TextStyle(
                        color: Colors.white, fontSize: 14, height: 1.55),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 17, 17, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel('Pilih Skrining',
                    action: Text(
                      '${AssessmentInstrument.values.length} Tersedia',
                      style: const TextStyle(color: Color(0xff687581)),
                    )),
                for (final instrument in AssessmentInstrument.values) ...[
                  AssessmentChoiceCard(
                      instrument: instrument,
                      onTap: () => _openAssessment(instrument)),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xfffcf8e9),
                    border: Border.all(color: const Color(0xfff3e7ac)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: Color(0xfff8edbd),
                        foregroundColor: Color(0xff91601c),
                        radius: 13,
                        child: Icon(Icons.info_outline_rounded, size: 16),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                          child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                    text:
                                        'Skor asesmen merupakan alat bantu skrining awal, '),
                                TextSpan(
                                    text: 'bukan diagnosis medis.',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800)),
                                TextSpan(
                                    text:
                                        ' Diagnosis hanya dapat diberikan oleh profesional terverifikasi setelah sesi konsultasi.'),
                              ]),
                              style: TextStyle(
                                  color: Color(0xff704820),
                                  fontSize: 13,
                                  height: 1.5))),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                SectionLabel(
                  'Riwayat Asesmen',
                  action: TextButton(
                    onPressed: _openHistory,
                    style:
                        TextButton.styleFrom(foregroundColor: MalvaColors.plum),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Lihat semua'),
                      SizedBox(width: 5),
                      Icon(Icons.arrow_forward_rounded, size: 16),
                    ]),
                  ),
                ),
                AssessmentHistoryPreview(key: ValueKey(_historyRevision)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
