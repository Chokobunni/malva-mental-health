part of 'therapy_library.dart';

const _recordInk = Color(0xff202a38);
const _recordMuted = Color(0xff98a5b4);
const _recordTeal = Color(0xff17877e);

class _TherapySubmissionSheet extends StatelessWidget {
  const _TherapySubmissionSheet({required this.view});
  final TherapySubmissionView view;

  @override
  Widget build(BuildContext context) {
    final module = findTherapyModuleById(view.moduleId);
    final fields = module?.worksheetFields ?? const <TherapyWorksheetField>[];
    final filled =
        fields.where((f) => _recordHasAnswer(view.answers[f.id])).length;
    final extra =
        therapyAnswerEntries(moduleId: view.moduleId, answers: view.answers)
            .skip(fields.length);
    final title = view.title;
    final split = title.indexOf(' (');
    final at = view.createdAt == null ? null : toWib(view.createdAt!);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                  child: Container(
                      width: 38,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                          color: const Color(0xffe0e6ed),
                          borderRadius: BorderRadius.circular(5)))),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: const Color(0xffeafcf4),
                      border: Border.all(color: const Color(0xffc4eddd)),
                      borderRadius: BorderRadius.circular(30)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_outline_rounded,
                        color: _recordTeal, size: 17),
                    SizedBox(width: 5),
                    Text('Tersimpan',
                        style: TextStyle(
                            color: _recordTeal, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(width: 9),
                if (at != null)
                  Expanded(
                      child: Row(children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: _recordMuted),
                    const SizedBox(width: 5),
                    Flexible(
                        child: Text(
                            '${at.day} ${months[at.month - 1]} ${at.year} • ${formatWibBubbleTime(at)}',
                            style: const TextStyle(
                                color: _recordMuted, fontSize: 12))),
                  ]))
                else
                  const Spacer(),
                IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: _recordMuted)),
              ]),
              const SizedBox(height: 10),
              Text(split < 0 ? title : title.substring(0, split),
                  style: const TextStyle(
                      color: Color(0xff111927),
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      height: 1.25)),
              if (split >= 0)
                Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(title.substring(split + 1),
                        style: const TextStyle(
                            color: Color(0xff687687), fontSize: 16))),
            ]),
          ),
          const Divider(height: 1, color: Color(0xfff0f2f5)),
          Flexible(
              child: ColoredBox(
            color: const Color(0xfffafbfd),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.description_outlined,
                          color: _recordTeal, size: 19),
                      const SizedBox(width: 6),
                      const Expanded(
                          child: Text('DETAIL JAWABAN SESI',
                              style: TextStyle(
                                  color: _recordMuted,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12))),
                      if (fields.isNotEmpty)
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                                color: const Color(0xfff0fbf7),
                                border:
                                    Border.all(color: const Color(0xffe1e9e6)),
                                borderRadius: BorderRadius.circular(18)),
                            child: Text('$filled/${fields.length} Terisi',
                                style: const TextStyle(
                                    color: Color(0xff18766f),
                                    fontWeight: FontWeight.w800))),
                    ]),
                    const SizedBox(height: 20),
                    if (module == null && view.summary.trim().isNotEmpty)
                      _TherapyAnswerCard(
                        field: const TherapyWorksheetField(
                            id: 'summary', label: 'Catatan tersimpan'),
                        answer: view.summary,
                      ),
                    for (final field in fields)
                      _TherapyAnswerCard(
                          field: field, answer: view.answers[field.id]),
                    for (final entry in extra)
                      _TherapyAnswerCard(
                          field: TherapyWorksheetField(
                              id: entry.label, label: entry.label),
                          answer: entry.answer),
                  ]),
            ),
          )),
          const Divider(height: 1, color: Color(0xfff0f2f5)),
          Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
              child: Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor: const Color(0xff354353),
                            side: const BorderSide(color: Color(0xffe0e5eb)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        onPressed: () async {
                          final text = [
                            view.title,
                            for (final entry in therapyAnswerEntries(
                                moduleId: view.moduleId, answers: view.answers))
                              '${entry.label}\n${entry.answer}',
                          ].join('\n\n');
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Catatan disalin.')));
                        },
                        icon: const Icon(Icons.copy_outlined, size: 20),
                        label: const Text('Salin Catatan'))),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xff11968b),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Selesai',
                            style: TextStyle(
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.w800)))),
              ])),
        ]);
  }
}

bool _recordHasAnswer(Object? answer) {
  if (answer == null) return false;
  if (answer is String) return answer.trim().isNotEmpty;
  if (answer is List) return answer.any(_recordHasAnswer);
  if (answer is Map) return answer.values.any(_recordHasAnswer);
  return true;
}

class _TherapyAnswerCard extends StatelessWidget {
  const _TherapyAnswerCard({required this.field, required this.answer});
  final TherapyWorksheetField field;
  final Object? answer;

  Widget _panel(Widget child,
          {Color color = const Color(0xfff7f8fa),
          Color border = const Color(0xfff0f2f5)}) =>
      Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: color,
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(12)),
          child: child);

  Widget _text(String text) => SelectableText(text,
      style:
          const TextStyle(color: Color(0xff384555), fontSize: 14, height: 1.4));

  Widget _empty() => CustomPaint(
      foregroundPainter: const _UnansweredBorderPainter(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: const Color(0xfffafbfd),
            borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.remove_circle_outline_rounded,
              size: 17, color: _recordMuted),
          SizedBox(width: 7),
          Expanded(
              child: Text('Belum dijawab pada sesi ini',
                  style: TextStyle(
                      color: _recordMuted,
                      fontStyle: FontStyle.italic,
                      fontSize: 13))),
        ]),
      ));

  Widget _content() {
    if (!_recordHasAnswer(answer)) return _empty();
    if (field.kind == TherapyFieldKind.beforeAfter && answer is Map) {
      final values = answer as Map;
      final before = values['before'];
      final after = values['after'];
      final delta = before is num && after is num ? before - after : null;
      final change = delta == null
          ? 'Skala 0–10'
          : delta > 0
              ? 'Turun ${delta.toInt()} poin'
              : delta < 0
                  ? 'Naik ${-delta.toInt()} poin'
                  : 'Tetap';
      Widget value(
              String label, Object? number, String caption, bool isAfter) =>
          Expanded(
              child: _panel(
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(label,
                              style: TextStyle(
                                  color: isAfter
                                      ? _recordTeal
                                      : const Color(0xffa15b17),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12)),
                          const SizedBox(height: 5),
                          Text(caption,
                              style: TextStyle(
                                  color: isAfter
                                      ? _recordTeal
                                      : const Color(0xffc79347),
                                  fontSize: 12)),
                        ])),
                    Text(number?.toString() ?? '—',
                        style: TextStyle(
                            fontSize: 25,
                            color: isAfter
                                ? const Color(0xff095c49)
                                : const Color(0xff85460f),
                            fontWeight: FontWeight.w800)),
                  ]),
                  color: isAfter
                      ? const Color(0xfff0fcf7)
                      : const Color(0xfffffcf1),
                  border: isAfter
                      ? const Color(0xffc7eddf)
                      : const Color(0xfff3e8b4)));
      return Row(children: [
        value('SEBELUM', before, 'Skala 0–10', false),
        const SizedBox(width: 9),
        value('SESUDAH', after, change, true)
      ]);
    }
    if ((field.kind == TherapyFieldKind.choiceMulti ||
        field.kind == TherapyFieldKind.choice)) {
      final choices = answer is List ? answer as List : [answer];
      return Wrap(spacing: 7, runSpacing: 7, children: [
        for (final choice in choices.where(_recordHasAnswer))
          Builder(builder: (_) {
            final trap = field.id == 'trap_type';
            final catastrophic = choice == 'Catastrophizing';
            final tone = trap
                ? catastrophic
                    ? const Color(0xffa96b1a)
                    : const Color(0xff5845a6)
                : _recordTeal;
            return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                    color: trap
                        ? catastrophic
                            ? const Color(0xfffffbe9)
                            : const Color(0xfff0f0ff)
                        : const Color(0xffeffaf6),
                    border: Border.all(
                        color: trap
                            ? catastrophic
                                ? const Color(0xfff1e8b8)
                                : const Color(0xffdce0f7)
                            : const Color(0xffe0e7e5)),
                    borderRadius: BorderRadius.circular(13)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                      trap
                          ? catastrophic
                              ? Icons.warning_amber_rounded
                              : Icons.psychology_outlined
                          : field.id == 'schedule_day'
                              ? Icons.calendar_month_outlined
                              : field.id == 'next_step'
                                  ? Icons.repeat_rounded
                                  : Icons.circle,
                      color: tone,
                      size: trap || field.kind == TherapyFieldKind.choice
                          ? 17
                          : 7),
                  const SizedBox(width: 7),
                  Flexible(
                      child: Text(choice.toString(),
                          style: TextStyle(
                              color: trap ? tone : _recordInk, fontSize: 14))),
                ]));
          }),
      ]);
    }

    if (field.kind == TherapyFieldKind.points && answer is List) {
      final points = answer as List;
      final evidence = field.id == 'evidence';
      return Column(children: [
        for (var i = 0; i < points.length; i++)
          if (_recordHasAnswer(points[i]))
            Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                child: _panel(
                    evidence
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Row(children: [
                                  Icon(
                                      i == 0
                                          ? Icons.thumb_up_outlined
                                          : Icons.verified_user_outlined,
                                      color: i == 0
                                          ? const Color(0xffa22b50)
                                          : const Color(0xff1d7794),
                                      size: 18),
                                  const SizedBox(width: 7),
                                  Expanded(
                                      child: Text(
                                          field
                                                  .effectivePointLabels()
                                                  .elementAtOrNull(i) ??
                                              'Poin ${i + 1}',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: i == 0
                                                  ? const Color(0xffa22b50)
                                                  : const Color(0xff1d7794),
                                              fontSize: 13))),
                                ]),
                                const SizedBox(height: 6),
                                _text(points[i].toString()),
                              ])
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text('${i + 1}.',
                                    style: const TextStyle(
                                        color: _recordMuted, fontSize: 12)),
                                const SizedBox(width: 13),
                                Expanded(child: _text(points[i].toString())),
                              ]),
                    color: evidence
                        ? (i == 0
                            ? const Color(0xfffdf7f8)
                            : const Color(0xfff4fbfd))
                        : const Color(0xfff7f8fa),
                    border: evidence
                        ? (i == 0
                            ? const Color(0xfff5e4e6)
                            : const Color(0xffdfedf2))
                        : const Color(0xfff0f2f5))),
      ]);
    }
    if (field.id == 'cycles' && answer is num) {
      return Align(
          alignment: Alignment.centerLeft,
          child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                  color: const Color(0xfff1fbf7),
                  border: Border.all(color: const Color(0xffe1e8e6)),
                  borderRadius: BorderRadius.circular(14)),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '$answer',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: Color(0xff17796f))),
                const TextSpan(
                    text: '  Siklus 4-2-6',
                    style: TextStyle(color: _recordInk, fontSize: 14)),
              ]))));
    }
    return _panel(_text(_answerText(field, answer) ?? answer.toString()));
  }

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffe6eaee)),
          borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (field.badge.isNotEmpty) ...[
            Container(
                width: 29,
                height: 29,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: const Color(0xffeffbf6),
                    border: Border.all(color: const Color(0xffe1e8e5)),
                    borderRadius: BorderRadius.circular(9)),
                child: Text(field.badge,
                    style: const TextStyle(
                        color: Color(0xff1a766c),
                        fontWeight: FontWeight.w800,
                        fontSize: 14))),
            const SizedBox(width: 10),
          ],
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(field.label,
                      style: const TextStyle(
                          color: _recordInk,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)))),
        ]),
        const SizedBox(height: 12),
        _content(),
      ]));
}

class _UnansweredBorderPainter extends CustomPainter {
  const _UnansweredBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5), const Radius.circular(12)));
    final paint = Paint()
      ..color = const Color(0xffdfe5ec)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final edge in outline.computeMetrics()) {
      for (double offset = 0; offset < edge.length; offset += 7) {
        canvas.drawPath(
            edge.extractPath(offset, (offset + 4).clamp(0, edge.length)),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_UnansweredBorderPainter oldDelegate) => false;
}
