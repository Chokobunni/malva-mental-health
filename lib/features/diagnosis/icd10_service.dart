import 'dart:convert';

import 'package:flutter/services.dart';

class Icd10Diagnosis {
  const Icd10Diagnosis({
    required this.code,
    required this.codeClean,
    required this.title,
    required this.keywords,
    required this.type,
  });

  factory Icd10Diagnosis.fromJson(Map<String, dynamic> json) => Icd10Diagnosis(
        code: json['code'] as String,
        codeClean: json['code_clean'] as String,
        title: json['title'] as String,
        keywords: List<String>.unmodifiable(json['keywords'] as List),
        type: json['type'] as String,
      );

  final String code;
  final String codeClean;
  final String title;
  final List<String> keywords;
  final String type;
  String get system => 'http://hl7.org/fhir/sid/icd-10';

  Map<String, dynamic> toJson() => {
        'code': code,
        'code_clean': codeClean,
        'title': title,
        'keywords': keywords,
        'type': type,
        'system': system,
      };
}

class Icd10Service {
  static const _assetPath = 'assets/data/mh_icd10_id_en.json';
  static const _resultLimit = 25;
  static final _codeSeparators = RegExp(r'[.\s]');
  static List<Icd10Diagnosis>? _catalog;
  static Future<List<Icd10Diagnosis>>? _loading;

  Future<List<Icd10Diagnosis>> load() async {
    final cached = _catalog;
    if (cached != null) return cached;
    final request = _loading ??= _loadAsset();
    try {
      return _catalog = await request;
    } finally {
      if (identical(_loading, request)) _loading = null;
    }
  }

  static Future<List<Icd10Diagnosis>> _loadAsset() async {
    final rows =
        jsonDecode(await rootBundle.loadString(_assetPath, cache: false))
            as List;
    return List<Icd10Diagnosis>.unmodifiable(
      rows.map((row) => Icd10Diagnosis.fromJson(row as Map<String, dynamic>)),
    );
  }

  Future<List<Icd10Diagnosis>> search(String query) async {
    final catalog = await load();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return catalog.take(_resultLimit).toList(growable: false);
    }

    final code = normalized.replaceAll(_codeSeparators, '').toUpperCase();
    final codeMatches = <Icd10Diagnosis>[];
    final exactMatches = <Icd10Diagnosis>[];
    final partialMatches = <Icd10Diagnosis>[];
    for (final item in catalog) {
      if (code.isNotEmpty && item.codeClean.startsWith(code)) {
        codeMatches.add(item);
        continue;
      }
      final title = item.title.toLowerCase();
      final keywords = item.keywords.map((keyword) => keyword.toLowerCase());
      if (title == normalized || keywords.contains(normalized)) {
        exactMatches.add(item);
      } else if (title.contains(normalized) ||
          keywords.any((keyword) => keyword.contains(normalized))) {
        partialMatches.add(item);
      }
    }
    return [
      ...codeMatches,
      ...exactMatches,
      ...partialMatches,
    ].take(_resultLimit).toList(growable: false);
  }
}
