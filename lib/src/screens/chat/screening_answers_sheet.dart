import 'package:flutter/material.dart';

import '../../ai/assessment_scoring.dart';
import '../../assessment_engine.dart';
import '../../widgets/therapy_library.dart'
    show dass21WorksheetFields, who5WorksheetFields;

const _dassDisplayLabels = <int, String>{
  2: 'Saya merasa mulut saya kering',
  4: 'Saya mengalami kesulitan bernapas (misalnya napas cepat atau terengah-engah tanpa aktivitas fisik)',
  5: 'Saya merasa sulit untuk berinisiatif melakukan sesuatu',
  6: 'Saya cenderung bereaksi berlebihan terhadap suatu situasi',
  7: 'Saya mengalami gemetar (misalnya pada tangan)',
  8: 'Saya merasa menggunakan banyak energi untuk cemas',
  9: 'Saya khawatir dengan situasi di mana saya mungkin panik dan mempermalukan diri sendiri',
  10: 'Saya merasa tidak ada hal yang dapat diharapkan di masa depan',
  11: 'Saya merasa mudah gelisah',
  12: 'Saya merasa sulit untuk bersantai',
  14: 'Saya tidak dapat memaklumi hal apa pun yang menghalangi saya menyelesaikan pekerjaan',
  16: 'Saya tidak bisa merasa antusias terhadap hal apa pun',
  17: 'Saya merasa tidak berharga sebagai seorang manusia',
  19: 'Saya merasakan perubahan detak jantung meskipun tidak melakukan aktivitas fisik',
  21: 'Saya merasa hidup ini tidak berarti',
};

int? _validAnswer(dynamic value, int maximum) => value is num &&
        value.isFinite &&
        value == value.roundToDouble() &&
        value >= 0 &&
        value <= maximum
    ? value.toInt()
    : null;

class ScreeningAnswer {
  const ScreeningAnswer(this.number, this.label, this.group, this.value,
      {this.safety = false});
  final int number;
  final String label;
  final String group;
  final int? value;
  final bool safety;
}

List<ScreeningAnswer> worksheetScreeningAnswers(
    String module, Map<String, dynamic> answers) {
  final fields = module == 'who5' ? who5WorksheetFields : dass21WorksheetFields;
  return [
    for (var i = 0; i < fields.length; i++)
      ScreeningAnswer(
        i + 1,
        module == 'dass21'
            ? (_dassDisplayLabels[i + 1] ?? fields[i].label)
            : fields[i].label,
        module == 'who5'
            ? 'WHO-5'
            : dassDepressionItems.contains(i + 1)
                ? 'Depresi'
                : dassAnxietyItems.contains(i + 1)
                    ? 'Kecemasan'
                    : 'Stres',
        _validAnswer(answers[fields[i].id], module == 'who5' ? 5 : 3),
      ),
  ];
}

List<ScreeningAnswer> clinicalScreeningAnswers(
        Map<String, int> phq, Map<String, int> gad) =>
    [
      for (final type in AssessmentType.values)
        for (var i = 0; i < AssessmentEngine.questionsFor(type).length; i++)
          ScreeningAnswer(
            i + 1,
            AssessmentEngine.questionsFor(type)[i].label,
            type == AssessmentType.phq9 ? 'PHQ-9' : 'GAD-7',
            (type == AssessmentType.phq9
                ? phq
                : gad)[AssessmentEngine.questionsFor(type)[i].id],
            safety: type == AssessmentType.phq9 &&
                i == 8 &&
                (phq['phq_self_harm'] ?? 0) > 0,
          ),
    ];

class ScreeningAnswersSheet extends StatefulWidget {
  const ScreeningAnswersSheet(
      {super.key,
      required this.module,
      required this.subtitle,
      required this.answers,
      this.badge = ''});
  final String module;
  final String subtitle;
  final String badge;
  final List<ScreeningAnswer> answers;

  @override
  State<ScreeningAnswersSheet> createState() => _ScreeningAnswersSheetState();
}

class _ScreeningAnswersSheetState extends State<ScreeningAnswersSheet> {
  String _filter = 'Semua';
  bool _highest = false;
  static const _purple = Color(0xff812b98);
  static const _green = Color(0xff05966e);
  static const _ink = Color(0xff202b39);
  bool get _who => widget.module == 'who5';
  bool get _dass => widget.module == 'dass21';

  Color _tone(String group) => switch (group) {
        'GAD-7' || 'Stres' => _green,
        'Kecemasan' => const Color(0xffcc7a00),
        _ => _purple,
      };

  Widget _pill(String text, Color color,
          {bool selected = false, bool compact = false}) =>
      Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 10, vertical: compact ? 3 : 7),
        decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(compact ? 6 : 24),
            border: Border.all(color: color.withValues(alpha: .15))),
        child: Text(text,
            maxLines: 1,
            style: TextStyle(
                color: selected ? Colors.white : color,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    final groups = _dass
        ? ['Semua', 'Depresi', 'Kecemasan', 'Stres']
        : ['Semua', 'PHQ-9', 'GAD-7'];
    var shown = widget.answers
        .where((a) => _filter == 'Semua' || a.group == _filter)
        .toList();
    if (_highest && shown.any((a) => a.value != null)) {
      final max = shown
          .where((a) => a.value != null)
          .map((a) => a.value!)
          .reduce((a, b) => a > b ? a : b);
      shown = shown.where((a) => a.value == max).toList();
    }
    final title = _who
        ? 'Rincian Jawaban WHO-5'
        : _dass
            ? 'Rincian Jawaban DASS-21'
            : 'Rincian PHQ-9 & GAD-7';
    return SafeArea(
        top: false,
        child: ColoredBox(
            color: Colors.white,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .92),
              child: Column(
                  mainAxisSize: _who ? MainAxisSize.min : MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(top: 10, bottom: 16),
                            decoration: BoxDecoration(
                                color: const Color(0xffcbd5df),
                                borderRadius: BorderRadius.circular(4)))),
                    Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 12, 14),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Flexible(
                                      child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 18,
                                                  color: _ink)))),
                                  if (widget.badge.isNotEmpty) ...[
                                    const SizedBox(width: 7),
                                    _pill(
                                        widget.badge,
                                        _who
                                            ? _green
                                            : widget.badge
                                                    .startsWith('Keselamatan')
                                                ? const Color(0xffb4232a)
                                                : _purple),
                                  ],
                                ]),
                                const SizedBox(height: 5),
                                Text(widget.subtitle,
                                    style: const TextStyle(
                                        color: Color(0xff697787),
                                        fontSize: 12,
                                        height: 1.5)),
                              ])),
                          IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                              style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xfff1f4f8))),
                        ])),
                    const Divider(height: 1),
                    if (!_who)
                      Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(children: [
                            Row(children: [
                              for (var i = 0; i < groups.length; i++) ...[
                                if (i > 0) const SizedBox(width: 5),
                                Expanded(
                                    flex: groups[i] == 'Kecemasan' ||
                                            groups[i] == 'GAD-7'
                                        ? 12
                                        : 10,
                                    child: InkWell(
                                        onTap: () =>
                                            setState(() => _filter = groups[i]),
                                        borderRadius: BorderRadius.circular(24),
                                        child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: _pill(
                                                '${groups[i] == 'PHQ-9' ? 'PHQ-9 Depresi' : groups[i] == 'GAD-7' ? 'GAD-7 Kecemasan' : groups[i]} (${groups[i] == 'Semua' ? widget.answers.length : widget.answers.where((a) => a.group == groups[i]).length})',
                                                groups[i] == 'Semua'
                                                    ? _filter == 'Semua'
                                                        ? _purple
                                                        : const Color(
                                                            0xff596575)
                                                    : _tone(groups[i]),
                                                selected:
                                                    _filter == groups[i])))),
                              ]
                            ]),
                            const SizedBox(height: 10),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: Text(
                                          _dass
                                              ? 'Skala: 0 Tidak sesuai • 1 Kadang • 2 Sering • 3 Sangat sering'
                                              : 'Skala 2 minggu terakhir: 0 Tidak sama sekali • 1 Beberapa hari • 2 > separuh hari • 3 Hampir setiap hari',
                                          style: const TextStyle(
                                              color: Color(0xff697787),
                                              fontSize: 11,
                                              height: 1.5))),
                                  if (_dass)
                                    Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                              width: 26,
                                              height: 26,
                                              child: Checkbox(
                                                  value: _highest,
                                                  onChanged: (v) => setState(
                                                      () => _highest =
                                                          v ?? false),
                                                  activeColor: _purple)),
                                          const Text('Skor tertinggi',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: _purple)),
                                        ]),
                                ]),
                          ])),
                    Flexible(
                        fit: _who ? FlexFit.loose : FlexFit.tight,
                        child: ColoredBox(
                            color: const Color(0xfffaf7fc),
                            child: ListView(
                                shrinkWrap: _who,
                                padding: const EdgeInsets.all(15),
                                children: [
                                  if (_who)
                                    _box(
                                        child: const Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Expanded(
                                              child: Text(
                                                  '0: Tidak pernah\n1: Jarang\n2: < setengah waktu',
                                                  style: TextStyle(
                                                      height: 2,
                                                      color: Color(0xff697787),
                                                      fontSize: 12))),
                                          Expanded(
                                              child: Text(
                                                  '3: > setengah waktu\n4: Sebagian besar\n5: Selalu',
                                                  style: TextStyle(
                                                      height: 2,
                                                      color: Color(0xff697787),
                                                      fontSize: 12))),
                                        ])),
                                  for (final answer in shown) _answer(answer),
                                ]))),
                    Padding(
                        padding: const EdgeInsets.all(13),
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                              backgroundColor: _purple,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14))),
                          child: const Text('Tutup Rincian',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        )),
                  ]),
            )));
  }

  Widget _box({required Widget child, bool safety = false}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: safety ? const Color(0xfffff5f5) : Colors.white,
            border: Border.all(
                color:
                    safety ? const Color(0xffefa5a8) : const Color(0xffe7e8ed)),
            borderRadius: BorderRadius.circular(17)),
        child: child,
      );

  Widget _answer(ScreeningAnswer answer) {
    final groupTone = _tone(answer.group);
    final tone = answer.group == 'GAD-7' ? _green : _purple;
    final numberTone = _who
        ? _green
        : _dass
            ? const Color(0xff465363)
            : groupTone;
    final value = answer.value;
    final choices = _who
        ? [
            'Tidak pernah',
            'Jarang',
            '< ½ waktu',
            '> ½ waktu',
            'Sebagian besar',
            'Selalu'
          ]
        : _dass
            ? ['Tidak sesuai', 'Kadang-kadang', 'Sering', 'Sangat sering']
            : [
                'Tidak sama sekali',
                'Beberapa hari',
                '> separuh hari',
                'Hampir setiap hari'
              ];
    final label = value != null && value >= 0 && value < choices.length
        ? '$value • ${choices[value]}'
        : 'Belum tersedia';
    return _box(
        safety: answer.safety,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 13,
              backgroundColor: numberTone.withValues(alpha: .08),
              child: Text('${answer.number}',
                  style: TextStyle(
                      fontSize: 12,
                      color: numberTone,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(answer.label,
                    style: const TextStyle(
                        color: _ink, fontSize: 13, height: 1.45)),
                if (!_who) ...[
                  const SizedBox(height: 6),
                  _pill(answer.group, groupTone, compact: true)
                ],
                if (answer.safety) ...[
                  const SizedBox(height: 7),
                  _pill('Pemicu Indikator Keselamatan', Colors.red,
                      compact: true)
                ],
              ])),
          const SizedBox(width: 8),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 125),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                    color: answer.safety
                        ? const Color(0xffdc2626)
                        : value != null && (value >= 2 || _who)
                            ? tone
                            : tone.withValues(alpha: value == 0 ? .03 : .08),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: answer.safety ||
                                value != null && (value >= 2 || _who)
                            ? Colors.white
                            : value == 0
                                ? const Color(0xff697787)
                                : tone)),
              )),
        ]));
  }
}
