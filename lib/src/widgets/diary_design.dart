import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../models/diary_content.dart';
import '../models/diary_catalog.dart';
import '../models/diary_achievements.dart';
import '../time/wib.dart';

const diaryPurple = Color(0xff8c4393),
    diaryPlum = Color(0xff5f2568),
    diaryPaper = Color(0xfffaf7fb);
const diaryMonths = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember'
];
const diaryPalettes = <String, (String, Color, Color)>{
  'cerah': ('Cerah', Color(0xfffde047), Color(0xff713f12)),
  'teduh': ('Teduh', Color(0xffbfece4), Color(0xff065f46)),
  'netral': ('Netral', Color(0xffe0e7ff), Color(0xff3730a3)),
  'redup': ('Redup', Color(0xfffed7aa), Color(0xff9a3412)),
  'sendu': ('Sendu', Color(0xfffecdd3), Color(0xff9f1239)),
};
String diaryDate(DateTime date) {
  final d = toWib(date);
  return '${d.day} ${diaryMonths[d.month - 1]} ${d.year}';
}

Color diaryEditorPaper(String? palette) => switch (palette) {
      'cerah' => const Color(0xfffffdf0),
      'teduh' => const Color(0xfff2f9f6),
      'netral' => const Color(0xfff4f5fd),
      'redup' => const Color(0xfffff6ee),
      'sendu' => const Color(0xfffff3f5),
      _ => const Color(0xfff6effa)
    };

class DiaryTheme extends StatelessWidget {
  const DiaryTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
        data: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Inter'),
          splashFactory: InkRipple.splashFactory,
          colorScheme: theme.colorScheme.copyWith(primary: diaryPurple),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  backgroundColor: diaryPurple,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)))),
        ),
        child: child);
  }
}

class DiaryCard extends StatelessWidget {
  const DiaryCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20),
      this.radius = 26,
      this.color = Colors.white});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0xfff1e6f5)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0f622774), blurRadius: 20, offset: Offset(0, 4))
          ]),
      child: child);
}

class DiaryHeader extends StatelessWidget {
  const DiaryHeader(
      {super.key, required this.unlocked, this.onBadges, this.onBack});
  final int unlocked;
  final VoidCallback? onBadges, onBack;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff622774), Color(0xffc56cd6)]),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(32))),
      child: Row(children: [
        InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(16),
            child: Tooltip(
                message: onBack == null ? 'Ruang Cerita & Diari' : 'Kembali',
                child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.menu_book_outlined,
                        color: Colors.white, size: 24)))),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ruang Cerita & Diari',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.2)),
          const SizedBox(height: 4),
          Text('Catatan perjalanan pikiran & kenangan baik',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: .85),
                  height: 1.4))
        ])),
        const SizedBox(width: 8),
        Semantics(
            button: true,
            label: 'Lencana Apresiasi Diri, $unlocked dari 100 terbuka',
            child: InkWell(
                key: const ValueKey('diary-badges-header'),
                onTap: onBadges,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(16)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded,
                          color: Color(0xfffde047), size: 21),
                      const SizedBox(width: 6),
                      Text('$unlocked/100',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10))
                    ]))))
      ]));
}

class DiaryPalettePill extends StatelessWidget {
  const DiaryPalettePill(
      {super.key,
      required this.palette,
      this.selected = false,
      this.onTap,
      this.bullet = false});
  final String? palette;
  final bool selected, bullet;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final meta = diaryPalettes[palette];
    return Semantics(
        selected: selected,
        button: onTap != null,
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: meta?.$2 ?? const Color(0xfff3f4f6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: selected ? diaryPurple : Colors.transparent,
                        width: 2)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (bullet) ...[
                    Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: meta?.$3 ?? Colors.grey)),
                    const SizedBox(width: 6)
                  ],
                  Text(meta?.$1 ?? 'Tanpa palet',
                      style: TextStyle(
                          color: meta?.$3 ?? Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.w700))
                ]))));
  }
}

class DiaryVaultCard extends StatelessWidget {
  const DiaryVaultCard(
      {super.key,
      required this.count,
      required this.onRandom,
      required this.onAll,
      this.vaultOnly = false});
  final int count;
  final bool vaultOnly;
  final VoidCallback onRandom, onAll;
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff6e2b7e), Color(0xffb55cc4)])),
          child: Stack(children: [
            Positioned(
                top: -38,
                right: -35,
                child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: .1)))),
            Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .2),
                                    borderRadius: BorderRadius.circular(16)),
                                child: const Icon(Icons.bookmark,
                                    color: Colors.white, size: 22)),
                            const SizedBox(width: 12),
                            const Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text('POSITIVE VAULT',
                                      style: TextStyle(
                                          color: Color(0xffe9d5ff),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: .6)),
                                  SizedBox(height: 4),
                                  Text('Kotak Kenangan Baik & Syukur',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          height: 1.35,
                                          fontWeight: FontWeight.w800))
                                ])),
                            const SizedBox(width: 8),
                            if (!_compact(context)) _countChip()
                          ]),
                      if (_compact(context))
                        Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _countChip())),
                      const SizedBox(height: 18),
                      const Text(
                          'Saat hari terasa berat, buka kembali catatan positif yang pernah kamu tulis sebagai pengingat bahwa kamu sudah melangkah sejauh ini.',
                          style: TextStyle(
                              color: Color(0xfff3e8ff),
                              fontSize: 12,
                              height: 1.65)),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(
                            flex: 68,
                            child: FilledButton.icon(
                                onPressed: onRandom,
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: diaryPlum,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 13),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(13))),
                                icon: const Icon(Icons.bookmark, size: 14),
                                label: const Text('Acak Kenangan Baik',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800)))),
                        const SizedBox(width: 9),
                        Expanded(
                            flex: 32,
                            child: TextButton(
                                onPressed: onAll,
                                style: TextButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: .2),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 13),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(13))),
                                child: Text(
                                    vaultOnly ? 'Semua Diari' : 'Lihat Semua',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800))))
                      ])
                    ]))
          ])));
  bool _compact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 350 ||
      MediaQuery.textScalerOf(context).scale(1) > 1.2;
  Widget _countChip() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .2),
          borderRadius: BorderRadius.circular(20)),
      child: Text('$count Tersimpan',
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)));
}

class DailyPromptCards extends StatefulWidget {
  const DailyPromptCards(
      {super.key,
      required this.onAnswer,
      this.onRefresh,
      this.onClose,
      this.draw});
  final ValueChanged<DiaryPrompt> onAnswer;
  final VoidCallback? onRefresh, onClose;
  final Future<List<DiaryPrompt>> Function()? draw;
  @override
  State<DailyPromptCards> createState() => _DailyPromptCardsState();
}

class _DailyPromptCardsState extends State<DailyPromptCards> {
  final _deck = DiaryPromptDeck();
  List<DiaryPrompt> _cards = [];
  int? _selected;
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      final List<DiaryPrompt> cards;
      if (widget.draw != null) {
        cards = await widget.draw!();
      } else {
        if (refresh) _deck.refresh();
        cards = [..._deck.cards];
      }
      if (!mounted) return;
      setState(() => _cards = cards);
      if (refresh) widget.onRefresh?.call();
    } on Object {
      if (mounted)
        setState(() => _error =
            'Kartu belum dapat dimuat. Ketuk refresh untuk mencoba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => DiaryCard(
      padding: const EdgeInsets.all(14),
      color: const Color(0xfffcf7ff),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: const Color(0xffefe0f4),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.event_note_outlined,
                  color: diaryPurple, size: 24)),
          Container(
              width: 1,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              color: const Color(0xffe4d2ec)),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Pertanyaan Harian',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: diaryPlum)),
                SizedBox(height: 4),
                Text('Pilih satu kartu, beri ruang untuk ceritamu.',
                    style: TextStyle(
                        fontSize: 10, height: 1.4, color: Color(0xff6b7280)))
              ])),
          IconButton.filledTonal(
              tooltip: 'Ganti pertanyaan baru',
              style: IconButton.styleFrom(
                  backgroundColor: const Color(0xffefe0f4),
                  foregroundColor: diaryPurple,
                  minimumSize: const Size(32, 32),
                  padding: const EdgeInsets.all(6)),
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: const Icon(Icons.refresh, size: 22)),
          if (widget.onClose != null)
            IconButton(
                tooltip: 'Tutup kartu pertanyaan',
                onPressed: widget.onClose,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
                icon: const Icon(Icons.close, size: 20, color: diaryPurple))
        ]),
        const SizedBox(height: 16),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!, style: const TextStyle(fontSize: 11, color: diaryPlum)),
        if (!_loading && _error == null)
          Row(children: [
            for (var i = 0; i < _cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                  child: Semantics(
                      button: true,
                      selected: _selected == i,
                      label:
                          'Kartu pertanyaan ${i + 1}, ${_selected == i ? 'terbuka' : 'tertutup'}',
                      child: InkWell(
                          key: ValueKey('prompt-card-$i'),
                          onTap: () => setState(() => _selected = i),
                          borderRadius: BorderRadius.circular(16),
                          child: TweenAnimationBuilder<double>(
                              tween: Tween(end: _selected == i ? math.pi : 0),
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 450),
                              builder: (context, angle, _) => Transform(
                                  alignment: Alignment.center,
                                  transform: Matrix4.identity()
                                    ..setEntry(3, 2, .001)
                                    ..rotateY(angle),
                                  child: Container(
                                      height: 74,
                                      decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: angle < math.pi / 2
                                                  ? const [
                                                      Color(0xffb77ac5),
                                                      Color(0xff9c56ae)
                                                    ]
                                                  : const [
                                                      Color(0xfff2e2f3),
                                                      Color(0xfffaf5ff)
                                                    ]),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border:
                                              Border.all(color: Colors.white),
                                          boxShadow: const [
                                            BoxShadow(
                                                color: Color(0x33622774),
                                                blurRadius: 8,
                                                offset: Offset(0, 4))
                                          ]),
                                      child: Transform(
                                          alignment: Alignment.center,
                                          transform: Matrix4.rotationY(
                                              angle >= math.pi / 2
                                                  ? math.pi
                                                  : 0),
                                          child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child:
                                                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                Icon(
                                                    angle < math.pi / 2
                                                        ? Icons
                                                            .auto_awesome_outlined
                                                        : Icons
                                                            .chat_bubble_outline,
                                                    color: angle < math.pi / 2
                                                        ? Colors.white
                                                        : diaryPurple,
                                                    size: 25),
                                                const SizedBox(height: 5),
                                                Flexible(
                                                    child: Text(
                                                        angle < math.pi / 2
                                                            ? '${i + 1}'
                                                            : _cards[i]
                                                                .category,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                            fontSize: angle <
                                                                    math.pi / 2
                                                                ? 21
                                                                : 9,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: angle <
                                                                    math.pi / 2
                                                                ? Colors.white
                                                                : diaryPlum)))
                                              ])))))))))
            ]
          ]),
        if (_selected != null && !_loading && _error == null) ...[
          const SizedBox(height: 14),
          Text('“${_cards[_selected!].question}”',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                  color: diaryPlum)),
          const SizedBox(height: 10),
          Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: () => widget.onAnswer(_cards[_selected!]),
                  child: const Text('Jawab di Diari')))
        ]
      ]));
}

class DiaryCalendar extends StatelessWidget {
  const DiaryCalendar(
      {super.key,
      required this.month,
      required this.entries,
      required this.onMonth,
      required this.onDay,
      required this.onPalette,
      this.palette,
      this.selectedDay});
  final DateTime month;
  final List<DiaryEntry> entries;
  final ValueChanged<int> onMonth;
  final ValueChanged<DateTime> onDay;
  final ValueChanged<String?> onPalette;
  final String? palette, selectedDay;
  @override
  Widget build(BuildContext context) {
    final first = wibFromParts(month.year, month.month, 1),
        length = wibFromParts(month.year, month.month + 1, 0).day;
    final offset = first.weekday % 7;
    final byDay = <int, List<DiaryEntry>>{};
    for (final e in entries) {
      final d = toWib(e.createdAt);
      if (d.year == month.year && d.month == month.month) {
        (byDay[d.day] ??= []).add(e);
      }
    }
    return DiaryCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: const Color(0xfffcf5ff),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.calendar_month_outlined,
                color: diaryPurple, size: 22)),
        const SizedBox(width: 12),
        const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('PALET WARNA DIARI',
              style: TextStyle(
                  fontSize: 10,
                  color: diaryPlum,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5)),
          SizedBox(height: 4),
          Text('Ketuk tanggal berwarna untuk membuka cerita pada hari tersebut',
              style: TextStyle(
                  fontSize: 11, color: Color(0xff6b7280), height: 1.4))
        ]))
      ]),
      const SizedBox(height: 12),
      Row(children: [
        IconButton(
            tooltip: 'Bulan sebelumnya',
            onPressed: () => onMonth(-1),
            icon: const Icon(Icons.chevron_left, size: 20)),
        Expanded(
            child: Text('${diaryMonths[month.month - 1]} ${month.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800))),
        IconButton(
            tooltip: 'Bulan berikutnya',
            onPressed: () => onMonth(1),
            icon: const Icon(Icons.chevron_right, size: 20))
      ]),
      Row(children: [
        for (final day in ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'])
          Expanded(
              child: Text(day,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xff6b7280))))
      ]),
      const SizedBox(height: 8),
      for (var week = 0; week < (offset + length) / 7; week++)
        Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: Builder(builder: (context) {
                  final day = week * 7 + col - offset + 1;
                  if (day < 1 || day > length)
                    return const SizedBox(height: 40);
                  final records = byDay[day] ?? const <DiaryEntry>[];
                  final palettes = records
                      .map((e) => DiaryContent.parse(e.note).palette)
                      .whereType<String>()
                      .toSet()
                      .toList();
                  final colors =
                      palettes.map((p) => diaryPalettes[p]!.$2).toList();
                  final date = wibFromParts(month.year, month.month, day),
                      isSelected = selectedDay == diaryDay(date);
                  return Semantics(
                      button: records.isNotEmpty,
                      label: '${diaryDate(date)}, ${records.length} cerita',
                      child: InkWell(
                          onTap: records.isEmpty ? null : () => onDay(date),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                              key: ValueKey('diary-date-${diaryDay(date)}'),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              constraints: const BoxConstraints(minHeight: 40),
                              decoration: BoxDecoration(
                                  color: colors.isNotEmpty
                                      ? colors.first
                                      : records.isEmpty
                                          ? Colors.transparent
                                          : const Color(0xfff0e5f3),
                                  gradient: colors.length > 1
                                      ? LinearGradient(colors: [
                                          for (final color in colors) ...[
                                            color,
                                            color
                                          ]
                                        ], stops: [
                                          for (var i = 0;
                                              i < colors.length;
                                              i++) ...[
                                            i / colors.length,
                                            (i + 1) / colors.length
                                          ]
                                        ])
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isSelected
                                      ? Border.all(color: diaryPurple, width: 2)
                                      : null),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('$day',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: palettes.isEmpty
                                                ? const Color(0xff374151)
                                                : diaryPalettes[palettes.first]!
                                                    .$3,
                                            fontWeight: records.isEmpty
                                                ? FontWeight.w400
                                                : FontWeight.w700)),
                                    SizedBox(
                                        height: 7,
                                        child: records.any((e) =>
                                                DiaryContent.parse(e.note)
                                                    .inVault)
                                            ? const Icon(Icons.circle,
                                                size: 4, color: diaryPurple)
                                            : null)
                                  ]))));
                }))
            ])),
      const Divider(height: 24, color: Color(0xfff3f4f6)),
      const Text('Filter berdasarkan nuansa cerita hari:',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: Color(0xff6b7280))),
      const SizedBox(height: 8),
      Wrap(
          alignment: WrapAlignment.center,
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final key in diaryPalettes.keys)
              DiaryPalettePill(
                  palette: key,
                  bullet: true,
                  selected: palette == key,
                  onTap: () => onPalette(palette == key ? null : key))
          ]),
      const SizedBox(height: 10),
      const Text(
          'Tanggal berwarna = diari tercatat • Titik ungu = tersimpan di Vault',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9, color: Color(0xff9ca3af), height: 1.5))
    ]));
  }
}
