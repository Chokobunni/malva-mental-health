import 'package:flutter/material.dart';
import '../models.dart';
import '../time/wib.dart';

/// Read the snapshot that was actually shared, including older message formats.
class SharedRecordDetail extends StatelessWidget {
  const SharedRecordDetail({super.key, required this.message});
  final ChatMessage message;

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

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Detail record dibagikan',
              style: Theme.of(context).textTheme.titleLarge),
          Text(formatWibDateTime(message.timestamp)),
          const SizedBox(height: 12),
          SelectableText(message.text),
          ..._fields(message.metadata ?? const {}),
          if ((message.metadata ?? const {}).isEmpty ||
              (message.kind == 'diary' &&
                  !(message.metadata ?? const {}).containsKey('note') &&
                  !(message.metadata ?? const {}).containsKey('content')))
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child:
                    Text('Record lama hanya menyimpan teks yang dibagikan.')),
        ],
      );
}
