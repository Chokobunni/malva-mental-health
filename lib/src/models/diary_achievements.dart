import 'dart:math';
import '../models.dart';
import '../time/wib.dart';
import 'diary_content.dart';
import 'diary_catalog.dart';

/// Visit every ordered three-card arrangement once using a shuffled rank cycle.
class DiaryPromptDeck {
  DiaryPromptDeck({Random? random, Map<String, dynamic>? state})
      : _random = random ?? Random() {
    if (state != null &&
        state['start'] is int &&
        state['step'] is int &&
        state['cursor'] is int &&
        state['start'] >= 0 &&
        state['start'] < cycleSize &&
        _validStep(state['step'] as int) &&
        state['cursor'] >= 0 &&
        state['cursor'] <= cycleSize) {
      _start = state['start'];
      _step = state['step'];
      _cursor = state['cursor'];
    } else {
      _reset();
    }
    refresh();
  }
  static const cycleSize = 100 * 99 * 98;
  // Keep each rank digit far enough apart that exclusion remapping cannot
  // leave a question in the same slot on two consecutive hands.
  static bool _validStep(int step) =>
      step >= 99 * 98 &&
      step <= cycleSize - 99 * 98 &&
      step.gcd(cycleSize) == 1 &&
      step % 98 >= 3 &&
      step % 98 <= 95 &&
      step ~/ 98 % 99 >= 2 &&
      step ~/ 98 % 99 <= 95;
  final Random _random;
  late int _start, _step, _cursor;
  List<DiaryPrompt> cards = [];
  Map<String, dynamic> toJson() =>
      {'start': _start, 'step': _step, 'cursor': _cursor};
  void _reset() {
    _start = _random.nextInt(cycleSize);
    do {
      _step = _random.nextInt(cycleSize - 1) + 1;
    } while (!_validStep(_step));
    _cursor = 0;
  }

  void refresh([int? slot]) {
    if (_cursor == cycleSize) _reset();
    final rank = (_start + _cursor++ * _step) % cycleSize;
    final a = rank ~/ (99 * 98);
    var b = rank ~/ 98 % 99;
    if (b >= a) b++;
    var c = rank % 98;
    for (final excluded in ([a, b]..sort())) {
      if (c >= excluded) c++;
    }
    cards = [diaryPrompts[a], diaryPrompts[b], diaryPrompts[c]];
  }
}

const diarySubjectiveBadges = <int>{
  27,
  28,
  29,
  37,
  38,
  44,
  45,
  47,
  48,
  49,
  50,
  71,
  72,
  73,
  74,
  75,
  76,
  77,
  78,
  79,
  81,
  82,
  83,
  84,
  85,
  86,
  87,
  88,
  89,
  91,
  92,
  93,
  94,
  95,
  96,
  97,
  98,
  99,
  100
};

class DiaryBadgeProgress {
  const DiaryBadgeProgress(this.badge, this.current, this.target);
  final DiaryBadge badge;
  final int current, target;
  bool get unlocked => current >= target;
  double get fraction => (current / target).clamp(0, 1);
}

String diaryDay(DateTime date) {
  final d = toWib(date);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Psychological experiences require a patient's saved selections, never keyword guesses.
List<DiaryBadgeProgress> evaluateDiaryBadges(List<DiaryEntry> source,
    {Set<String> activities = const {}}) {
  final entries = [...source]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final data = entries.map((e) => DiaryContent.parse(e.note)).toList();
  int count(bool Function(DiaryContent) predicate) =>
      data.where(predicate).length;
  bool answered(DiaryContent c) => c.prompt != null && c.text.trim().isNotEmpty;
  bool shortNote(DiaryContent c) =>
      c.text.trim().isNotEmpty &&
      c.text
              .trim()
              .split(RegExp(r'[.!?]+'))
              .where((s) => s.trim().isNotEmpty)
              .length <=
          2;
  int days(String palette) => {
        for (var i = 0; i < entries.length; i++)
          if (data[i].palette == palette) diaryDay(entries[i].createdAt)
      }.length;
  final monthDays = <String, Set<String>>{},
      monthColors = <String, Set<String>>{};
  for (var i = 0; i < entries.length; i++) {
    if (data[i].palette == null) continue;
    final day = diaryDay(entries[i].createdAt), month = day.substring(0, 7);
    (monthDays[month] ??= {}).add(day);
    (monthColors[month] ??= {}).add(data[i].palette!);
  }
  int maximum(Iterable<Set<String>> groups) =>
      groups.fold(0, (v, g) => max(v, g.length));
  bool gap = false, transition = false;
  for (var i = 1; i < entries.length; i++) {
    final before = toWib(entries[i - 1].createdAt),
        after = toWib(entries[i].createdAt);
    if (wibFromParts(after.year, after.month, after.day)
            .difference(wibFromParts(before.year, before.month, before.day))
            .inDays >=
        3) gap = true;
    if (const ['sendu', 'redup'].contains(data[i - 1].palette) &&
        const ['teduh', 'cerah'].contains(data[i].palette)) transition = true;
  }
  final values = <int, (int, int)>{};
  void v(int id, int current, [int target = 1]) =>
      values[id] = (current, target);
  void flag(int id, String event) => v(id, activities.contains(event) ? 1 : 0);
  for (final (id, target) in [
    (1, 1),
    (3, 3),
    (4, 5),
    (5, 10),
    (6, 20),
    (7, 50),
    (8, 100)
  ]) {
    v(id, entries.length, target);
  }
  v(2, activities.where((e) => e.startsWith('visit:')).length, 2);
  v(9, gap ? 1 : 0);
  v(10, entries.where((e) => toWib(e.createdAt).hour >= 20).length, 3);
  v(11, maximum(monthColors.values), 3);
  v(12, data.map((c) => c.palette).whereType<String>().toSet().length, 5);
  v(13, days('sendu'));
  v(14, days('redup'));
  v(15, days('netral'));
  v(16, days('teduh'), 5);
  v(17, days('cerah'), 5);
  v(18, transition ? 1 : 0);
  v(19, maximum(monthDays.values), 7);
  v(20, maximum(monthDays.values), 15);
  for (final (id, target) in [(21, 1), (22, 3), (23, 10), (24, 25)]) {
    v(id, count((c) => c.inVault), target);
  }
  flag(25, 'randomVault');
  flag(26, 'hardDayVault');
  flag(30, 'oldRead');
  v(31, count(answered));
  v(32, data.where(answered).map((c) => c.promptId).toSet().length, 5);
  v(33, count(answered), 15);
  v(34, count(answered), 30);
  flag(35, 'refreshPrompt');
  v(36, count((c) => c.text.trim().split(RegExp(r'\s+')).length > 100));
  v(39, count((c) => answered(c) && c.prompt!.category == 'Harapan'));
  v(40, count(answered), 10);
  v(41, count((c) => c.selfNote.trim().isNotEmpty));
  final selfNotes = data
      .map((c) => c.selfNote.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .length;
  v(42, selfNotes, 5);
  v(46, selfNotes, 15);
  v(
      43,
      count((c) =>
          c.selfNote.trim().isNotEmpty &&
          const ['redup', 'sendu'].contains(c.palette)));
  v(51, count((c) => c.media.isNotEmpty));
  final drawings =
      data.expand((c) => c.media).where((m) => m.kind == 'drawing').length;
  v(52, drawings, 3);
  v(53, count((c) => c.media.any((m) => m.kind == 'drawing')), 5);
  v(54, data.expand((c) => c.media).where((m) => m.kind == 'photo').length, 3);
  v(
      55,
      count((c) => c.media
          .any((m) => m.kind == 'drawing' && m.colors.toSet().length > 2)));
  v(
      56,
      count((c) =>
          c.media.any((m) => m.kind == 'drawing') && c.text.trim().isEmpty));
  v(57, count((c) => c.inVault && c.media.isNotEmpty));
  v(58, count((c) => c.font != 'roboto'));
  v(
      59,
      entries.where((e) {
        final c = DiaryContent.parse(e.note);
        return e.title.trim().isNotEmpty &&
            c.text.trim().isNotEmpty &&
            c.tags.isNotEmpty &&
            c.media.isNotEmpty;
      }).length);
  v(60, count((c) => c.media.isNotEmpty), 10);
  final tags = data.expand((c) => c.tags).map((s) => s.toLowerCase()).toSet();
  v(61, tags.length);
  v(62, tags.length, 5);
  v(67, tags.length, 10);
  bool tag(DiaryContent c, List<String> names) => c.tags.any(
      (t) => names.contains(t.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')));
  v(
      63,
      count((c) => tag(
          c, ['tenang', 'ketenangan', 'latihannapas', 'napas', 'relaksasi'])),
      3);
  v(64, count((c) => tag(c, ['istirahat', 'pulih', 'pemulihan', 'selfcare'])));
  v(
      65,
      count((c) =>
          tag(c, ['cemas', 'lelah', 'pemicu', 'kecemasan', 'kelelahan'])));
  v(
      66,
      count((c) =>
          tag(c, ['progres', 'kemajuan', 'pencapaian', 'kemenangankecil'])),
      3);
  flag(68, 'colorFilter');
  flag(69, 'adjacentRead');
  flag(70, 'reviewFive');
  v(
      80,
      count((c) =>
          c.inVault &&
          (c.appreciations.contains(72) ||
              tag(c, [
                'tenang',
                'ketenangan',
                'latihannapas',
                'napas',
                'relaksasi'
              ]))),
      3);
  v(
      90,
      count((c) =>
          c.appreciations.any((id) => id >= 81 && id <= 89) ||
          tag(c, ['selfcare', 'perawatandiri'])),
      5);
  for (final id in diarySubjectiveBadges) {
    var evidence =
        count((c) => c.appreciations.contains(id) && c.text.trim().isNotEmpty);
    if (id == 37)
      evidence = count((c) => c.appreciations.contains(id) && shortNote(c));
    if (id == 38)
      evidence = count((c) =>
          c.appreciations.contains(id) &&
          answered(c) &&
          c.prompt!.category == 'Pelepasan');
    if (const [44, 45].contains(id))
      evidence = count(
          (c) => c.appreciations.contains(id) && c.selfNote.trim().isNotEmpty);
    if (id == 28)
      evidence = count((c) =>
          c.appreciations.contains(id) &&
          c.inVault &&
          c.text.trim().isNotEmpty);
    if (id == 97 || id == 98)
      evidence = entries.where((e) {
        final c = DiaryContent.parse(e.note),
            weekday = toWib(e.createdAt).weekday;
        return c.appreciations.contains(id) &&
            c.text.trim().isNotEmpty &&
            (id == 97 ? weekday == 1 : weekday >= 6);
      }).length;
    v(id, evidence);
  }
  return diaryBadges.map((b) {
    final p = values[b.id] ?? (0, 1);
    return DiaryBadgeProgress(b, max(0, p.$1), p.$2);
  }).toList();
}
