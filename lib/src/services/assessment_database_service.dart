import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../assessment_engine.dart';
import '../models.dart';
import '../time/wib.dart';

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
        'createdAt': wibIso(r.createdAt),
        'ruleVersion': r.ruleVersion,
        'rulesFired': [
          for (final t in r.rulesFired)
            {'id': t.id, 'label': t.label, 'level': t.level.name},
        ],
      };

  /// Level cadangan bila nama level tersimpan tidak dikenali (mis. data
  /// ditulis versi aplikasi yang lebih baru). Diturunkan dari skor memakai
  /// band baku — BUKAN default ke 'minimal', karena itu menurunkan derajat
  /// pasien secara diam-diam.
  static RiskLevel _levelFromScore(AssessmentType type, int score) {
    if (type == AssessmentType.phq9) {
      if (score >= 20) return RiskLevel.severe;
      if (score >= 15) return RiskLevel.moderatelySevere;
      if (score >= 10) return RiskLevel.moderate;
      if (score >= 5) return RiskLevel.mild;
      return RiskLevel.minimal;
    }
    if (score >= 15) return RiskLevel.severe;
    if (score >= 10) return RiskLevel.moderate;
    if (score >= 5) return RiskLevel.mild;
    return RiskLevel.minimal;
  }

  static AssessmentResult? _resultFromJson(Map<String, dynamic> json) {
    try {
      final type = AssessmentType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AssessmentType.phq9,
      );
      final score = (json['score'] as num?)?.toInt() ?? 0;
      final level = RiskLevel.values.firstWhere(
        (l) => l.name == json['level'],
        orElse: () => _levelFromScore(type, score),
      );
      final rulesRaw = json['rulesFired'];
      final rules = <RuleTrace>[
        if (rulesRaw is List)
          for (final r in rulesRaw.whereType<Map>())
            RuleTrace(
              id: r['id']?.toString() ?? '',
              label: r['label']?.toString() ?? '',
              // Level pada jejak rule hanya metadata audit (bukan klasifikasi
              // pasien), jadi fallback minimal di sini tidak berbahaya.
              level: RiskLevel.values.firstWhere(
                (l) => l.name == r['level'],
                orElse: () => RiskLevel.minimal,
              ),
            ),
      ];
      return AssessmentResult(
        type: type,
        score: score,
        maxScore: (json['maxScore'] as num?)?.toInt() ?? 0,
        level: level,
        summary: json['summary']?.toString() ?? '',
        crisisFlag: json['crisisFlag'] == true,
        rulesFired: rules,
        createdAt: parseWibStored(json['createdAt']?.toString()) ?? wibNow(),
        ruleVersion: json['ruleVersion']?.toString() ?? '',
        certaintyFactor: (json['certaintyFactor'] as num?)?.toDouble() ?? 0.0,
      );
    } on Object {
      return null;
    }
  }
}
