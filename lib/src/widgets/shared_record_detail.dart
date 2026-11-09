import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import '../models.dart';
import '../assessment_engine.dart';
import '../time/wib.dart';

/// Read the snapshot that was actually shared, including older message formats.
class SharedRecordDetail extends StatelessWidget {
  const SharedRecordDetail(
      {super.key,
      required this.message,
      this.detail,
      this.showClinicalAudit = false});
  final ChatMessage message;
  final Widget? detail;
  final bool showClinicalAudit;

  static const _labels = {
    'title': 'Judul',
    'note': 'Catatan',
    'content': 'Isi',
    'mood': 'Mood',
    'occurred_at': 'Tanggal',
    'shared_at': 'Tanggal dibagikan',
    'medications': 'Obat & Resep',
    'name': 'Nama obat',
    'dosage': 'Dosis',
    'form': 'Bentuk obat',
    'reminder_time': 'Jadwal',
    'relation_to_meal': 'Aturan makan',
    'source': 'Sumber',
    'goals': 'Goals & Habits',
    'target_per_week': 'Target per minggu',
    'done_this_week': 'Selesai minggu ini',
    'is_active': 'Aktif',
    'insight': 'Insight',
    'summary': 'Ringkasan',
    'mood_count': 'Jumlah check-in',
    'avg_sleep_hours': 'Rata-rata tidur (jam)',
    'medication_adherence': 'Ketaatan obat (%)',
    'phq9_score': 'PHQ-9 Total Score',
    'gad7_score': 'GAD-7 Total Score',
    'overall_level': 'Tingkat gejala',
    'crisis_flag': 'Indikator keselamatan',
    'module_id': 'Instrumen',
    'answers': 'Jawaban tersimpan',
    'phq9': 'PHQ-9',
    'gad7': 'GAD-7',
    'score': 'Total Score',
    'max_score': 'Skor maksimum',
    'level': 'Tingkat gejala',
    'phq9_max_score': 'Skor maksimum PHQ-9',
    'gad7_max_score': 'Skor maksimum GAD-7',
    'phq9_level': 'Tingkat PHQ-9',
    'gad7_level': 'Tingkat GAD-7',
    'diary': 'Diary',
    'medication': 'Obat',
    'category': 'Kategori',
    'last_logged_on': 'Terakhir dicatat',
  };
  static const _hidden = {
    'id',
    'session_id',
    'submission_id',
    'screening_id',
    'attachment_id',
    'goal_ids',
    'private_note',
    'access_token',
    'refresh_token',
    'token',
    'secret',
  };

  List<Widget> _fields(Map data) => [
        for (final entry in data.entries)
          if (!_hidden.contains(entry.key) && entry.value != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _labels[entry.key] ??
                            entry.key.toString().replaceAll('_', ' '),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (entry.value is Map)
                      ..._fields(entry.value as Map)
                    else if (entry.value is List)
                      for (final value in entry.value as List)
                        if (value is Map)
                          ..._fields(value)
                        else
                          Text(value.toString())
                    else
                      SelectableText(entry.value is bool
                          ? (entry.value == true ? 'Ya' : 'Tidak')
                          : entry.value.toString()),
                  ]),
            ),
      ];

  static const _purple = Color(0xFF963DD0);
  static const _ink = Color(0xFF242C36);
  static const _muted = Color(0xFF707782);

  Widget _card(Widget child,
          {Color color = Colors.white, Color? accent, Color? scoreAccent}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE6E7E9)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0C000000), blurRadius: 4, offset: Offset(0, 3))
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
              border: Border(
                  left: accent == null
                      ? BorderSide.none
                      : BorderSide(color: accent, width: 5),
                  bottom: scoreAccent == null
                      ? BorderSide.none
                      : BorderSide(color: scoreAccent, width: 4))),
          padding: const EdgeInsets.all(18),
          child: child,
        ),
      );

  Widget _heading(String text, IconData icon, {Color color = _purple}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 18),
        child: Row(children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _muted,
                      fontSize: 13,
                      letterSpacing: .7)))
        ]),
      );

  Widget _pill(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4)
          ],
          Flexible(
              child: Text(text,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11))),
        ]),
      );

  List<Map> _maps(dynamic value) => value is List
      ? value.whereType<Map>().toList()
      : value is Map
          ? [value]
          : [];
  String _value(Map data, String key, [String fallback = '']) =>
      data[key]?.toString() ?? fallback;

  List<Widget> _medications(Map meta) => [
        _heading('DAFTAR OBAT AKTIF & RESEP', Icons.medication_outlined),
        for (final med in _maps(meta['medications'] ?? meta['medication']))
          _card(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFFEFF6FF),
                child: Icon(CupertinoIcons.capsule_fill,
                    color: Color(0xFF4188DE))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: Text(_value(med, 'name', 'Obat'),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: _ink))),
                    if (_value(med, 'form').isNotEmpty) ...[
                      const SizedBox(width: 6),
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 80),
                          child: _pill(_value(med, 'form'), _muted))
                    ],
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    if (_value(med, 'dosage').isNotEmpty)
                      Flexible(child: _pill(_value(med, 'dosage'), _purple)),
                    const SizedBox(width: 6),
                    if (_value(med, 'reminder_time').isNotEmpty)
                      Expanded(
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                            const Icon(Icons.schedule, size: 16, color: _muted),
                            const SizedBox(width: 4),
                            Flexible(
                                child: Text(_value(med, 'reminder_time'),
                                    style: const TextStyle(
                                        color: _muted, fontSize: 13))),
                          ])),
                  ]),
                  if (_value(med, 'relation_to_meal').isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_value(med, 'relation_to_meal'),
                            style:
                                const TextStyle(fontSize: 12, color: _muted))),
                ])),
          ])),
      ];

  List<Widget> _goals(Map meta) {
    final goals = _maps(meta['goals']);
    return [
      _heading('RINCIAN GOALS & HABITS', Icons.checklist_rounded,
          color: const Color(0xFF4188DE)),
      for (var i = 0; i < goals.length; i++)
        _goal(goals[i],
            i.isEven ? const Color(0xFF3E83EC) : const Color(0xFF8983ED)),
    ];
  }

  Widget _goal(Map goal, Color color) => _card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(_value(goal, 'title', 'Goal'),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: _ink))),
          if (goal['is_active'] is bool) ...[
            const SizedBox(width: 8),
            Flexible(
                child: _pill(goal['is_active'] == true ? 'AKTIF' : 'NONAKTIF',
                    goal['is_active'] == true ? Colors.green.shade700 : _muted,
                    icon:
                        goal['is_active'] == true ? Icons.check_circle : null)),
          ],
        ]),
        const SizedBox(height: 20),
        Row(children: [
          const Expanded(
              child: Text('Selesai minggu ini',
                  style: TextStyle(color: _muted, fontSize: 12))),
          if (goal['done_this_week'] != null ||
              goal['target_per_week'] != null) ...[
            const SizedBox(width: 8),
            Flexible(
                child: _pill(
                    '${goal['done_this_week'] ?? '—'} / ${goal['target_per_week'] ?? '—'} Target',
                    color)),
          ],
        ]),
        if (goal['done_this_week'] is num &&
            goal['target_per_week'] is num &&
            (goal['target_per_week'] as num) > 0) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
              value: ((goal['done_this_week'] as num) /
                      (goal['target_per_week'] as num))
                  .clamp(0, 1)
                  .toDouble(),
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              color: color,
              backgroundColor: const Color(0xFFF1F2F4)),
        ],
      ]),
      accent: color);

  List<Widget> _diary(Map meta) {
    final data = meta['diary'] is Map ? meta['diary'] as Map : meta;
    final at = parseWibStored(_value(data, 'occurred_at'));
    return [
      _card(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (at != null) ...[
              Row(children: [
                const Icon(Icons.calendar_month,
                    color: Color(0xFFBD9133), size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('${formatWibDateTime(at)} WIB',
                        style: const TextStyle(
                            color: Color(0xFFBD9133),
                            fontWeight: FontWeight.w700)))
              ]),
              const SizedBox(height: 18),
            ],
            if (_value(data, 'title').isNotEmpty) ...[
              Text(_value(data, 'title'),
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 18)
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.format_quote_rounded,
                  color: Color(0xFFE9D996), size: 30),
              const SizedBox(width: 8),
              Expanded(
                  child: SelectableText(
                      _value(
                          data, 'note', _value(data, 'content', message.text)),
                      style: const TextStyle(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                          height: 1.6,
                          color: _ink))),
            ]),
          ]),
          color: const Color(0xFFFFFAEB))
    ];
  }

  Widget _metric(String title, String value, String unit, IconData icon,
          Color color) =>
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: .12),
              child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 7),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 11))),
        ]),
        const SizedBox(height: 24),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: value,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 32, color: _ink)),
          TextSpan(
              text: ' $unit',
              style: const TextStyle(color: _muted, fontSize: 12))
        ])),
      ]));

  List<Widget> _summary(Map meta) {
    final days =
        RegExp(r'(\d+) hari').firstMatch(message.text)?.group(1) ?? '7';
    return [
      _heading('METRIK $days HARI TERAKHIR', Icons.pie_chart_rounded),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: _metric('CHECK-IN', _value(meta, 'mood_count', '—'), 'kali',
                Icons.assignment_turned_in, Colors.blue)),
        const SizedBox(width: 12),
        Expanded(
            child: _metric('TIDUR', _value(meta, 'avg_sleep_hours', '—'), 'jam',
                Icons.bedtime, Colors.indigo)),
      ]),
      _card(
          Stack(children: [
            Positioned(
                right: -25,
                bottom: -30,
                child: Transform.rotate(
                    angle: -.65,
                    child: const Icon(CupertinoIcons.capsule,
                        size: 130, color: Color(0x25FFFFFF)))),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('KETAATAN OBAT',
                  style: TextStyle(
                      color: Color(0xFFB8F5D1),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 12),
              Text('${_value(meta, 'medication_adherence', '—')}%',
                  style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
              if (meta['medication_adherence'] == 100)
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.star_rounded,
                              color: Color(0xFFFFDE67), size: 20),
                          SizedBox(width: 6),
                          Expanded(
                              child: Text('Sempurna! Lanjutkan dengan baik.',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13))),
                        ])),
            ]),
          ]),
          color: const Color(0xFF0EAE8D)),
    ];
  }

  String _level(dynamic value) => switch (value?.toString()) {
        'crisis' => 'KRISIS',
        'severe' => 'Berat',
        'moderately_severe' => 'Cukup berat',
        'moderate' => 'Sedang',
        'mild' => 'Ringan',
        'normal' || 'minimal' => 'Minimal',
        null || '' => 'Belum tersedia',
        _ => value.toString(),
      };

  Widget _scoreCard(String instrument, Map data, Color color) => _card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text('$instrument Total Score',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _muted,
                      fontSize: 12))),
          const SizedBox(width: 5),
          Icon(
              instrument == 'PHQ-9'
                  ? Icons.psychology
                  : Icons.monitor_heart_outlined,
              color: color,
              size: 21),
        ]),
        const SizedBox(height: 16),
        Text(_value(data, 'score', '—'),
            style: TextStyle(
                fontSize: 38, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 12),
        _pill(_level(data['level']), color),
      ]),
      scoreAccent: color);

  Widget _cfCard(String label, dynamic value) => _card(Row(children: [
        const CircleAvatar(
            radius: 23,
            backgroundColor: Color(0xFFEAF4FF),
            child: Icon(Icons.percent, color: Color(0xFF4386DE), size: 28)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label · Dukungan rule internal (CF)',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: _muted)),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(
                text:
                    value is num ? value.toStringAsFixed(2) : value.toString(),
                style: const TextStyle(
                    fontSize: 23, fontWeight: FontWeight.w900, color: _ink)),
            if (value is num)
              TextSpan(
                  text: ' (${(value * 100).round()}%)',
                  style: const TextStyle(fontSize: 13, color: _muted)),
          ])),
        ])),
      ]));

  List<Widget> _assessment(Map meta) {
    final data =
        meta['bundle'] is Map ? {...meta, ...meta['bundle'] as Map} : meta;
    Map instrument(String id) => data[id] is Map
        ? data[id] as Map
        : {'score': data['${id}_score'], 'max_score': data['${id}_max_score']};
    final rawPhq = instrument('phq9');
    final rawGad = instrument('gad7');
    final phqLevel = AssessmentEngine.levelFromScore(
        AssessmentType.phq9, rawPhq['score'],
        maxScore: rawPhq['max_score']);
    final gadLevel = AssessmentEngine.levelFromScore(
        AssessmentType.gad7, rawGad['score'],
        maxScore: rawGad['max_score']);
    final phq = {
      ...rawPhq,
      'score': phqLevel == null ? null : rawPhq['score'],
      'level': phqLevel?.label
    };
    final gad = {
      ...rawGad,
      'score': gadLevel == null ? null : rawGad['score'],
      'level': gadLevel?.label
    };
    final crisis = [meta, data, rawPhq, rawGad]
        .any((value) => value['crisis_flag'] == true);
    final hasSafety = [meta, data, rawPhq, rawGad]
        .any((value) => value['crisis_flag'] is bool);
    final overall = crisis
        ? 'crisis'
        : phqLevel != null && gadLevel != null
            ? (phqLevel.index > gadLevel.index ? phqLevel : gadLevel).label
            : null;
    return [
      _card(
          Stack(children: [
            if (crisis)
              const Positioned(
                  right: -28,
                  top: -35,
                  child: Icon(Icons.warning_rounded,
                      size: 150, color: Color(0x12D62828))),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                  radius: 22,
                  backgroundColor: crisis
                      ? const Color(0xFFFFE2E2)
                      : const Color(0xFFF1E3FB),
                  child: Icon(
                      crisis ? Icons.bolt : Icons.health_and_safety_outlined,
                      color: crisis ? Colors.red.shade700 : _purple,
                      size: 28)),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('TINGKAT GEJALA',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .6,
                            color: crisis ? Colors.red.shade600 : _muted)),
                    const SizedBox(height: 8),
                    Text(_level(overall),
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: crisis ? Colors.red.shade800 : _purple)),
                    if (hasSafety) ...[
                      const SizedBox(height: 16),
                      Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: crisis
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            const Icon(Icons.health_and_safety,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 7),
                            Expanded(
                                child: Text(
                                    'INDIKATOR KESELAMATAN: ${crisis ? 'YA' : 'TIDAK'}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12))),
                          ])),
                    ],
                  ])),
            ]),
          ]),
          color: crisis ? const Color(0xFFFFF2F2) : const Color(0xFFFAF5FF)),
      _heading('DETAIL SKOR (PHQ-9 / GAD-7)', Icons.checklist),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _scoreCard('PHQ-9', phq, Colors.red.shade700)),
        const SizedBox(width: 12),
        Expanded(child: _scoreCard('GAD-7', gad, Colors.orange.shade800)),
      ]),
      if (showClinicalAudit &&
          (meta['cf'] is num || meta['certainty_factor'] is num))
        _cfCard('Assessment', meta['cf'] ?? meta['certainty_factor']),
      for (final item in [('PHQ-9', phq), ('GAD-7', gad)]) ...[
        if (item.$2['summary'] != null)
          Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_value(item.$2, 'summary'))),
        if (showClinicalAudit && item.$2['cf'] != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _cfCard(item.$1, item.$2['cf'])),
        if (item.$2['answers'] is Map)
          ExpansionTile(
              title: Text('Jawaban ${item.$1}'),
              children: _fields(item.$2['answers'] as Map)),
      ],
      if (meta['summary'] != null)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SelectableText(_value(meta, 'summary'))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final meta = message.metadata ?? const <String, dynamic>{};
    final content = switch (message.kind) {
      'prescription' ||
      'medication'
          when meta['medications'] != null || meta['medication'] != null =>
        _medications(meta),
      'goals' || 'habits' when meta['goals'] is List => _goals(meta),
      'diary' => _diary(meta),
      'summary' || 'progress' => _summary(meta),
      'assessment' ||
      'screening'
          when meta.containsKey('phq9_score') ||
              meta.containsKey('gad7_score') ||
              meta['phq9'] is Map ||
              meta['gad7'] is Map ||
              meta['bundle'] is Map ||
              meta['source'] == 'screening' ||
              message.kind == 'screening' =>
        _assessment(meta),
      _ => [SelectableText(message.text), ..._fields(meta)],
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            color: const Color(0xFFFFF1F3),
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(builder: (context, constraints) {
              final left = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Detail Record',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                            color: _ink)),
                    const SizedBox(height: 7),
                    Text(
                        message.kind == 'assessment' ||
                                message.kind == 'screening'
                            ? 'Assessment Dibagikan'
                            : 'Dibagikan',
                        style: const TextStyle(fontSize: 12, color: _muted)),
                  ]);
              final right =
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: _purple),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(formatWibDate(message.timestamp),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _ink)))
                ]),
                const SizedBox(height: 7),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.schedule, size: 16, color: _purple),
                  const SizedBox(width: 6),
                  Text(formatWibBubbleTime(message.timestamp),
                      style: const TextStyle(fontSize: 13, color: _muted))
                ]),
              ]);
              if (constraints.maxWidth < 250 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.25)
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      left,
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: right)
                    ]);
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: left),
                    const SizedBox(width: 10),
                    Expanded(flex: 4, child: right)
                  ]);
            })),
        Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: detail == null ? content : [detail!])),
      ]),
    );
  }
}
