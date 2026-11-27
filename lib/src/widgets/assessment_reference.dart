import 'package:flutter/material.dart';

enum AssessmentInstrument {
  who5(
      'who5',
      'WHO-5 (Indeks Kesejahteraan)',
      'Mengukur tingkat kesejahteraan psikologis dalam 2 minggu terakhir (skala 0–5).',
      5,
      'who5.png',
      Color(0xff087d5c),
      Color(0xffe7f8f0)),
  phqGad(
      'screening',
      'PHQ-9 + GAD-7',
      'Skrining komprehensif untuk gejala depresi & kecemasan dalam 2 minggu terakhir.',
      16,
      'phq_gad.png',
      Color(0xff77399a),
      Color(0xfff4e8fb)),
  dass21(
      'dass21',
      'DASS-21 (Depresi, Kecemasan, Stres)',
      'Evaluasi tingkat depresi, kecemasan, dan stres selama 1 minggu terakhir (skala 0–3).',
      21,
      'dass21.png',
      Color(0xff245bb0),
      Color(0xffe8f1fd));

  const AssessmentInstrument(this.id, this.title, this.description,
      this.questionCount, this.asset, this.color, this.tint);
  final String id;
  final String title;
  final String description;
  final int questionCount;
  final String asset;
  final Color color;
  final Color tint;

  static AssessmentInstrument? fromId(String id) {
    for (final instrument in values) {
      if (instrument.id == id) return instrument;
    }
    return null;
  }

  Widget icon(double size) => Image.asset('assets/reference/$asset',
      width: size, height: size, excludeFromSemantics: true);
}

class AssessmentChoiceCard extends StatelessWidget {
  const AssessmentChoiceCard({
    super.key,
    required this.instrument,
    required this.onTap,
  });

  final AssessmentInstrument instrument;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xffedf0f3)),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              instrument.icon(45),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(instrument.title,
                        style: const TextStyle(
                            color: Color(0xff141b28),
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text(instrument.description,
                        style: const TextStyle(
                            color: Color(0xff647180),
                            fontSize: 13,
                            height: 1.45)),
                    const SizedBox(height: 9),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xffeef1f5),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.checklist_rounded,
                                size: 14, color: Color(0xff526171)),
                            const SizedBox(width: 4),
                            Flexible(
                                child: Text('${instrument.questionCount} Soal',
                                    style: const TextStyle(
                                        color: Color(0xff526171),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(top: 28),
                child:
                    Icon(Icons.chevron_right_rounded, color: Color(0xff98a4b0)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
