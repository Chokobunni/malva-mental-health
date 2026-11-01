import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

// ============================================================
// BUG 1 — atribusi penulis diagnosis.
// `authorName` HARUS murni dari `updatedBy` (audit_logs.actor_id).
// `primaryProfessional` (link aktif pertama) TIDAK boleh dipakai sebagai
// penulis: profesional yang lebih dulu terhubung bukan berarti yang menulis
// diagnosis. Saat `updatedBy` kosong, UI tidak boleh menampilkan nama orang.
// ============================================================

void main() {
  group('BackendHealthRecord.authorName', () {
    test('memakai updatedBy bila tersedia (bukan primaryProfessional)', () {
      const rec = BackendHealthRecord(
        patientId: 'p1',
        diagnosisSummary: 'F31.3',
        hasDiagnosis: true,
        primaryProfessional: 'Andi Wijaya, M.Psi',
        updatedBy: 'dr. Hafid Algistian, Sp.KJ',
      );
      expect(rec.authorName, 'dr. Hafid Algistian, Sp.KJ');
    });

    test('kosong saat updatedBy kosong walau primaryProfessional terisi', () {
      const rec = BackendHealthRecord(
        patientId: 'p1',
        diagnosisSummary: 'F31.3',
        hasDiagnosis: true,
        primaryProfessional: 'Andi Wijaya, M.Psi',
        updatedBy: '',
      );
      // Tidak boleh fallback ke primaryProfessional (fabrikasi atribusi).
      expect(rec.authorName, isEmpty);
    });

    test('fromJson: updated_by kosong → authorName kosong', () {
      final rec = BackendHealthRecord.fromJson(const {
        'patient_id': 'p1',
        'diagnosis_summary': 'F31.3',
        'has_diagnosis': true,
        'primary_professional': 'Andi Wijaya, M.Psi',
        'updated_by': '',
      });
      expect(rec.primaryProfessional, 'Andi Wijaya, M.Psi');
      expect(rec.authorName, isEmpty);
    });

    test('fromJson: updated_by terisi → authorName = updated_by', () {
      final rec = BackendHealthRecord.fromJson(const {
        'patient_id': 'p1',
        'diagnosis_summary': 'F31.3',
        'has_diagnosis': true,
        'primary_professional': 'Andi Wijaya, M.Psi',
        'updated_by': 'dr. Hafid Algistian, Sp.KJ',
      });
      expect(rec.authorName, 'dr. Hafid Algistian, Sp.KJ');
    });
  });
}
