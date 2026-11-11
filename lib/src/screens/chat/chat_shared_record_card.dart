import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/assessment_interpretation.dart';
import '../../ai/assessment_scoring.dart';
import '../../assessment_engine.dart';
import '../../models.dart';
import '../../providers/auth_providers.dart';
import '../../services/malva_api_client.dart';
import '../../services/weekly_summary_service.dart';
import '../../time/wib.dart';

/// Compact saved clinical records stay readable in the conversation.
class ChatSharedRecordCard extends ConsumerStatefulWidget {
  const ChatSharedRecordCard({super.key, required this.message});

  final ChatMessage message;

  @override
  ConsumerState<ChatSharedRecordCard> createState() =>
      _ChatSharedRecordCardState();
}

class _ChatSharedRecordCardState extends ConsumerState<ChatSharedRecordCard> {
  static const _ink = Color(0xFF303745);
  static const _muted = Color(0xFF9299A7);
  static const _purple = Color(0xFF9854BD);
  static const _mint = Color(0xFF249F87);
  late final String _owner;
  bool _invalidated = false;
  int _generation = 0;
  BackendTherapySubmission? _submission;
  BackendScreeningSession? _screening;
  WeeklySummaryMetrics? _weekly;
  bool _loading = false;

  String _ownerOf(AuthSession? session) => session == null
      ? ''
      : '${session.role.name}:${session.backendUserId ?? session.identifier}';

  bool get _ownerMatches =>
      !_invalidated && _ownerOf(ref.read(currentSessionProvider)) == _owner;
  Map get _meta => widget.message.metadata ?? const {};
  String get _module =>
      (_submission?.moduleId ?? _meta['module_id']?.toString() ?? '')
          .toLowerCase();
  bool get _isAssessmentModule => _module == 'who5' || _module == 'dass21';
  bool get _historicalSummary =>
      RegExp(r'\b14\s*hari\b', caseSensitive: false)
          .hasMatch(widget.message.text) ||
      ['days', 'period_days', 'window_days'].any((key) => _meta[key] == 14);

  @override
  void initState() {
    super.initState();
    _owner = _ownerOf(ref.read(currentSessionProvider));
    ref.listenManual(currentSessionProvider, (_, next) {
      if (_ownerOf(next) != _owner && !_invalidated) {
        setState(() {
          _invalidated = true;
          _generation++;
          _submission = null;
          _screening = null;
          _weekly = null;
        });
      }
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant ChatSharedRecordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.kind != widget.message.kind ||
        oldWidget.message.metadata != widget.message.metadata ||
        oldWidget.message.text != widget.message.text) {
      _submission = null;
      _screening = null;
      _weekly = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    _loading = false;
    if (!_ownerMatches || token == null || token.isEmpty) return;
    final api = ref.read(apiClientProvider);
    final submissionId = _meta['submission_id']?.toString() ?? '';
    final screeningId = _meta['screening_id']?.toString() ?? '';
    final patientId = session!.role == UserRole.patient
        ? session.backendUserId ?? session.identifier
        : widget.message.senderId;
    final kind = widget.message.kind;
    try {
      if (submissionId.isNotEmpty &&
          (kind == 'assessment' || kind == 'worksheet')) {
        _loading = true;
        final submission = await api.getTherapySubmission(
            accessToken: token, submissionId: submissionId);
        if (!mounted || !_ownerMatches || generation != _generation) return;
        _submission = submission;
      } else if ((kind == 'summary' || kind == 'progress') &&
          _historicalSummary) {
        // A 14-day snapshot cannot be presented as a seven-day measurement.
        _loading = true;
        final weekly = await loadWeeklySummary(
            api: api,
            accessToken: token,
            asOf: widget.message.timestamp,
            patientId: session.role == UserRole.patient ? null : patientId);
        if (!mounted || !_ownerMatches || generation != _generation) return;
        _weekly = weekly;
      } else if (screeningId.isNotEmpty &&
          (kind == 'assessment' || kind == 'screening')) {
        _loading = true;
        final screening = await api.getScreeningDetail(
            accessToken: token, screeningId: screeningId, patientId: patientId);
        if (!mounted || !_ownerMatches || generation != _generation) return;
        _screening = screening;
      }
    } on Object {
      // Chat snapshots remain readable; a submission ID never falls back to answers.
    } finally {
      if (mounted && _ownerMatches && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map> _maps(dynamic value) => value is List
      ? value.whereType<Map>().toList()
      : value is Map
          ? [value]
          : [];
  String _text(Map data, String key, [String fallback = '']) =>
      data[key]?.toString() ?? fallback;
  num? _number(dynamic value, {num? maximum, bool integer = false}) =>
      value is num &&
              value.isFinite &&
              value >= 0 &&
              (maximum == null || value <= maximum) &&
              (!integer || value == value.roundToDouble())
          ? value
          : null;
  String _numeric(num? value) => value == null
      ? '—'
      : value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(1);

  Widget _tile(IconData icon, Color color,
          {double size = 28, double rotation = 0}) =>
      Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8)),
          child: Transform.rotate(
              angle: rotation,
              child: Icon(icon, size: size * .63, color: color)));

  Widget _heading(String title, IconData icon,
          {String? subtitle,
          Color color = _purple,
          bool compact = false,
          double rotation = 0}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _tile(icon, color, size: compact ? 24 : 26, rotation: rotation),
              SizedBox(width: compact ? 6 : 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                            fontSize: compact ? 11 : 12)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: TextStyle(
                              color: _muted, fontSize: compact ? 9 : 9.5)),
                  ])),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF0EAF7)),
            ],
          ]));

  Widget _white(Widget child,
          {Color color = Colors.white,
          EdgeInsets padding = const EdgeInsets.all(12)}) =>
      Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: padding,
          decoration: BoxDecoration(
              color: color,
              border: Border.all(color: const Color(0xFFF0EBF5)),
              borderRadius: BorderRadius.circular(14)),
          child: child);

  Widget _chip(String text, Color color,
          {bool score = false, double fontSize = 11}) =>
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
              color: score
                  ? const Color(0xFFD8FAEB)
                  : color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(score ? 20 : 7),
              border: Border.all(color: color.withValues(alpha: .10))),
          child: Text(text,
              style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700)));

  Widget _metric(String label, String value, IconData icon, Color color) =>
      _white(
          Row(children: [
            _tile(icon, color,
                rotation: icon == CupertinoIcons.capsule ? -.7854 : 0),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: const TextStyle(color: _ink, fontSize: 12))),
            const SizedBox(width: 4),
            _chip(value, color),
          ]),
          padding: const EdgeInsets.all(10));

  List<Widget> _summary() {
    final historical = _historicalSummary;
    final mood = historical
        ? (_weekly?.moodKnown == true ? _weekly?.moodCount : null)
        : _number(_meta['mood_count'], integer: true);
    final sleep = historical
        ? (_weekly?.moodKnown == true && (_weekly?.moodCount ?? 0) > 0
            ? _weekly?.avgSleepHours
            : null)
        : _number(_meta['avg_sleep_hours'], maximum: 24);
    final adherence = historical
        ? (_weekly?.logsKnown == true ? _weekly?.adherencePercent : null)
        : _number(_meta['medication_adherence'], maximum: 100);
    return [
      _heading('Ringkasan Periodik (7 Hari)', Icons.auto_awesome,
          subtitle: 'Generasi otomatis dari data harian'),
      _metric('Mood Check-in', '${_numeric(mood)} Kali',
          Icons.sentiment_satisfied_alt, const Color(0xFFD7AC44)),
      _metric('Rata-rata Tidur', '${_numeric(sleep)} Jam',
          Icons.bedtime_outlined, const Color(0xFF8176CB)),
      _metric('Ketaatan Minum Obat', '${_numeric(adherence)}%',
          CupertinoIcons.capsule, _mint),
    ];
  }

  List<Widget> _goals() {
    final goals = _maps(_meta['goals'] ?? _meta['habits']);
    const colors = [
      Color(0xFF8078CA),
      Color(0xFF9D8ED3),
      Color(0xFFE3A21F),
      Color(0xFF20B5C6)
    ];
    return [
      _heading('Progress Goals & Habits', Icons.adjust,
          subtitle: 'Pembaruan Target Mingguan',
          compact: true,
          color: const Color(0xFF8478CF)),
      for (var i = 0; i < goals.length; i++)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(builder: (_) {
              final goal = goals[i];
              final done = _number(goal['done_this_week'], integer: true);
              final target = _number(goal['target_per_week'], integer: true);
              final color = colors[i % colors.length];
              return Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Text(_text(goal, 'title', 'Goal'),
                          style: const TextStyle(color: _ink, fontSize: 11))),
                  const SizedBox(width: 8),
                  Text('${_numeric(done)}/${_numeric(target)} minggu ini',
                      style: TextStyle(
                          color: done != null && done > 0 ? color : _muted,
                          fontSize: 10)),
                ]),
                const SizedBox(height: 6),
                if (done != null && target != null && target > 0)
                  LinearProgressIndicator(
                      value: (done / target).clamp(0, 1).toDouble(),
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(6),
                      color: color,
                      backgroundColor: const Color(0xFFEDE8F4)),
              ]);
            })),
      if (goals.isEmpty)
        const Text('Goals belum tersedia',
            style: TextStyle(color: _muted, fontSize: 12)),
    ];
  }

  Widget _cf(String instrument, num? cf, {bool triage = false}) => Container(
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
          color: const Color(0xFFF0F6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE3EDF9))),
      child: Row(children: [
        _tile(Icons.percent, const Color(0xFF538CCB), size: 26),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '$instrument · ${triage ? 'Dukungan aturan triage' : 'Dukungan rule internal'} (CF)',
              style: const TextStyle(color: _muted, fontSize: 9)),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: cf == null ? 'CF belum tersedia' : cf.toStringAsFixed(2),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: _ink, fontSize: 13)),
            if (cf != null)
              TextSpan(
                  text: ' (${(cf * 100).round()}%)',
                  style: const TextStyle(color: _muted, fontSize: 10)),
          ])),
        ])),
      ]));

  Widget _level(String level) => Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
          color: const Color(0xFFFBF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF3EBF9))),
      child: Row(children: [
        _tile(Icons.health_and_safety_outlined, _purple, size: 28),
        const SizedBox(width: 9),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TINGKAT GEJALA',
              style: TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  letterSpacing: .5)),
          const SizedBox(height: 3),
          Text(level,
              style: const TextStyle(
                  color: _purple, fontSize: 12, fontWeight: FontWeight.w700)),
        ])),
      ]));

  Widget _instrument(
          String name, String score, String level, String cfName, num? cf,
          {bool triage = false}) =>
      _white(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(name,
                  style: const TextStyle(
                      color: _ink, fontSize: 12, fontWeight: FontWeight.w700))),
          const SizedBox(width: 6),
          _chip(score, _mint, score: true),
        ]),
        _level(level),
        _cf(cfName, cf, triage: triage),
      ]));

  List<Widget> _assessment() {
    final header = _heading(
        'Hasil Screening Klinis', Icons.assignment_turned_in_outlined,
        subtitle: 'Evaluasi Mandiri Terbaru', color: _mint);
    final submissionId = _meta['submission_id']?.toString() ?? '';
    final screeningId = _meta['screening_id']?.toString() ?? '';
    if ((submissionId.isNotEmpty && _submission == null) ||
        (screeningId.isNotEmpty && _screening == null)) {
      return [
        header,
        Text(_loading ? 'Memuat assessment…' : 'Assessment belum tersedia',
            style: const TextStyle(color: _muted, fontSize: 12))
      ];
    }
    if (_isAssessmentModule) {
      final raw = _submission?.answers ?? _meta['answers'];
      final answers =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final complete = isCompleteAssessmentAnswers(_module, answers);
      final interpretation = complete
          ? interpretDassWho5(answers: answers, moduleId: _module)
          : null;
      if (_module == 'who5') {
        final score = complete ? scoreWho5(answers) : null;
        return [
          header,
          _instrument(
              'WHO-5 (Well-Being Index)',
              '${score?.raw ?? '—'} / 25',
              score?.level ?? 'Belum tersedia',
              'WHO-5',
              interpretation?.certaintyFactor,
              triage: true),
          if (_meta['crisis_flag'] == true) _safety(),
        ];
      }
      final score = complete ? scoreDass21(answers) : null;
      return [
        header,
        _white(
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('DASS-21',
              style: TextStyle(
                  color: _ink, fontWeight: FontWeight.w700, fontSize: 12)),
          for (final part in [
            ('Depresi', score?.depression, score?.depressionLevel),
            ('Kecemasan', score?.anxiety, score?.anxietyLevel),
            ('Stres', score?.stress, score?.stressLevel),
          ]) ...[
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  Expanded(
                      child: Text(part.$1,
                          style: const TextStyle(color: _ink, fontSize: 12))),
                  _chip('${part.$2 ?? '—'} / 42', _mint, score: true),
                ])),
            _level(part.$3 ?? 'Belum tersedia'),
          ],
          _cf('DASS-21', interpretation?.certaintyFactor, triage: true),
        ])),
        if (interpretation?.triageLevel == 'krisis' ||
            _meta['crisis_flag'] == true)
          _safety(),
      ];
    }
    final data =
        _meta['bundle'] is Map ? {..._meta, ..._meta['bundle'] as Map} : _meta;
    Map instrument(String id) {
      final saved = id == 'phq9' ? _screening?.phq9 : _screening?.gad7;
      if (saved != null)
        return {
          'score': saved.score,
          'max_score': saved.maxScore,
          'crisis_flag': saved.crisisFlag,
          'cf': saved.hasCertaintyFactor ? saved.certaintyFactor : double.nan,
        };
      return data[id] is Map
          ? data[id] as Map
          : {
              'score': data['${id}_score'],
              'max_score': data['${id}_max_score'],
              'cf': data['${id}_cf'],
              'crisis_flag': data['${id}_crisis_flag']
            };
    }

    final phq = instrument('phq9');
    final gad = instrument('gad7');
    return [
      header,
      for (final item in [
        (AssessmentType.phq9, 'PHQ-9 (Depresi)', 'PHQ-9', 27, phq),
        (AssessmentType.gad7, 'GAD-7 (Kecemasan)', 'GAD-7', 21, gad)
      ])
        Builder(builder: (_) {
          final level = AssessmentEngine.levelFromScore(
              item.$1, item.$5['score'],
              maxScore: item.$5['max_score']);
          final cf = AssessmentEngine.savedCertaintyFactor(
              type: item.$1,
              score: item.$5['score'],
              maxScore: item.$5['max_score'],
              cf: item.$5['cf'],
              answers: AssessmentEngine.savedAnswers(item.$5['answers']),
              crisisFlag: item.$5['crisis_flag'] == true);
          return _instrument(
              item.$2,
              '${level == null ? '—' : _numeric(item.$5['score'] as num)} / ${item.$4}',
              level?.label ?? 'Belum tersedia',
              item.$3,
              cf);
        }),
      if (_screening?.crisisFlag == true ||
          [_meta, data, phq, gad].any((value) => value['crisis_flag'] == true))
        _safety(),
    ];
  }

  Widget _safety() => const Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Text('INDIKATOR KESELAMATAN: YA',
          style: TextStyle(
              color: Color(0xFFB43838),
              fontWeight: FontWeight.w700,
              fontSize: 11)));

  Widget _recordTimestamp() => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          const Icon(Icons.calendar_month_outlined, size: 13, color: _purple),
          const SizedBox(width: 4),
          Text(formatWibDate(widget.message.timestamp),
              style: const TextStyle(color: _ink, fontSize: 11)),
        ]),
        const SizedBox(height: 3),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          const Icon(Icons.schedule, size: 13, color: _purple),
          const SizedBox(width: 4),
          Text(formatWibBubbleTime(widget.message.timestamp),
              style: const TextStyle(color: _muted, fontSize: 10)),
        ]),
      ]));

  List<Widget> _medications() => [
        _recordTimestamp(),
        _heading('DAFTAR OBAT AKTIF & RESEP', CupertinoIcons.capsule,
            color: _purple, compact: true, rotation: -.7854),
        for (final med in _maps(_meta['medications'] ?? _meta['medication']))
          _white(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _tile(CupertinoIcons.capsule_fill, const Color(0xFF4188DE),
                  rotation: -.7854),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(_text(med, 'name', 'Obat'),
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12))),
              if (_text(med, 'form').isNotEmpty)
                _chip(_text(med, 'form'), _muted, fontSize: 9),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              if (_text(med, 'dosage').isNotEmpty)
                _chip(_text(med, 'dosage'), _purple),
              const Spacer(),
              if (_text(med, 'reminder_time').isNotEmpty) ...[
                const Icon(Icons.schedule, color: _muted, size: 13),
                const SizedBox(width: 3),
                Flexible(
                    child: Text(_text(med, 'reminder_time'),
                        style: const TextStyle(color: _muted, fontSize: 11))),
              ],
            ]),
            if (_text(med, 'relation_to_meal').isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(_text(med, 'relation_to_meal'),
                      style: const TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontStyle: FontStyle.italic))),
          ])),
      ];

  List<Widget> _diary() {
    final data = _meta['diary'] is Map ? _meta['diary'] as Map : _meta;
    final occurredAt = parseWibStored(_text(data, 'occurred_at'));
    return [
      _heading('Diary', Icons.menu_book_outlined,
          color: const Color(0xFFC69F49)),
      _recordTimestamp(),
      _white(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (occurredAt != null) ...[
              Row(children: [
                const Icon(Icons.calendar_month_outlined,
                    size: 13, color: Color(0xFFAC8040)),
                const SizedBox(width: 5),
                Expanded(
                    child: Text('${formatWibDateTime(occurredAt)} WIB',
                        style: const TextStyle(
                            color: Color(0xFFAC8040),
                            fontSize: 11,
                            fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 9),
            ],
            if (_text(data, 'title').isNotEmpty) ...[
              Text(_text(data, 'title'),
                  style: const TextStyle(
                      color: _ink, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
            ],
            Text(
                _text(
                    data, 'note', _text(data, 'content', widget.message.text)),
                style: const TextStyle(
                    color: Color(0xFF8E7B53),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    height: 1.5)),
          ]),
          color: const Color(0xFFFFFCEE)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_ownerMatches) return const SizedBox.shrink();
    final content = switch (widget.message.kind) {
      'summary' || 'progress' => _summary(),
      'goals' || 'habits' => _goals(),
      'assessment' || 'screening' || 'worksheet' => _assessment(),
      'prescription' || 'medication' => _medications(),
      'diary' => _diary(),
      _ => <Widget>[Text(widget.message.text)],
    };
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFF9F5FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEDE4F7))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...content,
          if (!const {'prescription', 'medication', 'diary'}
              .contains(widget.message.kind)) ...[
            SizedBox(
                height: switch (widget.message.kind) {
              'summary' || 'progress' => 17,
              'assessment' || 'screening' || 'worksheet' => 12,
              _ => 5,
            }),
            Align(
                alignment: Alignment.centerRight,
                child: Text(formatWibBubbleTime(widget.message.timestamp),
                    style: const TextStyle(color: _muted, fontSize: 10))),
          ],
        ]));
  }
}
