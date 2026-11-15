import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/models/diary_catalog.dart';
import 'package:malva_mental_health/src/models/diary_achievements.dart';
import 'package:malva_mental_health/src/time/wib.dart';

DiaryEntry story(int id, int day, {DiaryContent? content}) => DiaryEntry(
    id: '$id',
    createdAt: wibFromParts(2026, 11, day, 21),
    mood: MoodValue.sad,
    title: 'Cerita $id',
    note: (content ?? const DiaryContent(text: 'Aku bercerita.')).encode());

void main() {
  test(
      'limited-energy and before-rest badges need patient evidence and structural checks',
      () {
    DiaryEntry entry(String text, List<int> evidence, {int prompt = 21}) =>
        story(1, 1,
            content: DiaryContent(
                text: text, promptId: prompt, appreciations: evidence));
    final without = evaluateDiaryBadges([entry('Catatan singkat.', [])]);
    expect(without[36].unlocked, false);
    expect(without[37].unlocked, false);
    final valid = evaluateDiaryBadges([
      entry('Catatan singkat.', [37, 38])
    ]);
    expect(valid[36].unlocked, true);
    expect(valid[37].unlocked, true);
    expect(
        evaluateDiaryBadges([
          entry('Satu. Dua. Tiga.', [37])
        ])[36]
            .unlocked,
        false);
    expect(
        evaluateDiaryBadges([
          entry('', [37, 38])
        ])[36]
            .unlocked,
        false);
    expect(
        evaluateDiaryBadges([
          entry('', [37, 38])
        ])[37]
            .unlocked,
        false);
    expect(
        evaluateDiaryBadges([
          entry('Jawabanku.', [38], prompt: 1)
        ])[37]
            .unlocked,
        false);
  });
  test('visit badge requires two real visit dates, not backdated diary dates',
      () {
    final entries = [story(1, 1), story(2, 10)];
    expect(evaluateDiaryBadges(entries)[1].unlocked, false);
    expect(
        evaluateDiaryBadges(entries, activities: {'visit:2026-11-14'})[1]
            .unlocked,
        false);
    expect(
        evaluateDiaryBadges(entries,
                activities: {'visit:2026-11-14', 'visit:2026-11-15'})[1]
            .unlocked,
        true);
  });
  test('each count badge opens at its threshold without a streak', () {
    for (final (id, target) in [
      (1, 1),
      (3, 3),
      (4, 5),
      (5, 10),
      (6, 20),
      (7, 50),
      (8, 100),
      (21, 1),
      (22, 3),
      (23, 10),
      (24, 25),
      (31, 1),
      (33, 15),
      (34, 30),
      (40, 10),
      (41, 1),
      (42, 5),
      (46, 15),
      (51, 1),
      (53, 5),
      (60, 10)
    ]) {
      final all = [
        for (var i = 0; i < target; i++)
          story(i, 1 + i * 4,
              content: DiaryContent(
                  text: 'Aku bercerita.',
                  promptId: 1,
                  selfNote: 'Aku cukup $i',
                  inVault: true,
                  media: [
                    DiaryMedia(url: '/v1/diary-media/p/$i.png', kind: 'drawing')
                  ]))
      ];
      expect(evaluateDiaryBadges(all)[id - 1].unlocked, true,
          reason: 'badge $id at $target');
      expect(
          evaluateDiaryBadges(all.take(target - 1).toList())[id - 1].unlocked,
          false,
          reason: 'badge $id below $target');
    }
  });
  test('every subjective badge requires explicit saved relevant evidence', () {
    for (final id in diarySubjectiveBadges) {
      // Monday for weekly intention; Saturday for weekend reflection.
      final day = id == 97 ? 2 : 7;
      final saved = story(1, day,
          content: DiaryContent(
              text: 'Pengalaman dalam cerita ini.',
              promptId: 21,
              selfNote: 'Aku cukup.',
              inVault: true,
              appreciations: [id]));
      expect(evaluateDiaryBadges([saved])[id - 1].unlocked, true,
          reason: 'badge $id');
      expect(evaluateDiaryBadges([story(1, day)])[id - 1].unlocked, false,
          reason: 'badge $id without selection');
    }
  });
  test(
      'monthly palette evidence is grouped by calendar month, distinct dates and colors',
      () {
    final entries = [
      for (var i = 1; i <= 15; i++)
        story(i, i,
            content: DiaryContent(
                text: 'Ceritaku',
                palette: ['cerah', 'teduh', 'netral', 'redup', 'sendu'][i % 5]))
    ];
    final result = evaluateDiaryBadges(entries);
    for (final id in [11, 12, 13, 14, 15, 18, 19, 20]) {
      expect(result[id - 1].unlocked, true, reason: 'badge $id');
    }
    final split = [
      for (var i = 0; i < 15; i++)
        story(i, 1 + i * 31,
            content: const DiaryContent(text: 'Ceritaku', palette: 'cerah'))
    ];
    expect(evaluateDiaryBadges(split)[19].unlocked, false);
  });
  test(
      'distinct reflection and affirmation counts do not duplicate identical content',
      () {
    final entries = [
      for (var i = 0; i < 5; i++)
        story(i, i + 1,
            content: const DiaryContent(
                text: 'Jawaban', promptId: 1, selfNote: 'Aku cukup.'))
    ];
    final result = evaluateDiaryBadges(entries);
    expect(result[31].current, 1);
    expect(result[41].current, 1);
    expect(result[30].unlocked, true);
  });
  test(
      'activity badges require recorded actions and never appear on content alone',
      () {
    const flags = {
      25: 'randomVault',
      26: 'hardDayVault',
      30: 'oldRead',
      35: 'refreshPrompt',
      68: 'colorFilter',
      69: 'adjacentRead',
      70: 'reviewFive'
    };
    final plain = evaluateDiaryBadges([story(1, 1)]),
        withEvents = evaluateDiaryBadges([story(1, 1)],
            activities: flags.values.toSet());
    for (final id in flags.keys) {
      expect(plain[id - 1].unlocked, false);
      expect(withEvents[id - 1].unlocked, true);
    }
  });
  test('midnight offsets use WIB calendar dates for day counts', () {
    final entries = [
      story(1, 1,
              content: const DiaryContent(text: 'Ceritaku', palette: 'cerah'))
          .copyWith(createdAt: DateTime.parse('2026-11-01T23:30:00+07:00')),
      story(2, 1,
              content: const DiaryContent(text: 'Ceritaku', palette: 'cerah'))
          .copyWith(createdAt: DateTime.parse('2026-11-02T00:30:00+08:00'))
    ];
    expect(evaluateDiaryBadges(entries)[16].current, 1);
  });
  test('multicolor badge uses three colors in one successfully saved drawing',
      () {
    final saved = story(1, 1,
        content: const DiaryContent(text: 'Cerita', media: [
          DiaryMedia(
              url: '/v1/diary-media/p/a.png',
              kind: 'drawing',
              colors: [1, 2, 3])
        ]));
    expect(evaluateDiaryBadges([saved])[54].unlocked, true);
    final separate = story(2, 1,
        content: const DiaryContent(text: 'Cerita', media: [
          DiaryMedia(
              url: '/v1/diary-media/p/a.png', kind: 'drawing', colors: [1]),
          DiaryMedia(
              url: '/v1/diary-media/p/b.png', kind: 'drawing', colors: [2, 3])
        ]));
    expect(evaluateDiaryBadges([separate])[54].unlocked, false);
  });
  test('PDF catalogues each have 100 ordered unique items in ten categories',
      () {
    expect(diaryPrompts.length, 100);
    expect(diaryBadges.length, 100);
    expect(diaryPrompts.map((p) => p.id).toSet().length, 100);
    expect(diaryPrompts.map((p) => p.category).toSet().length, 10);
    expect(diaryBadges.map((p) => p.category).toSet().length, 10);
    expect(diaryPrompts.first.question,
        'Apa satu hal kecil yang berhasil kamu lewati dengan tenang hari ini?');
    expect(diaryPrompts.last.question,
        'Langkah kecil apa hari ini yang membuatmu selangkah lebih dekat dengan ketenangan?');
    expect(diaryBadges.first.title, 'Langkah Pertama');
    expect(diaryBadges.last.title, 'Pejalan yang Tangguh');
  });
  test('all diary presentation metadata survives edits, legacy remains plain',
      () {
    const content = DiaryContent(
        text: 'Ceritaku',
        palette: 'sendu',
        promptId: 24,
        selfNote: 'Aku boleh pelan.',
        tags: ['Istirahat', 'Pulih'],
        inVault: true,
        appreciations: [48, 81],
        font: 'jakarta',
        align: TextAlign.center,
        media: [DiaryMedia(url: '/v1/diary-media/p/a.png')]);
    final parsed = DiaryContent.parse(content.encode());
    expect(parsed.palette, 'sendu');
    expect(parsed.promptId, 24);
    expect(parsed.selfNote, content.selfNote);
    expect(parsed.tags, content.tags);
    expect(parsed.appreciations, [48, 81]);
    expect(parsed.inVault, true);
    expect(parsed.copyWith(inVault: false).text, 'Ceritaku');
    expect(parsed.copyWith(inVault: false).media.single.url,
        content.media.single.url);
    expect(DiaryContent.parse('Tulisan lama').encode(), 'Tulisan lama');
    expect(parsed.plainText, contains(diaryPrompts[23].question));
    expect(parsed.plainText, isNot(contains('malva-diary-v1')));
  });
  test('three prompts are distinct and the whole pool is reached before repeat',
      () {
    final deck = DiaryPromptDeck(random: Random(7));
    final seen = <int>{...deck.cards.map((p) => p.id)};
    for (var i = 0; i < 97; i++) {
      deck.refresh(i % 3);
      expect(deck.cards.map((p) => p.id).toSet().length, 3);
      seen.add(deck.cards[i % 3].id);
    }
    expect(seen.length, 100);
    for (var i = 0; i < 100; i++) {
      deck.refresh(i % 3);
      expect(deck.cards.map((p) => p.id).toSet().length, 3);
    }
  });
  test('empty history unlocks nothing; gaps never erase total progress', () {
    expect(evaluateDiaryBadges([]).where((p) => p.unlocked), isEmpty);
    final result =
        evaluateDiaryBadges([story(1, 1), story(2, 8), story(3, 15)]);
    expect(result[0].unlocked, true);
    expect(result[2].unlocked, true);
    expect(result[8].unlocked, true);
    expect(result[4].unlocked, false);
    expect(result[99].unlocked, false);
  });
  test('palette days deduplicate dates and never use legacy mood as evidence',
      () {
    final entries = [
      for (var i = 0; i < 5; i++)
        story(i, 1,
            content: const DiaryContent(text: 'Cerita', palette: 'cerah'))
    ];
    expect(evaluateDiaryBadges(entries)[16].current, 1);
    expect(evaluateDiaryBadges([story(1, 1)])[12].unlocked, false);
  });
  test('question, vault, visual and subjective evidence comes from saved data',
      () {
    final entry = story(1, 1,
        content: const DiaryContent(
            text: 'Aku belum memaafkan diri.',
            promptId: 24,
            palette: 'sendu',
            inVault: true,
            appreciations: [
              81
            ],
            media: [
              DiaryMedia(url: '/v1/diary-media/p/a.png', kind: 'drawing')
            ]));
    final result = evaluateDiaryBadges([entry]);
    expect(result[20].unlocked, true);
    expect(result[30].unlocked, true);
    expect(result[50].unlocked, true);
    expect(result[80].unlocked, true);
    expect(result[47].unlocked,
        false); // Negation never becomes a psychological claim.
    final questionOnly =
        story(2, 2, content: const DiaryContent(text: '', promptId: 1));
    expect(evaluateDiaryBadges([questionOnly])[30].unlocked, false);
  });
}
