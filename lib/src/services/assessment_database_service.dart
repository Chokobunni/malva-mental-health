import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../assessment_engine.dart';
import '../models.dart';

/// Penyimpanan lokal riwayat asesmen (PHQ-9 / GAD-7) per akun.
///
/// Data disimpan sebagai JSON pada [FlutterSecureStorage] dengan kunci
/// `malva_assessments_<accountId>` agar antar akun tidak bocor (selaras
/// dengan pola `offline_sync_service`). Bila platform channel tidak
/// tersedia (unit test / storage terkunci), semua operasi gagal diam-diam
/// dan mengembalikan kondisi kosong.
class AssessmentDatabaseService {
  AssessmentDatabaseService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'malva_assessments_';

  String _keyFor(String accountId) => '$_keyPrefix$accountId';

  /// Simpan seluruh riwayat asesmen akun [accountId] (timpa yang lama).
  Future<void> saveAll(
    String accountId,
    List<AssessmentResult> results,
  ) async {
    if (accountId.isEmpty) return;
    try {
      final data = jsonEncode(results.map(_resultToJson).toList());
      await _storage.write(key: _keyFor(accountId), value: data);
    } on Object {
      // Storage tidak tersedia (test/offline): abaikan.
    }
  }

  /// Muat riwayat asesmen akun [accountId] (kosong bila tidak ada/gagal).
  Future<List<AssessmentResult>> loadAll(String accountId) async {
    if (accountId.isEmpty) return const [];
    try {
      final raw = await _storage.read(key: _keyFor(accountId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => _resultFromJson(Map<String, dynamic>.from(m)))
          .whereType<AssessmentResult>()
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  /// Hapus semua data lokal akun [accountId].
  Future<void> clear(String accountId) async {
    if (accountId.isEmpty) return;
    try {
      await _storage.delete(key: _keyFor(accountId));
    } on Object {
      // Storage tidak tersedia: abaikan.
    }
  }

  static Map<String, dynamic> _resultToJson(AssessmentResult r) => {
        'type': r.type.name,
        'score': r.score,
        'maxScore': r.maxScore,
        'level': r.level.name,
        'summary': r.summary,
        'crisisFlag': r.crisisFlag,
        'certaintyFactor': r.certaintyFactor,
        'createdAt': r.createdAt.toIso8601String(),
        'ruleVersion': r.ruleVersion,
        'rulesFired': [
          for (final t in r.rulesFired)
            {'id': t.id, 'label': t.label, 'level': t.level.name},
        ],
      };

  static AssessmentResult? _resultFromJson(Map<String, dynamic> json) {
    try {
      final type = AssessmentType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AssessmentType.phq9,
      );
      final level = RiskLevel.values.firstWhere(
        (l) => l.name == json['level'],
        orElse: () => RiskLevel.minimal,
      );
      final rulesRaw = json['rulesFired'];
      final rules = <RuleTrace>[
        if (rulesRaw is List)
          for (final r in rulesRaw.whereType<Map>())
            RuleTrace(
              id: r['id']?.toString() ?? '',
              label: r['label']?.toString() ?? '',
              level: RiskLevel.values.firstWhere(
                (l) => l.name == r['level'],
                orElse: () => RiskLevel.minimal,
              ),
            ),
      ];
      return AssessmentResult(
        type: type,
        score: (json['score'] as num?)?.toInt() ?? 0,
        maxScore: (json['maxScore'] as num?)?.toInt() ?? 0,
        level: level,
        summary: json['summary']?.toString() ?? '',
        crisisFlag: json['crisisFlag'] == true,
        rulesFired: rules,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        ruleVersion: json['ruleVersion']?.toString() ?? '',
        certaintyFactor: (json['certaintyFactor'] as num?)?.toDouble() ?? 0.0,
      );
    } on Object {
      return null;
    }
  }
}
