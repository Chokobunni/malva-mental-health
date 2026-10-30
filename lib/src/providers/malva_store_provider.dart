import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../assessment_engine.dart';
import '../models.dart';
import '../services/assessment_database_service.dart';
import '../services/malva_api_client.dart';
import 'auth_providers.dart';
import 'data/assessment_provider.dart';

const _sessionKey = 'malva_active_session';
const _continuousConsentKey = 'malva_continuous_support_consent';

/// Prefix cache lokal log minum obat per akun (`..._<backendUserId>`).
/// Selaras dengan isolasi per-akun yang dipakai sesi & consent di atas.
const _medicationLogsKeyPrefix = 'malva_medication_logs_';
const _secureStorage = FlutterSecureStorage();

/// Hasil penyimpanan screening.
///
/// [uploaded] hanya true bila server benar-benar menerima (mengembalikan ID).
/// Bila false, [bundle] tetap berisi hasil lokal sehingga skor bisa ditampilkan,
/// tetapi UI WAJIB memberi tahu bahwa profesional belum menerimanya.
class ScreeningSubmitResult {
  const ScreeningSubmitResult({
    required this.bundle,
    required this.uploaded,
    this.error,
  });

  final ScreeningBundle bundle;
  final bool uploaded;
  final String? error;
}

// ============================================================
// MALVA STORE STATE NOTIFIER
// ============================================================

class MalvaStoreState {
  final PatientProfile patient;
  final List<Medication> medications;
  final List<MedicationLog> medicationLogs;
  final List<MoodEntry> moodEntries;
  final List<DiaryEntry> diaryEntries;
  final List<GoalItem> goals;
  final List<HealthRecord> records;
  final List<AssessmentResult> assessments;
  final List<ScreeningBundle> screeningBundles;
  final InitialScreeningStatus initialScreeningStatus;

  const MalvaStoreState({
    required this.patient,
    this.medications = const [],
    this.medicationLogs = const [],
    this.moodEntries = const [],
    this.diaryEntries = const [],
    this.goals = const [],
    this.records = const [],
    this.assessments = const [],
    this.screeningBundles = const [],
    this.initialScreeningStatus = InitialScreeningStatus.pending,
  });

  bool get needsInitialScreeningDecision =>
      initialScreeningStatus == InitialScreeningStatus.pending;

  ScreeningBundle? get latestScreeningBundle =>
      screeningBundles.isEmpty ? null : screeningBundles.last;

  /// Persentase kepatuhan minum obat HARI INI.
  ///
  /// Aturan (jangan diubah tanpa alasan klinis): hanya log berstatus `taken`
  /// yang menaikkan kepatuhan. Status `partial`/`skipped`/`missed` TIDAK
  /// dihitung — meski `partial` tetap memotong stok di server, ia bukan dosis
  /// penuh sehingga tidak boleh membuat angka kepatuhan terlihat 100%.
  int get adherencePercent {
    if (medications.isEmpty) return 0;
    final today = DateTime.now();
    final todayLogs = medicationLogs
        .where((log) =>
            log.takenAt.day == today.day &&
            log.takenAt.month == today.month &&
            log.takenAt.year == today.year &&
            log.status == 'taken')
        .length;
    return ((todayLogs / medications.length) * 100).clamp(0, 100).round();
  }

  int get completedGoalPercent {
    if (goals.isEmpty) return 0;
    final done = goals.where((goal) => goal.completedToday).length;
    return ((done / goals.length) * 100).round();
  }

  List<String> get activeAlerts {
    final alerts = <String>[];
    for (final med in medications.where((med) => med.needsRefill)) {
      alerts.add('${med.name} tinggal ${med.currentStock}. Periksa refill.');
    }
    if (latestScreeningBundle?.crisisFlag == true ||
        (assessments.isNotEmpty && assessments.last.crisisFlag)) {
      alerts.add('Crisis flag aktif dari asesmen terbaru.');
    }
    return alerts;
  }

  MalvaStoreState copyWith({
    PatientProfile? patient,
    List<Medication>? medications,
    List<MedicationLog>? medicationLogs,
    List<MoodEntry>? moodEntries,
    List<DiaryEntry>? diaryEntries,
    List<GoalItem>? goals,
    List<HealthRecord>? records,
    List<AssessmentResult>? assessments,
    List<ScreeningBundle>? screeningBundles,
    InitialScreeningStatus? initialScreeningStatus,
  }) {
    return MalvaStoreState(
      patient: patient ?? this.patient,
      medications: medications ?? this.medications,
      medicationLogs: medicationLogs ?? this.medicationLogs,
      moodEntries: moodEntries ?? this.moodEntries,
      diaryEntries: diaryEntries ?? this.diaryEntries,
      goals: goals ?? this.goals,
      records: records ?? this.records,
      assessments: assessments ?? this.assessments,
      screeningBundles: screeningBundles ?? this.screeningBundles,
      initialScreeningStatus:
          initialScreeningStatus ?? this.initialScreeningStatus,
    );
  }
}

// ============================================================
// MALVA STORE NOTIFIER
// ============================================================

class MalvaStoreNotifier extends StateNotifier<MalvaStoreState> {
  final MalvaApiClient? _apiClient;
  final AssessmentDatabaseService _assessmentDb;

  MalvaStoreNotifier(this._apiClient, AssessmentDatabaseService? assessmentDb)
      : _assessmentDb = assessmentDb ?? AssessmentDatabaseService(),
        super(_seededState());

  static MalvaStoreState _seededState() {
    // Fresh start: TIDAK ada data demo (diagnosis, obat, mood, diary, goals,
    // record). Semua data berasal dari server per akun yang login — akun baru
    // melihat kondisi kosong sampai profesional mengisi diagnosis/obat.
    return const MalvaStoreState(
      patient: PatientProfile(
        id: 'patient_local',
        name: 'Pasien',
        age: 0,
        primaryProfessional: '',
        diagnosisSummary: '',
      ),
    );
  }

  // ============================================================
  // AUTH METHODS
  // ============================================================

  /// Reset seluruh data akun ke kondisi fresh (kosong). Dipanggil saat
  /// login akun baru & logout agar data akun sebelumnya tidak bocor.
  void resetForAccount() {
    __lastAccessToken = null;
    clearPendingDoses();
    state = _seededState();
  }

  /// Terapkan sesi login: reset data lama, lalu set nama tampilan akun.
  void applySession(AuthSession session) {
    final name = session.displayName.trim().isEmpty
        ? 'Pasien'
        : session.displayName.trim();
    // Dosis pending milik akun sebelumnya tidak boleh terbawa.
    clearPendingDoses();
    state = MalvaStoreState(
      patient: PatientProfile(
        id: session.backendUserId ?? 'patient_local',
        name: name,
        age: 0,
        primaryProfessional: '',
        diagnosisSummary: '',
      ),
    );
    // Simpan token akses untuk pemuatan data server nanti.
    __lastAccessToken = session.accessToken;
    // Muat riwayat asesmen lokal akun ini (fire-and-forget).
    loadAndSaveAssessmentsAsync();
    // Muat riwayat check-in dan obat dari server agar tidak hilang
    // setelah logout/login atau ganti perangkat (Bug #5a & #5b).
    _loadServerDataAsync(session);
  }

  /// Muat data dari server secara paralel setelah login (non-blocking).
  /// Kegagalan satu panggilan tidak menghalangi panggilan lain.
  Future<void> _loadServerDataAsync(AuthSession session) async {
    // Hidrasi cache log obat LOKAL lebih dulu agar riwayat kepatuhan tetap
    // tampil walau offline / server belum merespons (akar bug "adherence &
    // riwayat reset setelah logout/login"). Harus SEBELUM merge data server
    // supaya log lama server tidak salah dianggap lebih baru dari cache.
    await _hydrateMedicationLogsCache();

    final api = _apiClient;
    final token = session.accessToken;
    if (api == null || token == null || token.isEmpty) return;

    // Jalankan pemuatan secara paralel (mood, daftar obat, log obat).
    await Future.wait([
      loadCheckinHistory(api, token).catchError((_) {}),
      loadMedications(api, token).catchError((_) {}),
      loadMedicationLogs(api, token).catchError((_) {}),
    ]);
  }

  /// Muat riwayat check-in (mood) dari server dan isi store.
  /// Dipanggil saat login agar riwayat tidak hilang setelah logout/login.
  Future<void> loadCheckinHistory([
    MalvaApiClient? apiOverride,
    String? tokenOverride,
  ]) async {
    final api = apiOverride ?? _apiClient;
    if (api == null) return;
    final token = tokenOverride ?? _currentAccessToken;
    if (token == null || token.isEmpty) return;
    try {
      final moods = await api.listMoodCheckins(
        accessToken: token,
        limit: 30,
      );
      // Konversi BackendMoodCheckin → MoodEntry untuk store lokal.
      final entries = moods
          .where((m) => m.occurredAt != null)
          .map((m) => MoodEntry(
                date: m.occurredAt!,
                mood: _parseMoodValue(m.mood),
                sleepHours: m.sleepHours,
                energy: m.energy,
                anxiety: m.anxiety,
                irritability: m.irritability,
                note: m.note,
              ))
          .toList();
      replaceMoodEntries(entries);
    } on Object {
      // Gagal memuat (offline/server error): jangan halangi UI.
    }
  }

  /// Muat daftar obat dari server dan isi store.
  /// Dipanggil saat login agar obat dari resep muncul di daily check-in.
  Future<void> loadMedications([
    MalvaApiClient? apiOverride,
    String? tokenOverride,
  ]) async {
    final api = apiOverride ?? _apiClient;
    if (api == null) return;
    final token = tokenOverride ?? _currentAccessToken;
    if (token == null || token.isEmpty) return;
    try {
      final meds = await api.listMedications(
        accessToken: token,
        limit: 50,
      );
      // Konversi BackendMedication → Medication untuk store lokal.
      final medications = meds.map((m) {
        // Parse reminder_time menjadi MedicationReminder.
        final reminders = <MedicationReminder>[];
        if (m.reminderTime.isNotEmpty) {
          final parts = m.reminderTime.split(':');
          if (parts.length >= 2) {
            final hour = int.tryParse(parts[0]) ?? 8;
            final minute = int.tryParse(parts[1]) ?? 0;
            reminders.add(MedicationReminder(
              time: TimeOfDay(hour: hour, minute: minute),
              relationToMeal: '',
            ));
          }
        }
        return Medication(
          id: m.id,
          name: m.name,
          dosage: m.dosage,
          form: m.form,
          reminders: reminders,
          currentStock: m.currentStock,
          alertBelow: m.alertBelow,
          source: m.source,
        );
      }).toList();
      replaceMedications(medications);
    } on Object {
      // Gagal memuat (offline/server error): jangan halangi UI.
    }
  }

  /// Muat riwayat log minum obat dari server dan gabungkan ke store.
  ///
  /// Dipanggil saat login (dan setelah log baru diterima server) agar riwayat
  /// kepatuhan tidak hilang setelah logout/login atau ganti perangkat.
  /// `takenAt` di model backend bisa null; pakai `createdAt` sebagai fallback
  /// dan buang entri yang dua-duanya null (tidak bisa ditempatkan di tanggal).
  Future<void> loadMedicationLogs([
    MalvaApiClient? apiOverride,
    String? tokenOverride,
  ]) async {
    final api = apiOverride ?? _apiClient;
    if (api == null) return;
    final token = tokenOverride ?? _currentAccessToken;
    if (token == null || token.isEmpty) return;
    try {
      final logs = await api.listMedicationLogs(
        accessToken: token,
        limit: 50,
      );
      final mapped = <MedicationLog>[];
      for (final log in logs) {
        final takenAt = log.takenAt ?? log.createdAt;
        if (takenAt == null) continue; // buang entri tanpa waktu sama sekali
        mapped.add(MedicationLog(
          medicationId: log.medicationId,
          medicationName: log.medicationName,
          takenAt: takenAt,
          status: log.status,
        ));
      }
      replaceMedicationLogs(mapped);
    } on Object {
      // Gagal memuat (offline/server error): jangan halangi UI.
    }
  }

  /// Token akses terakhir yang diketahui (di-set saat applySession).
  String? get _currentAccessToken {
    // Ambil dari sesi yang tersimpan di secure storage secara sinkron
    // tidak mungkin, jadi kita simpan referensi saat applySession.
    return __lastAccessToken;
  }

  String? __lastAccessToken;

  /// Perbarui nama pasien di store (dipakai setelah profil dimuat server).
  void setPatientIdentity({String? name, String? primaryProfessional}) {
    state = state.copyWith(
      patient: PatientProfile(
        id: state.patient.id,
        name: (name ?? state.patient.name).trim().isEmpty
            ? 'Pasien'
            : (name ?? state.patient.name).trim(),
        age: state.patient.age,
        primaryProfessional:
            primaryProfessional ?? state.patient.primaryProfessional,
        diagnosisSummary: state.patient.diagnosisSummary,
      ),
    );
  }

  /// Perbarui diagnosis summary (dari Health Record server) untuk pasien.
  void setPatientDiagnosis(String diagnosis) {
    state = state.copyWith(
      patient: PatientProfile(
        id: state.patient.id,
        name: state.patient.name,
        age: state.patient.age,
        primaryProfessional: state.patient.primaryProfessional,
        diagnosisSummary: diagnosis,
      ),
    );
  }

  // ============================================================
  // AUTH METHODS — selalu ke server (tanpa sesi lokal palsu).
  // Error jaringan/server diteruskan apa adanya agar UI menampilkannya.
  // ============================================================

  static const _noServerFailure = AuthFailure(
    'Tidak terhubung ke server Malva. Periksa koneksi dan alamat server, lalu coba lagi.',
  );

  Future<AuthSession> loginPatientOnline({
    required String email,
    required String password,
  }) async {
    final api = _apiClient;
    if (api == null) throw _noServerFailure;
    try {
      final result = await api.login(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (result.role != UserRole.patient && result.role != UserRole.admin) {
        throw const AuthFailure('Akun ini bukan akun pasien.');
      }
      return AuthSession(
        role: result.role,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      throw _noServerFailure;
    }
  }

  Future<AuthSession> registerPatientOnline({
    required String email,
    required String password,
    required String displayName,
    String? phone,
    String? dateOfBirth,
    String? gender,
  }) async {
    final api = _apiClient;
    if (api == null) throw _noServerFailure;
    try {
      final result = await api.register(
        role: UserRole.patient,
        email: email.trim().toLowerCase(),
        password: password,
        displayName: displayName,
        phone: phone,
        dateOfBirth: dateOfBirth,
        gender: gender,
      );
      return AuthSession(
        role: UserRole.patient,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      throw _noServerFailure;
    }
  }

  /// Login pasien via Google (ID Token sudah diverifikasi google_sign_in).
  /// Akun baru otomatis dibuat + tersimpan di database server.
  Future<AuthSession> loginPatientWithGoogle({
    required String idToken,
  }) async {
    final api = _apiClient;
    if (api == null) throw _noServerFailure;
    try {
      final result = await api.googleLogin(idToken: idToken);
      if (result.role != UserRole.patient && result.role != UserRole.admin) {
        throw const AuthFailure('Akun ini bukan akun pasien.');
      }
      return AuthSession(
        role: result.role,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      throw _noServerFailure;
    }
  }

  /// Login profesional via Google (ID Token sudah diverifikasi google_sign_in).
  /// Mengembalikan sesi + flag needsCompletion untuk profesional baru tanpa STR/SIP.
  Future<({AuthSession session, bool needsCompletion})>
      loginProfessionalWithGoogle({
    required String idToken,
  }) async {
    final api = _apiClient;
    if (api == null) throw _noServerFailure;
    try {
      final result = await api.googleLogin(
        idToken: idToken,
        role: UserRole.professional,
      );
      if (result.role != UserRole.professional) {
        throw const AuthFailure('Akun ini bukan akun profesional.');
      }
      final session = AuthSession(
        role: result.role,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
      return (session: session, needsCompletion: result.needsCompletion);
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      throw _noServerFailure;
    }
  }

  /// Lengkapi onboarding profesional baru (STR/SIP/spesialisasi) setelah login Google.
  /// Mengembalikan sesi yang sudah diperbarui.
  Future<AuthSession> completeProfessionalOnboarding({
    required String accessToken,
    required String strNumber,
    required String sipNumber,
    required String specialization,
    String? displayName,
    String currentRefreshToken = '',
    String existingPassword = '',
  }) async {
    final api = _apiClient;
    if (api == null) throw _noServerFailure;
    try {
      final result = await api.completeProfessionalProfile(
        accessToken: accessToken,
        strNumber: strNumber,
        sipNumber: sipNumber,
        specialization: specialization,
        displayName: displayName,
        existingPassword: existingPassword,
      );
      // Jalur non-merge tidak mengembalikan refresh token; pertahankan token
      // dari sesi login Google agar sesi baru tetap bisa memperpanjang akses.
      final effectiveRefreshToken = result.refreshToken.isNotEmpty
          ? result.refreshToken
          : currentRefreshToken;
      return AuthSession(
        role: UserRole.professional,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: effectiveRefreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      throw _noServerFailure;
    }
  }

  Future<AuthSession> loginProfessionalOnline({
    required String professionalId,
    required String password,
  }) async {
    final api = _apiClient;
    if (api == null) throw _noServerFailure;
    try {
      // Login profesional mandiri: nomor STR/SIP/kode profesi diverifikasi
      // langsung oleh server (bukan email sintetis).
      final result = await api.loginProfessional(
        identifier: professionalId.trim(),
        password: password,
      );
      if (result.role != UserRole.professional) {
        throw const AuthFailure('Akun ini bukan akun profesional.');
      }
      return AuthSession(
        role: UserRole.professional,
        identifier: professionalId.trim(),
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      throw _noServerFailure;
    }
  }

  Future<AuthSession> registerProfessionalOnline({
    required String professionalId,
    required String password,
    required String displayName,
    String? strNumber,
    String? sipNumber,
    String? specialization,
    String? email,
    String? phone,
  }) async {
    final api = _apiClient;
    if (api == null) throw _noServerFailure;
    final normalizedId = professionalId.trim();
    final str = (strNumber ?? normalizedId).trim();
    // Email profesional asli (bila diisi) atau email sintetis dari STR.
    final accountEmail = (email != null && email.trim().isNotEmpty)
        ? email.trim().toLowerCase()
        : '$str@professional.malva.local';
    try {
      final result = await api.register(
        role: UserRole.professional,
        email: accountEmail,
        password: password,
        displayName: displayName,
        professionalId: normalizedId,
        phone: phone,
        strNumber: str,
        sipNumber: (sipNumber ?? '').trim(),
        specialization: (specialization ?? '').trim(),
      );
      return AuthSession(
        role: UserRole.professional,
        identifier: normalizedId,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      throw _noServerFailure;
    }
  }

  // Metode login/daftar lokal lama (kredensial hardcoded) DIHAPUS:
  // semua autentikasi kini melalui server Malva (Azure), termasuk
  // profesional mandiri via nomor STR/SIP.

  /// Menukar refresh token dengan sesi baru (dipakai saat restore sesi
  /// di cold start maupun refresh proaktif). Error jaringan dilempar apa
  /// adanya agar pemanggil bisa memutuskan fallback.
  Future<AuthSession> refreshSessionOnline(String refreshToken) async {
    final api = _apiClient;
    if (api == null) throw _noServerFailure;
    try {
      final result = await api.refreshSession(refreshToken: refreshToken);
      final session = AuthSession(
        role: result.role,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
      await persistSession(session); // simpan token baru
      return session;
    } on MalvaApiException catch (e) {
      if (e.statusCode != null) rethrow;
      throw _noServerFailure;
    }
  }

  /// Logout sesuai server: cabut refresh token di backend, lalu bersihkan
  /// sesi lokal. Dipanggil oleh MalvaApp saat user menekan keluar.
  /// Logout: bersihkan sesi lokal DULU, baru cabut refresh token di server.
  ///
  /// Urutan ini penting. Sebelumnya `clearSession()` (yang menghapus
  /// `malva_active_session` dari secure storage) baru dijalankan SETELAH
  /// `await api.logout(...)`, padahal HTTP client punya timeout 10 detik.
  /// Dampaknya dua:
  ///   1. Bila aplikasi ditutup saat revoke masih berjalan, sesi tetap
  ///      tersimpan sehingga `_restorePersistedSession()` meloginkan
  ///      pengguna kembali padahal ia sudah menekan logout.
  ///   2. Pada perangkat berganti akun, logout akun A yang masih in-flight
  ///      bisa selesai setelah akun B login lalu menghapus sesi B.
  /// Dengan menghapus lokal lebih dulu, keduanya tidak mungkin terjadi;
  /// revoke di server tetap best-effort (offline / token sudah dicabut).
  Future<void> logoutSession(AuthSession? session) async {
    final api = _apiClient;
    final refreshToken = session?.refreshToken;
    try {
      await clearSession();
    } on Object {
      // Gagal hapus secure storage: jangan halangi revoke token di server.
    }
    if (api != null && refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await api.logout(refreshToken: refreshToken);
      } on Object {
        // Offline / token sudah dicabut: sesi lokal sudah bersih.
      }
    }
  }

  // ============================================================
  // SESSION PERSISTENCE
  // ============================================================

  Future<void> persistSession(AuthSession session) async {
    final data = jsonEncode({
      'role': session.role.name,
      'identifier': session.identifier,
      'displayName': session.displayName,
      'backendUserId': session.backendUserId,
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'backendSynced': session.backendSynced,
    });
    await _secureStorage.write(key: _sessionKey, value: data);
  }

  Future<AuthSession?> restoreSession() async {
    try {
      final data = await _secureStorage.read(key: _sessionKey);
      if (data == null || data.isEmpty) return null;
      final map = jsonDecode(data) as Map<String, dynamic>;
      final role = switch (map['role']) {
        'professional' => UserRole.professional,
        'admin' => UserRole.admin,
        _ => UserRole.patient,
      };
      return AuthSession(
        role: role,
        identifier: map['identifier']?.toString() ?? '',
        displayName: map['displayName']?.toString() ?? '',
        backendUserId: map['backendUserId']?.toString(),
        accessToken: map['accessToken']?.toString(),
        refreshToken: map['refreshToken']?.toString(),
        backendSynced: map['backendSynced'] == true,
      );
    } on Object {
      return null;
    }
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: _sessionKey);
  }

  // ============================================================
  // MEDICATION METHODS
  // ============================================================

  /// Catat satu log minum obat dengan status sesuai pilihan pengguna.
  ///
  /// Sebelumnya status selalu ditulis 'taken' dan stok selalu berkurang,
  /// sehingga menandai "Skipped" atau "Missed" tetap tercatat sebagai sudah
  /// diminum dan memotong stok — riwayat kepatuhan minum obat jadi salah.
  void takeMedication(String medicationId, {String status = 'taken'}) {
    final index = state.medications.indexWhere((m) => m.id == medicationId);
    if (index == -1) return;
    final med = state.medications[index];
    final now = DateTime.now();
    // Hanya dosis yang benar-benar masuk (utuh atau sebagian) yang mengurangi
    // stok dan memperbarui penanda "terakhir diminum".
    final consumed = status == 'taken' || status == 'partial';
    final updatedMed = consumed
        ? med.copyWith(
            currentStock: (med.currentStock - 1).clamp(0, 999).toInt(),
            lastTakenAt: now,
          )
        : med;
    final newMeds = [...state.medications]..[index] = updatedMed;
    final newLog = MedicationLog(
      medicationId: medicationId,
      medicationName: med.name,
      takenAt: now,
      status: status,
    );
    if (consumed) {
      // Server baru memotong stok saat menerima log dengan `medication_id`.
      // Sampai konfirmasi sukses datang, pemotongan ini harus "diingat" agar
      // refresh dari server (yang stoknya belum terpotong) tidak mengembalikan
      // angka stok ke nilai lama — bug "stok 2 kembali jadi 3".
      _pendingDoses[medicationId] = (_pendingDoses[medicationId] ?? 0) + 1;
    }
    state = state.copyWith(
      medications: newMeds,
      medicationLogs: [newLog, ...state.medicationLogs],
    );
    // Tulis cache lokal agar log baru tidak hilang bila app ditutup paksa
    // sebelum sempat sync ke server.
    unawaited(_persistMedicationLogs());
  }

  void upsertMedication(Medication medication) {
    final idx = state.medications.indexWhere((m) => m.id == medication.id);
    final newMeds = [...state.medications];
    if (idx >= 0) {
      newMeds[idx] = medication;
    } else {
      newMeds.add(medication);
    }
    state = state.copyWith(medications: newMeds);
  }

  /// Ikat ulang obat lokal ke id dari server setelah pembuatan berhasil.
  ///
  /// Obat yang ditambahkan sebelum sync memakai id sementara
  /// `med_<timestamp>`. Tanpa pengikatan ulang, edit berikutnya tidak bisa
  /// memakai PUT (server tidak mengenal id sementara itu) sehingga server
  /// kembali membuat baris baru — persis duplikat yang ingin dihindari.
  void rebindMedication(String localId, Medication updated) {
    final idx = state.medications.indexWhere((m) => m.id == localId);
    if (idx < 0) return;
    final next = [...state.medications];
    next[idx] = updated;
    state = state.copyWith(medications: next);
  }

  /// Simpan izin monitoring Continuous Support (7 hari) secara lokal.
  /// Dipakai sebagai sumber kebenaran offline + audit consent pasien.
  Future<void> setContinuousSupportConsent({
    required bool diary,
    required bool goals,
    required bool healthRecord,
    required bool moodCheckin,
    required bool medicationCheckin,
  }) async {
    final data = jsonEncode({
      'diary': diary,
      'goals': goals,
      'health_record': healthRecord,
      'mood_checkin': moodCheckin,
      'medication_checkin': medicationCheckin,
      'granted_at': DateTime.now().toIso8601String(),
    });
    await _secureStorage.write(key: _continuousConsentKey, value: data);
  }

  /// Baca izin Continuous Support yang tersimpan lokal (null bila belum ada).
  Future<Map<String, dynamic>?> readContinuousSupportConsent() async {
    try {
      final raw = await _secureStorage.read(key: _continuousConsentKey);
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      return null;
    }
  }

  void deleteMedication(String id) {
    state = state.copyWith(
      medications: state.medications.where((m) => m.id != id).toList(),
    );
    _pendingDoses.remove(id);
  }

  /// Ganti seluruh daftar obat (mis. hasil muat ulang dari server).
  ///
  /// Stok dari server bisa BELUM terpotong (backend hanya memotong saat log
  /// dikirim dengan `medication_id`). Karena itu dosis yang masih pending
  /// dikurangkan lagi di sini, agar angka stok di layar tidak naik kembali
  /// setelah pull-to-refresh.
  void replaceMedications(List<Medication> meds) {
    final adjusted = <Medication>[];
    for (final med in meds) {
      final pending = _pendingDoses[med.id] ?? 0;
      adjusted.add(
        pending <= 0
            ? med
            : med.copyWith(
                currentStock:
                    (med.currentStock - pending).clamp(0, 999).toInt(),
              ),
      );
    }
    state = state.copyWith(medications: adjusted);
  }

  // ============================================================
  // LOG MINUM OBAT — merge server + cache lokal per akun
  // ============================================================

  /// Jendela toleransi pencocokan satu dosis.
  ///
  /// Timestamp eksak tidak bisa dipakai: server bisa menyimpan/mengembalikan
  /// `taken_at` yang sedikit berbeda dari waktu optimistis di perangkat (jam
  /// server di belakang, normalisasi zona waktu, atau pembulatan detik).
  /// Dua dosis obat yang SAMA tidak mungkin diminum dalam rentang 2 menit,
  /// jadi jendela ini aman untuk menggabungkan pasangan "optimistis + server"
  /// tanpa menelan dosis yang benar-benar berbeda.
  static const _doseMatchWindow = Duration(minutes: 2);

  /// True bila id belum berupa id server: kosong atau id sementara
  /// `med_<timestamp>` (obat yang dicatat sebelum sync berhasil).
  static bool _isTemporaryId(String id) {
    final value = id.trim();
    return value.isEmpty || value.startsWith('med_');
  }

  /// True bila dua log adalah DOSIS YANG SAMA: obat sama, status sama, dan
  /// waktunya berdekatan (<= [_doseMatchWindow]).
  ///
  /// Nama obat hanya dipakai sebagai jembatan saat salah satu id masih
  /// sementara/kosong. Dua id server yang sah tetapi berbeda adalah dua resep
  /// berbeda (mis. "Lamictal" 20mg dan 50mg) — tidak boleh dianggap satu dosis
  /// walau namanya sama, karena akan menghilangkan satu dosis dari riwayat dan
  /// menurunkan adherence secara palsu.
  static bool _isSameDose(MedicationLog a, MedicationLog b) {
    if (a.status != b.status) return false;
    final idA = a.medicationId.trim();
    final idB = b.medicationId.trim();
    final sameId = idA.isNotEmpty && idA == idB;
    final sameName = a.medicationName.trim().toLowerCase() ==
        b.medicationName.trim().toLowerCase();
    final bridgedByName =
        sameName && (_isTemporaryId(idA) || _isTemporaryId(idB));
    if (!sameId && !bridgedByName) return false;
    return a.takenAt.difference(b.takenAt).abs() <= _doseMatchWindow;
  }

  /// GABUNGKAN log dari server ke log lokal (bukan menimpa buta).
  ///
  /// Aturan merge (tanpa heuristik "lebih baru dari log server terbaru"):
  /// 1. Semua log server masuk.
  /// 2. Log lokal yang TIDAK punya padanan dosis di server DIPERTAHANKAN —
  ///    termasuk yang waktunya lebih lama. Ini mencegah log offline (gagal
  ///    kirim) hilang diam-diam saat data server dimuat.
  /// 3. Padanan dosis dicocokkan dengan jendela toleransi waktu
  ///    ([_doseMatchWindow]) via [_isSameDose], bukan timestamp eksak, agar
  ///    pasangan "optimistis lokal + versi server" tidak jadi dua baris. Nama
  ///    obat hanya menjadi jembatan bila salah satu id masih sementara/kosong;
  ///    dua id server yang sah dan berbeda tetap dianggap dua dosis berbeda.
  /// 4. Hasil diurutkan `takenAt` DESC (terbaru dulu).
  void replaceMedicationLogs(List<MedicationLog> logs) {
    final merged = <MedicationLog>[...logs];
    for (final local in state.medicationLogs) {
      // Pertahankan log lokal HANYA bila tidak ada padanannya di server.
      if (merged.any((server) => _isSameDose(server, local))) continue;
      merged.add(local);
    }
    merged.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    state = state.copyWith(medicationLogs: merged);
    // Persist gabungan agar konsisten dengan cache saat app dibuka lagi.
    unawaited(_persistMedicationLogs());
  }

  /// Simpan daftar log minum obat ke secure storage (per akun).
  ///
  /// Fire-and-forget; kegagalan storage tidak menghalangi UI. Key mengandung
  /// id akun sehingga data pasien lain tidak pernah tercampur.
  Future<void> _persistMedicationLogs() async {
    final accountId = state.patient.id;
    if (accountId.isEmpty) return;
    try {
      final data = jsonEncode(state.medicationLogs
          .map((log) => {
                'medication_id': log.medicationId,
                'medication_name': log.medicationName,
                'taken_at': log.takenAt.toIso8601String(),
                'status': log.status,
              })
          .toList());
      await _secureStorage.write(
        key: '$_medicationLogsKeyPrefix$accountId',
        value: data,
      );
    } on Object {
      // Storage tidak tersedia (test/offline): abaikan.
    }
  }

  /// Hidrasi log minum obat dari cache lokal akun aktif.
  ///
  /// Dipanggil di awal [applySession] (via [_loadServerDataAsync]) SEBELUM
  /// data server dimuat, supaya riwayat kepatuhan langsung tampil dan merge
  /// server berikutnya tidak salah menganggap log lama server lebih baru.
  Future<void> _hydrateMedicationLogsCache() async {
    final accountId = state.patient.id;
    if (accountId.isEmpty) return;
    try {
      final raw = await _secureStorage.read(
        key: '$_medicationLogsKeyPrefix$accountId',
      );
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final cached = <MedicationLog>[];
      for (final entry in decoded.whereType<Map>()) {
        final map = Map<String, dynamic>.from(entry);
        final takenAt = DateTime.tryParse(map['taken_at']?.toString() ?? '');
        if (takenAt == null) continue;
        cached.add(MedicationLog(
          medicationId: map['medication_id']?.toString() ?? '',
          medicationName: map['medication_name']?.toString() ?? '',
          takenAt: takenAt,
          status: map['status']?.toString() ?? '',
        ));
      }
      if (cached.isEmpty) return;
      // state.medicationLogs kosong saat hidrasi (baru applySession) → hasil
      // akhir = cache. Bila sudah terisi (mis. server lebih dulu), merge tetap
      // aman karena replaceMedicationLogs menggabungkan, bukan menimpa.
      replaceMedicationLogs(cached);
    } on Object {
      // Cache rusak/tidak tersedia: abaikan, tetap lanjut muat dari server.
    }
  }

  // ============================================================
  // DOSIS PENDING (anti "stok naik sendiri" setelah refresh)
  // ============================================================

  /// Jumlah dosis yang sudah dipotong lokal tetapi belum dikonfirmasi server.
  final Map<String, int> _pendingDoses = <String, int>{};

  /// Berapa dosis yang masih pending untuk satu obat.
  int pendingDosesFor(String medicationId) => _pendingDoses[medicationId] ?? 0;

  /// Tandai satu dosis pending sudah diterima server.
  void confirmDose(String medicationId) {
    final pending = _pendingDoses[medicationId] ?? 0;
    if (pending <= 1) {
      _pendingDoses.remove(medicationId);
    } else {
      _pendingDoses[medicationId] = pending - 1;
    }
  }

  /// Buang semua catatan dosis pending (logout / ganti akun).
  void clearPendingDoses() {
    _pendingDoses.clear();
  }

  // ============================================================
  // MOOD METHODS
  // ============================================================

  void addMood(MoodEntry entry) {
    state = state.copyWith(moodEntries: [entry, ...state.moodEntries]);
  }

  void replaceMoodEntries(List<MoodEntry> entries) {
    state = state.copyWith(moodEntries: entries);
  }

  // ============================================================
  // DIARY METHODS
  // ============================================================

  void addDiary(DiaryEntry entry) {
    state = state.copyWith(diaryEntries: [entry, ...state.diaryEntries]);
  }

  void upsertDiary(DiaryEntry entry) {
    final idx = state.diaryEntries.indexWhere((d) => d.id == entry.id);
    final newDiaries = [...state.diaryEntries];
    if (idx >= 0) {
      newDiaries[idx] = entry;
    } else {
      newDiaries.insert(0, entry);
    }
    state = state.copyWith(diaryEntries: newDiaries);
  }

  void deleteDiary(String id) {
    state = state.copyWith(
      diaryEntries: state.diaryEntries.where((d) => d.id != id).toList(),
    );
  }

  void replaceDiaryEntries(List<DiaryEntry> entries) {
    state = state.copyWith(diaryEntries: entries);
  }

  // ============================================================
  // GOAL METHODS
  // ============================================================

  void toggleGoal(String id) {
    final idx = state.goals.indexWhere((g) => g.id == id);
    if (idx < 0) return;
    final goal = state.goals[idx];
    final newGoals = [...state.goals];
    newGoals[idx] = goal.copyWith(
      completedToday: !goal.completedToday,
      streakDays:
          goal.completedToday ? goal.streakDays - 1 : goal.streakDays + 1,
    );
    state = state.copyWith(goals: newGoals);
  }

  void addGoal(GoalItem goal) {
    state = state.copyWith(goals: [...state.goals, goal]);
  }

  void upsertGoal(GoalItem goal) {
    final idx = state.goals.indexWhere((g) => g.id == goal.id);
    final newGoals = [...state.goals];
    if (idx >= 0) {
      newGoals[idx] = goal;
    } else {
      newGoals.add(goal);
    }
    state = state.copyWith(goals: newGoals);
  }

  void deleteGoal(String id) {
    state = state.copyWith(
      goals: state.goals.where((g) => g.id != id).toList(),
    );
  }

  // ============================================================
  // RECORD METHODS
  // ============================================================

  void addRecord(HealthRecord record) {
    state = state.copyWith(records: [...state.records, record]);
  }

  void deleteRecord(String id) {
    state = state.copyWith(
      records: state.records.where((r) => r.id != id).toList(),
    );
  }

  // ============================================================
  // SCREENING METHODS
  // ============================================================

  void skipInitialScreening() {
    state =
        state.copyWith(initialScreeningStatus: InitialScreeningStatus.skipped);
  }

  void saveScreeningBundle(ScreeningBundle bundle) {
    state = state.copyWith(
      screeningBundles: [...state.screeningBundles, bundle],
      assessments: [...state.assessments, bundle.phq9, bundle.gad7],
      initialScreeningStatus: bundle.isInitial
          ? InitialScreeningStatus.completed
          : state.initialScreeningStatus,
    );
  }

  void addScreeningBundle(ScreeningBundle bundle) {
    state = state.copyWith(
      screeningBundles: [...state.screeningBundles, bundle],
    );
  }

  void replaceScreeningBundles(List<ScreeningBundle> bundles) {
    state = state.copyWith(screeningBundles: bundles);
  }

  void saveAssessment(AssessmentResult result) {
    state = state.copyWith(
      assessments: [...state.assessments, result],
    );
    _persistAssessments();
  }

  /// Simpan assessment ke state + tunggu persistensi lokal per akun.
  Future<void> saveAssessmentResult(AssessmentResult result) async {
    saveAssessment(result);
    await _assessmentDb.saveAll(state.patient.id, state.assessments);
  }

  /// Muat riwayat asesmen dari penyimpanan lokal akun aktif, gabungkan
  /// dengan state (tanpa duplikat), lalu simpan kembali daftar gabungan.
  /// Panggil setelah [applySession] agar riwayat offline tampil lagi.
  Future<void> loadAndSaveAssessmentsAsync() async {
    final local = await _assessmentDb.loadAll(state.patient.id);
    if (local.isEmpty && state.assessments.isEmpty) return;
    final seen = state.assessments.map(_assessmentKey).toSet();
    final missing =
        local.where((r) => !seen.contains(_assessmentKey(r))).toList();
    if (missing.isEmpty && local.isNotEmpty) return;
    final merged = [...state.assessments, ...missing];
    state = state.copyWith(assessments: merged);
    await _assessmentDb.saveAll(state.patient.id, merged);
  }

  /// Persistensi lokal fire-and-forget (tidak menghalangi UI).
  void _persistAssessments() {
    _assessmentDb.saveAll(state.patient.id, state.assessments);
  }

  static String _assessmentKey(AssessmentResult r) =>
      '${r.type.name}|${r.createdAt.toIso8601String()}';

  /// Menyimpan hasil screening dan MENGIRIMKANNYA ke server.
  ///
  /// Mengembalikan [ScreeningSubmitResult] yang membedakan "tersimpan di
  /// perangkat" dari "benar-benar diterima server". Sebelumnya kegagalan
  /// upload ditelan diam-diam (`on Object { }`) lalu UI tetap menampilkan
  /// "Screening berhasil dikirim" dengan ID lokal — termasuk untuk screening
  /// awal yang menentukan crisis_flag, sehingga profesional tidak pernah tahu
  /// ada pasien berisiko.
  Future<ScreeningSubmitResult> submitScreeningBundle({
    required List<int> phq9Answers,
    required List<int> gad7Answers,
    required bool isInitial,
    required String source,
    AuthSession? session,
    String? patientId,
  }) async {
    final phq9 = AssessmentEngine.score(
      type: AssessmentType.phq9,
      answers: phq9Answers,
    );
    final gad7 = AssessmentEngine.score(
      type: AssessmentType.gad7,
      answers: gad7Answers,
    );
    var bundle = ScreeningBundle(
      id: 'screening_${DateTime.now().millisecondsSinceEpoch}',
      phq9: phq9,
      gad7: gad7,
      createdAt: DateTime.now(),
      isInitial: isInitial,
      source: source,
    );

    final accessToken = session?.accessToken;
    var uploaded = false;
    String? uploadError;
    if (_apiClient != null && accessToken != null && accessToken.isNotEmpty) {
      try {
        final remote = await _apiClient.submitScreening(
          accessToken: accessToken,
          bundle: bundle,
          phq9Answers: phq9Answers,
          gad7Answers: gad7Answers,
          patientId: patientId,
        );
        if (remote.id.isNotEmpty) {
          bundle = ScreeningBundle(
            id: remote.id,
            phq9: phq9,
            gad7: gad7,
            createdAt: bundle.createdAt,
            isInitial: isInitial,
            source: source,
          );
          uploaded = true;
        } else {
          uploadError = 'Server tidak mengembalikan ID screening.';
        }
      } on MalvaApiException catch (error) {
        uploadError = error.message;
      } on Object {
        uploadError = 'Tidak dapat menghubungi server.';
      }
    } else {
      uploadError = 'Kamu belum masuk atau server belum terhubung.';
    }

    saveScreeningBundle(bundle);
    return ScreeningSubmitResult(
      bundle: bundle,
      uploaded: uploaded,
      error: uploadError,
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Parse string mood dari server menjadi MoodValue enum.
  static MoodValue _parseMoodValue(String raw) {
    final v = raw.trim().toLowerCase();
    return switch (v) {
      'great' => MoodValue.great,
      'good' => MoodValue.good,
      'sad' => MoodValue.sad,
      'awful' => MoodValue.awful,
      _ => MoodValue.okay,
    };
  }

  // ============================================================
  // STATIC CONSTANTS
  // ============================================================

  static const professionalIdDigitCount = 16;
}

// ============================================================
// PROVIDERS
// ============================================================

final malvaStoreProvider =
    StateNotifierProvider<MalvaStoreNotifier, MalvaStoreState>((ref) {
  return MalvaStoreNotifier(
    ref.watch(apiClientProvider),
    ref.watch(assessmentDatabaseProvider),
  );
});

final adherencePercentProvider = Provider<int>((ref) {
  return ref.watch(malvaStoreProvider).adherencePercent;
});

final completedGoalPercentProvider = Provider<int>((ref) {
  return ref.watch(malvaStoreProvider).completedGoalPercent;
});

final activeAlertsProvider = Provider<List<String>>((ref) {
  return ref.watch(malvaStoreProvider).activeAlerts;
});

final needsInitialScreeningProvider = Provider<bool>((ref) {
  return ref.watch(malvaStoreProvider).needsInitialScreeningDecision;
});

final latestScreeningBundleProvider = Provider<ScreeningBundle?>((ref) {
  return ref.watch(malvaStoreProvider).latestScreeningBundle;
});

final screeningCrisisFlagProvider = Provider<bool>((ref) {
  return ref.watch(latestScreeningBundleProvider)?.crisisFlag ?? false;
});

final patientProfileProvider = Provider<PatientProfile>((ref) {
  return ref.watch(malvaStoreProvider).patient;
});
