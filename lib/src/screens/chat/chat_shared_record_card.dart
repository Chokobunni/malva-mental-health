import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/assessment_interpretation.dart';
import '../../ai/assessment_scoring.dart';
import '../../assessment_engine.dart';
import '../../models.dart';
import '../../models/diary_content.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/diary_body.dart';
import '../../widgets/care_reference_widgets.dart';
import '../../services/malva_api_client.dart';
import '../../services/weekly_summary_service.dart';
import '../../services/medication_reminder_service.dart';
import '../../theme.dart';
import '../../time/wib.dart';
import 'screening_answers_sheet.dart';

/// A display-only snapshot: never includes medication IDs or dose logs.
Map<String, dynamic> sharedMedicationSnapshot(Medication med,
    {String reminderTime = '', String relationToMeal = '', DateTime? asOf}) {
  final schedule = med.schedule;
  final time = switch (schedule) {
    final s? when s.intervalHours > 0 => 'Setiap ${s.intervalHours} jam',
    final s? when s.intervalDays > 1 =>
      'Setiap ${s.intervalDays} hari • ${s.times.join(', ')}',
    final s? when s.intervalMonths > 0 =>
      'Setiap ${s.intervalMonths} bulan • ${s.times.join(', ')}',
    final s? when s.times.isNotEmpty => [
        s.times.join(', '),
        if (s.weekdays.isNotEmpty && s.weekdays.length < 7)
          s.weekdays
              .where((d) => d >= 1 && d <= 7)
              .map((d) => const [
                    'Sen',
                    'Sel',
                    'Rab',
                    'Kam',
                    'Jum',
                    'Sab',
                    'Min'
                  ][d - 1])
              .join(', ')
      ].join(' • '),
    _ => reminderTime.isNotEmpty
        ? reminderTime
        : med.reminders.map((r) => r.label).join(', '),
  };
  final now = asOf ?? wibNow();
  final doses = schedule == null
      ? (time.isEmpty
          ? 0
          : med.reminders.isEmpty
              ? 1
              : med.reminders.length)
      : MedicationReminderService.routineOccurrences(schedule,
              now: now, until: now.add(const Duration(days: 1)))
          .length;
  final units = doses * med.unitsPerDose;
  final daily = schedule == null ||
      (schedule.intervalMonths == 0 &&
          schedule.intervalDays <= 1 &&
          schedule.weekdays.length == 7);
  return {
    'name': med.name,
    'dosage': med.dosage,
    'form': med.form,
    'reminder_time': reminderTime,
    'schedule_label': time,
    'relation_to_meal': relationToMeal.isNotEmpty
        ? relationToMeal
        : med.reminders.firstOrNull?.relationToMeal ?? '',
    'source': med.source,
    'current_stock': med.currentStock,
    if (daily && units > 0 && med.currentStock >= 0)
      'approximate_days': med.currentStock ~/ units,
    if (schedule?.instructions.trim().isNotEmpty ?? false)
      'instructions': schedule!.instructions.trim(),
  };
}

final chatDiaryEntryProvider =
    FutureProvider.autoDispose.family<BackendDiaryEntry, String>((ref, id) {
  final token = ref.watch(currentSessionProvider)?.accessToken;
  if (token == null || token.isEmpty) throw StateError('Sesi tidak tersedia.');
  return ref
      .watch(apiClientProvider)
      .fetchDiaryEntry(accessToken: token, diaryId: id);
});

String? chatDiaryReference(ChatMessage message) {
  if (message.kind != 'diary') return null;
  final id = message.metadata?['diary_id'];
  return id is String && id.isNotEmpty ? id : null;
}

Map _diaryData(ChatMessage message, BackendDiaryEntry? entry) {
  if (entry != null) {
    return {
      'title': entry.title,
      'note': entry.note,
      if (entry.occurredAt != null) 'occurred_at': wibIso(entry.occurredAt!),
    };
  }
  final meta = message.metadata ?? const {};
  return meta['diary'] is Map ? meta['diary'] as Map : meta;
}

/// Compact saved clinical records stay readable in the conversation.
class ChatSharedRecordCard extends ConsumerStatefulWidget {
  const ChatSharedRecordCard(
      {super.key,
      required this.message,
      this.onOpenDiary,
      this.onOpenRecord,
      this.guardDetail});

  final ChatMessage message;
  final VoidCallback? onOpenDiary, onOpenRecord;
  final Widget Function(Widget child)? guardDetail;

  @override
  ConsumerState<ChatSharedRecordCard> createState() =>
      _ChatSharedRecordCardState();
}

class ChatDiaryDetail extends ConsumerWidget {
  const ChatDiaryDetail({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = chatDiaryReference(message);
    if (id == null) return _detail(context, ref, _diaryData(message, null));
    return ref.watch(chatDiaryEntryProvider(id)).when(
        skipLoadingOnRefresh: false,
        data: (entry) => _detail(context, ref, _diaryData(message, entry)),
        error: (_, __) => _unavailable(context, 'Akses jurnal tidak tersedia.'),
        loading: () => _unavailable(context, 'Memuat jurnal…'));
  }

  Widget _unavailable(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 18),
      child: Row(children: [
        Expanded(child: Text(text)),
        IconButton(
            tooltip: 'Tutup detail jurnal',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: MalvaColors.plum)),
      ]));

  Widget _detail(BuildContext context, WidgetRef ref, Map data) {
    final title = data['title']?.toString().trim() ?? '';
    final at = parseWibStored(data['occurred_at']?.toString() ?? '');
    final note = (data['note'] ?? data['content'] ?? message.text).toString();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: const Color(0xfffff1d3),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.menu_book_outlined,
                    color: Color(0xffac792a), size: 20)),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Detail Jurnal',
                    style: TextStyle(
                        color: MalvaColors.plum,
                        fontSize: 20,
                        fontWeight: FontWeight.w800))),
            IconButton(
                tooltip: 'Tutup detail jurnal',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: MalvaColors.plum)),
          ])),
      const Divider(
          height: 1, indent: 20, endIndent: 20, color: Color(0xffddd0e5)),
      Flexible(
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title.isNotEmpty)
                      Text(title,
                          style: const TextStyle(
                              color: MalvaColors.ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                    if (at != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text('${formatWibDateTime(at)} WIB',
                              style: const TextStyle(
                                  color: Color(0xff625a6b), fontSize: 13))),
                    const SizedBox(height: 14),
                    DiaryBody(
                        note: note,
                        api: ref.watch(apiClientProvider),
                        token: ref.watch(currentSessionProvider)?.accessToken,
                        mediaGrid: true),
                  ]))),
    ]);
  }
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
          double rotation = 0,
          Widget? trailing}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _tile(icon, color, size: compact ? 26 : 32, rotation: rotation),
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
                              color: _muted, fontSize: compact ? 10 : 11)),
                  ])),
              if (trailing != null) trailing,
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
      Color(0xff7a3de0),
      Color(0xffa482d4),
      Color(0xffd68a10),
      Color(0xff12a7b5)
    ];
    return [
      _heading('Progres Target & Kebiasaan', Icons.flag_outlined,
          subtitle: 'Pembaruan Target Mingguan'),
      for (final (index, goal) in goals.indexed) ...[
        if (index > 0) const Divider(height: 19, color: Color(0xffe8def0)),
        _goalProgress(goal, colors[index % colors.length]),
      ],
      if (goals.isEmpty)
        const Text('Target belum tersedia',
            style: TextStyle(color: _muted, fontSize: 12)),
    ];
  }

  Widget _goalProgress(Map goal, Color color) {
    final done = _number(goal['done_this_week'], integer: true);
    final target = _number(goal['target_per_week'], integer: true);
    final value = _number(goal['today_value'], integer: true);
    final dailyTarget = _number(goal['daily_target'], integer: true);
    final numeric =
        goal['method'] == 'numeric' && dailyTarget != null && dailyTarget > 0;
    final checklist = goal['method'] == 'checklist';
    final streak = _number(goal['streak_days'], integer: true);
    final tasks = _maps(goal['steps'])
        .where((step) => _text(step, 'label').trim().isNotEmpty)
        .toList();
    final activities = _text(goal, 'activity')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final progress = numeric
        ? (value == null ? null : value / dailyTarget)
        : (done != null && target != null && target > 0 ? done / target : null);
    final details = [
      if (numeric && value != null)
        '${_numeric(value)}/${_numeric(dailyTarget)} ${_text(goal, 'unit')}'
            .trim(),
      if (_text(goal, 'schedule_label').isNotEmpty)
        _text(goal, 'schedule_label'),
      if (goal['done_today'] == true) 'Selesai hari ini',
      if (streak != null && streak > 1) '$streak hari berturut-turut',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(_text(goal, 'title', 'Target'),
                style: const TextStyle(
                    color: _ink, fontWeight: FontWeight.w800, fontSize: 13))),
        if (!numeric && target != null && target > 0) ...[
          const SizedBox(width: 7),
          Text('${_numeric(done)}/${_numeric(target)}',
              style: TextStyle(
                  color: done != null && done > 0 ? color : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ] else if (!numeric &&
            goal['flexible_weekly_target'] == true &&
            done != null) ...[
          const SizedBox(width: 7),
          Text('${_numeric(done)} kali',
              style: const TextStyle(
                  color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ]),
      if (details.isNotEmpty)
        Text(details.join(' • '),
            style: const TextStyle(color: _muted, fontSize: 11)),
      if (checklist && tasks.isNotEmpty)
        _goalDetail(
          'Daftar Langkah',
          '${tasks.where((step) => step['done'] == true).length}/${tasks.length} selesai',
          tasks
              .map((step) => (_text(step, 'label'), step['done'] == true))
              .toList(),
        ),
      if (progress != null) ...[
        const SizedBox(height: 6),
        LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0).toDouble(),
            minHeight: 6,
            color: color,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: const Color(0xffecdef7)),
      ],
      if (!checklist && activities.isNotEmpty)
        _goalDetail('Rincian Aktivitas', null,
            [for (final activity in activities) (activity, null)]),
    ]);
  }

  Widget _goalDetail(String title, String? count, List<(String, bool?)> rows) =>
      Container(
        margin: const EdgeInsets.only(top: 7),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
            color: const Color(0xfff0e6f8),
            borderRadius: BorderRadius.circular(9)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        fontSize: 12))),
            if (count != null)
              Text(count,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _purple,
                      fontSize: 11)),
          ]),
          for (final (label, done) in rows)
            Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          done == null
                              ? Icons.circle
                              : done
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                          color: _purple,
                          size: done == null ? 6 : 15),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(label,
                              style:
                                  const TextStyle(color: _ink, fontSize: 11))),
                    ])),
        ]),
      );

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
              triage
                  ? '$instrument · Dukungan aturan triage (CF)'
                  : 'Dukungan aturan internal (CF)',
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

  Widget _level(String level, {bool screening = false}) {
    final color = switch (level.trim().toLowerCase()) {
      'normal' || 'minimal' => _mint,
      'sedang' => const Color(0xff9a5b04),
      'berat' || 'sangat berat' => const Color(0xffaf333a),
      _ => _purple,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: screening && level.toLowerCase() == 'sedang'
              ? const Color(0xffffedca)
              : color.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(level,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _instrument(
          String name, String score, String level, String cfName, num? cf,
          {bool triage = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(name,
                  style: const TextStyle(
                      color: _ink, fontSize: 12, fontWeight: FontWeight.w800))),
          const SizedBox(width: 6),
          _chip(score, _mint, score: true),
        ]),
        _level(level),
        _cf(cfName, cf, triage: triage),
      ]);

  List<Widget> _assessment() {
    final completedAt = _submission?.createdDateTime ??
        _screening?.createdAt ??
        parseWibStored(_meta['completed_at']?.toString()) ??
        parseWibStored(_meta['created_at']?.toString()) ??
        parseWibStored(_meta['shared_at']?.toString());
    final header = _heading(
        'Hasil Skrining Klinis', Icons.assignment_turned_in_outlined,
        subtitle: completedAt == null
            ? 'Waktu pengisian tidak tersedia'
            : 'Diisi pada ${formatWibDate(completedAt)} • ${formatWibBubbleTime(completedAt)} WIB',
        color: _mint);
    final submissionId = _meta['submission_id']?.toString() ?? '';
    final screeningId = _meta['screening_id']?.toString() ?? '';
    if ((submissionId.isNotEmpty && _submission == null) ||
        (screeningId.isNotEmpty && _screening == null)) {
      return [
        header,
        Text(_loading ? 'Memuat asesmen…' : 'Asesmen belum tersedia',
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
          _assessmentPanel(
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _instrument(
                'WHO-5 (Indeks Kesejahteraan)',
                '${score?.raw ?? '—'} / 25',
                score?.level ?? 'Belum tersedia',
                'WHO-5',
                interpretation?.certaintyFactor,
                triage: true),
            _answersButton(
                'who5',
                worksheetScreeningAnswers('who5', answers),
                '${score?.raw ?? '—'} / 25',
                'Indeks Kesejahteraan • Kategori: ${score?.level ?? 'Belum tersedia'}')
          ])),
          if (_meta['crisis_flag'] == true) _safety(),
        ];
      }
      final score = complete ? scoreDass21(answers) : null;
      return [
        header,
        _assessmentPanel(
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
            _level(part.$3 ?? 'Belum tersedia', screening: true),
            const Divider(height: 14, color: Color(0xffece7f1)),
          ],
          _answersButton(
              'dass21',
              worksheetScreeningAnswers('dass21', answers),
              '21 Item',
              'Depresi: ${score?.depression ?? '—'} • Kecemasan: ${score?.anxiety ?? '—'} • Stres: ${score?.stress ?? '—'}'),
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
          'answers': saved.answers,
          'cf': saved.hasCertaintyFactor ? saved.certaintyFactor : double.nan,
        };
      return data[id] is Map
          ? data[id] as Map
          : {
              'score': data['${id}_score'],
              'max_score': data['${id}_max_score'],
              'cf': data['${id}_cf'],
              'crisis_flag': data['${id}_crisis_flag'],
              'answers': data['${id}_answers']
            };
    }

    final phq = instrument('phq9');
    final gad = instrument('gad7');
    final phqAnswers = AssessmentEngine.savedAnswers(phq['answers']);
    final gadAnswers = AssessmentEngine.savedAnswers(gad['answers']);
    final safety = _screening?.crisisFlag == true ||
        (phqAnswers['phq_self_harm'] ?? 0) > 0 ||
        [_meta, data, phq, gad].any((value) => value['crisis_flag'] == true);
    final phqLevel = AssessmentEngine.levelFromScore(
        AssessmentType.phq9, phq['score'],
        maxScore: phq['max_score']);
    final gadLevel = AssessmentEngine.levelFromScore(
        AssessmentType.gad7, gad['score'],
        maxScore: gad['max_score']);
    return [
      header,
      _assessmentPanel(
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (item.$1 == AssessmentType.gad7)
                    const Divider(height: 21, color: Color(0xffece7f1)),
                  _instrument(
                      item.$2,
                      '${level == null ? '—' : _numeric(item.$5['score'] as num)} / ${item.$4}',
                      level?.label ?? 'Belum tersedia',
                      item.$3,
                      cf),
                ]);
          }),
        _answersButton(
            'screening',
            clinicalScreeningAnswers(phqAnswers, gadAnswers),
            safety ? 'Keselamatan: YA' : '',
            'PHQ-9: ${phqLevel == null ? '—' : phq['score']}/27 (${phqLevel?.label ?? 'Belum tersedia'}) • GAD-7: ${gadLevel == null ? '—' : gad['score']}/21 (${gadLevel?.label ?? 'Belum tersedia'})'),
      ])),
      if (safety) _safety(),
    ];
  }

  Widget _assessmentPanel(Widget child) => _white(child,
      color: const Color(0xfffcf8fe), padding: const EdgeInsets.all(14));

  Widget _answersButton(String module, List<ScreeningAnswer> answers,
          String badge, String subtitle) =>
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: OutlinedButton.icon(
          onPressed: () {
            final guard = widget.guardDetail;
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              clipBehavior: Clip.antiAlias,
              shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24))),
              builder: (_) {
                final detail = Consumer(builder: (context, ref, _) {
                  final owner = _ownerOf(ref.watch(currentSessionProvider));
                  if (owner != _owner || _invalidated) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Detail asesmen sudah tidak tersedia.'));
                  }
                  return ScreeningAnswersSheet(
                      module: module,
                      subtitle: subtitle,
                      badge: badge,
                      answers: answers);
                });
                return guard?.call(detail) ?? detail;
              },
            );
          },
          style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xff812b98),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              side: const BorderSide(color: Color(0xffdccbe4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13))),
          icon: const Icon(Icons.checklist_rounded, size: 17),
          label: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
                child: Text('Lihat Rincian Jawaban (${answers.length} Item)',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700))),
            const SizedBox(width: 5),
            const Icon(Icons.chevron_right_rounded, size: 17),
          ]),
        ),
      );

  Widget _safety() => const Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Text('INDIKATOR KESELAMATAN: YA',
          style: TextStyle(
              color: Color(0xFFB43838),
              fontWeight: FontWeight.w700,
              fontSize: 11)));

  List<Widget> _medications() {
    final medications = _maps(_meta['medications'] ?? _meta['medication']);
    final adherence =
        _number(_meta['medication_adherence'], maximum: 100, integer: true);
    return [
      LayoutBuilder(
          builder: (context, constraints) => Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      _tile(CupertinoIcons.capsule, _purple,
                          size: 34, rotation: -.7854),
                      const SizedBox(width: 10),
                      const Text('Obat Aktif',
                          style: TextStyle(
                              color: _ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800))
                    ]),
                    if (adherence != null)
                      _chip('Kepatuhan ${adherence.toInt()}% (7 hari)', _purple,
                          fontSize: 11),
                  ])),
      const SizedBox(height: 14),
      if (medications.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Data obat tidak tersedia.',
                style: TextStyle(color: _muted))),
      for (final med in medications) ...[
        _white(LayoutBuilder(builder: (context, constraints) {
          final source = sharedMedicationSourceLabel(med['source']);
          final patient = source == 'Pasien';
          final tone = patient ? _mint : _purple;
          final title = [_text(med, 'name', 'Obat'), _text(med, 'dosage')]
              .where((s) => s.trim().isNotEmpty)
              .join(' ');
          final details = [
            _text(med, 'schedule_label', _text(med, 'reminder_time')),
            _text(med, 'form'),
            _text(med, 'relation_to_meal')
          ].where((s) => s.trim().isNotEmpty).join(' • ');
          final stock = _number(med['current_stock'], integer: true);
          final days = _number(med['approximate_days'], integer: true);
          final stockWidget =
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (stock != null)
              _chip('Sisa ${stock.toInt()}', _purple, fontSize: 11),
            if (stock != null && days != null)
              Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text('± ${days.toInt()} hari',
                      style: const TextStyle(
                          color: Color(0xFF71808A), fontSize: 11)))
          ]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _tile(Icons.medical_services_outlined, tone, size: 38),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  if (details.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(details,
                            style: const TextStyle(
                                color: Color(0xFF596672),
                                fontSize: 12,
                                height: 1.4))),
                  if (_text(med, 'instructions').isNotEmpty)
                    Text(_text(med, 'instructions'),
                        style: const TextStyle(color: _muted, fontSize: 11)),
                  if (source.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 9),
                        child: _chip(
                            patient ? 'Input Pasien' : 'Resep Profesional',
                            tone,
                            fontSize: 10)),
                  if (constraints.maxWidth < 290 && stock != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: stockWidget),
                ])),
            if (constraints.maxWidth >= 290 && stock != null) ...[
              const SizedBox(width: 8),
              stockWidget
            ],
          ]);
        })),
        const SizedBox(height: 10),
      ],
      Align(
          alignment: Alignment.centerRight,
          child: Text(
              '${formatWibDate(widget.message.timestamp)} • ${formatWibBubbleTime(widget.message.timestamp)}',
              style: const TextStyle(color: _muted, fontSize: 10))),
    ];
  }

  List<Widget> _diary() {
    final id = chatDiaryReference(widget.message);
    if (id == null) return _diaryPreview(_diaryData(widget.message, null));
    return ref.watch(chatDiaryEntryProvider(id)).when(
        skipLoadingOnRefresh: false,
        data: (entry) => _diaryPreview(_diaryData(widget.message, entry)),
        error: (_, __) => const [Text('Akses jurnal tidak tersedia.')],
        loading: () => const [Text('Memuat jurnal…')]);
  }

  List<Widget> _diaryPreview(Map data) {
    final content = DiaryContent.parse(
        _text(data, 'note', _text(data, 'content', widget.message.text)));
    final at = parseWibStored(_text(data, 'occurred_at'));
    final lines = content.text.trim().split('\n');
    final preview = lines.length > 3
        ? '${lines.take(3).join('\n').trimRight()}...'
        : lines.join('\n');
    final previews = [
      for (final kind in ['drawing', 'photo'])
        if (content.media.where((item) => item.kind == kind).firstOrNull
            case final item?)
          item,
    ];
    final sent = widget.message.timestamp;
    return [
      _heading('Jurnal', Icons.menu_book_outlined,
          color: const Color(0xFFC69F49),
          trailing:
              const Icon(Icons.chevron_right_rounded, color: MalvaColors.plum)),
      if (_text(data, 'title').isNotEmpty)
        Text(_text(data, 'title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: _ink, fontSize: 16, fontWeight: FontWeight.w800)),
      if (at != null)
        Text('${formatWibDateTime(at)} WIB',
            style: const TextStyle(color: Color(0xff625a6b), fontSize: 11)),
      if (preview.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: _ink, fontSize: 14, height: 1.45))),
      if (previews.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 10, runSpacing: 6, children: [
              for (final media in previews)
                DiaryMediaTile(
                    media: media,
                    api: ref.watch(apiClientProvider),
                    token: ref.watch(currentSessionProvider)?.accessToken,
                    size: 68),
            ])),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
            child:
                DiaryTags(tags: content.tags.take(3).toList(growable: false))),
        const SizedBox(width: 6),
        Text('${formatWibDate(sent)} · ${formatWibBubbleTime(sent)}',
            style: const TextStyle(color: Color(0xff625a6b), fontSize: 10)),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_ownerMatches) return const SizedBox.shrink();
    final record = widget.message.kind == 'worksheet' && !_isAssessmentModule;
    if (record) return _therapyRecordCard();
    final assessment =
        const {'assessment', 'screening'}.contains(widget.message.kind) ||
            widget.message.kind == 'worksheet' && _isAssessmentModule;
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
            color: (assessment ||
                    const {'prescription', 'medication'}
                        .contains(widget.message.kind))
                ? Colors.white
                : const Color(0xFFF8F1FC),
            boxShadow: widget.message.kind == 'diary' ? careSoftShadow : null,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: (assessment ||
                        const {'prescription', 'medication'}
                            .contains(widget.message.kind))
                    ? const Color(0xFFDCCBE4)
                    : const Color(0xFFEDE4F7),
                width: (assessment ||
                        const {'prescription', 'medication'}
                            .contains(widget.message.kind))
                    ? 1.5
                    : 1)),
        child: InkWell(
            onTap: widget.onOpenDiary ?? (record ? widget.onOpenRecord : null),
            borderRadius: BorderRadius.circular(18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                        child: Text(
                            formatWibBubbleTime(widget.message.timestamp),
                            style:
                                const TextStyle(color: _muted, fontSize: 10))),
                  ],
                ])));
  }

  Widget _therapyRecordCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xfff0e8f7)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _tile(Icons.assignment_turned_in_outlined, _purple, size: 45),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Text(
                          _submission?.title ??
                              _text(_meta, 'title', widget.message.text),
                          style: const TextStyle(
                              color: Color(0xff202a38),
                              fontSize: 15,
                              height: 1.35,
                              fontWeight: FontWeight.w800))),
                  const SizedBox(width: 8),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                          color: const Color(0xfff3e7fc),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('Dibagikan',
                          style: TextStyle(
                              color: Color(0xff963bd0),
                              fontSize: 11,
                              fontWeight: FontWeight.w700))),
                ]),
                const Divider(height: 29, color: Color(0xfff0f2f4)),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                              style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xff963bd0),
                                  backgroundColor: const Color(0xfff3e7fc),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 13, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12))),
                              onPressed: widget.onOpenRecord,
                              icon: const Icon(CupertinoIcons.square_pencil,
                                  size: 17),
                              label: const Text('Lihat riwayat',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13))))),
                  const SizedBox(width: 8),
                  Text(formatWibBubbleTime(widget.message.timestamp),
                      style: const TextStyle(color: _muted, fontSize: 11)),
                ]),
              ])),
        ]),
      );
}
