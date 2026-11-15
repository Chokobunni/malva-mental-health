import 'package:flutter/material.dart';
import '../models/diary_achievements.dart';
import '../widgets/diary_design.dart';

class DiaryBadgesScreen extends StatefulWidget {
  const DiaryBadgesScreen({super.key, required this.progress});
  final List<DiaryBadgeProgress> progress;
  @override
  State<DiaryBadgesScreen> createState() => _DiaryBadgesScreenState();
}

class _DiaryBadgesScreenState extends State<DiaryBadgesScreen> {
  String? _category;
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final unlocked = widget.progress.where((p) => p.unlocked).length;
    final visible = widget.progress.where((p) =>
        (_category == null || p.badge.category == _category) &&
        '${p.badge.title} ${p.badge.description}'
            .toLowerCase()
            .contains(_query));
    return DiaryTheme(
        child: Scaffold(
            backgroundColor: diaryPaper,
            body: SafeArea(
                child: ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                  DiaryHeader(
                      unlocked: unlocked, onBack: () => Navigator.pop(context)),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton.icon(
                                      onPressed: () => Navigator.pop(context),
                                      icon: const Icon(Icons.chevron_left,
                                          size: 18),
                                      label: const Text('Kembali ke Diari',
                                          style: TextStyle(fontSize: 11))),
                                  const Text('Lencana Apresiasi Diri',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: diaryPlum))
                                ]),
                            const SizedBox(height: 16),
                            DiaryCard(
                                color: const Color(0xfffdfaff),
                                child: Column(children: [
                                  const CircleAvatar(
                                      backgroundColor: Color(0xfffef9c3),
                                      radius: 25,
                                      child: Icon(Icons.star_rounded,
                                          color: Color(0xffca8a04), size: 30)),
                                  const SizedBox(height: 14),
                                  Text('$unlocked dari 100 Lencana Terbuka',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15)),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'Penghargaan atas proses dan keberanianmu mencatat perasaan',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xff6b7280),
                                          height: 1.5)),
                                  const SizedBox(height: 12),
                                  LinearProgressIndicator(
                                      value: unlocked / 100,
                                      borderRadius: BorderRadius.circular(8),
                                      color: diaryPurple,
                                      backgroundColor: const Color(0xfff2e2f3)),
                                  const SizedBox(height: 12),
                                  const Text(
                                      'Tak perlu berturut-turut. Setiap langkah kecil tetap berarti.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 11, color: diaryPlum))
                                ])),
                            const SizedBox(height: 16),
                            ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text('Cari atau filter lencana',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                                children: [
                                  TextField(
                                      onChanged: (s) => setState(() =>
                                          _query = s.trim().toLowerCase()),
                                      decoration: const InputDecoration(
                                          hintText: 'Cari lencana',
                                          prefixIcon: Icon(Icons.search))),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                      initialValue: _category,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                          labelText: 'Kategori apresiasi'),
                                      items: [
                                        const DropdownMenuItem(
                                            value: null,
                                            child: Text('Semua kategori')),
                                        ...widget.progress
                                            .map((p) => p.badge.category)
                                            .toSet()
                                            .map((c) => DropdownMenuItem(
                                                value: c,
                                                child: Text(c,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 12))))
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _category = v)),
                                ]),
                            const SizedBox(height: 16),
                            if (visible.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                      'Belum ada lencana yang cocok dengan pencarian.')),
                            for (final p in visible)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: DiaryCard(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                                width: 46,
                                                height: 46,
                                                decoration: BoxDecoration(
                                                    color: p.unlocked
                                                        ? const Color(
                                                            0xfff3e8ff)
                                                        : const Color(
                                                            0xfff3f4f6),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            16)),
                                                child: Icon(
                                                    p.unlocked
                                                        ? Icons
                                                            .auto_awesome_outlined
                                                        : Icons.lock_outline,
                                                    color: p.unlocked
                                                        ? diaryPurple
                                                        : const Color(
                                                            0xff9ca3af),
                                                    size: 22)),
                                            const SizedBox(width: 14),
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Expanded(
                                                            child: Text(
                                                                p.badge.title,
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                    height:
                                                                        1.4))),
                                                        const SizedBox(
                                                            width: 6),
                                                        Text(
                                                            p.unlocked
                                                                ? 'Terbuka'
                                                                : '${p.current.clamp(0, p.target)}/${p.target}',
                                                            style: TextStyle(
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: p.unlocked
                                                                    ? const Color(
                                                                        0xff047857)
                                                                    : Colors
                                                                        .grey))
                                                      ]),
                                                  const SizedBox(height: 6),
                                                  Text(p.badge.description,
                                                      style: const TextStyle(
                                                          fontSize: 10,
                                                          color:
                                                              Color(0xff6b7280),
                                                          height: 1.5)),
                                                  const SizedBox(height: 8),
                                                  LinearProgressIndicator(
                                                      value: p.fraction,
                                                      minHeight: 3,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              3),
                                                      color: p.unlocked
                                                          ? const Color(
                                                              0xff6abca1)
                                                          : diaryPurple,
                                                      backgroundColor:
                                                          const Color(
                                                              0xfff3edf5))
                                                ]))
                                          ])))
                          ]))
                ]))));
  }
}
