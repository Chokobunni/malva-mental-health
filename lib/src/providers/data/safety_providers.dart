import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../widgets/friendly_error.dart';
import '../auth_providers.dart';

// ============================================================
// SAFETY PROTOCOL STATE
// ============================================================

class SafetyState {
  const SafetyState({
    this.contacts = const [],
    this.incidents = const [],
    this.isLoading = false,
    this.error,
    this.activeIncident,
    this.blastStatus,
  });

  final List<BackendEmergencyContact> contacts;
  final List<BackendCrisisIncident> incidents;
  final bool isLoading;
  final String? error;
  final BackendCrisisIncident? activeIncident;
  final BackendSOSBlastStatus? blastStatus;

  SafetyState copyWith({
    List<BackendEmergencyContact>? contacts,
    List<BackendCrisisIncident>? incidents,
    bool? isLoading,
    String? error,
    BackendCrisisIncident? activeIncident,
    BackendSOSBlastStatus? blastStatus,
    bool clearActive = false,
  }) {
    return SafetyState(
      contacts: contacts ?? this.contacts,
      incidents: incidents ?? this.incidents,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      activeIncident:
          clearActive ? null : (activeIncident ?? this.activeIncident),
      blastStatus: clearActive ? null : (blastStatus ?? this.blastStatus),
    );
  }
}

// ============================================================
// SAFETY NOTIFIER
// ============================================================

class SafetyNotifier extends StateNotifier<SafetyState> {
  SafetyNotifier(this._ref) : super(const SafetyState());

  final Ref _ref;

  MalvaApiClient get _api => _ref.read(apiClientProvider);
  String? get _token => _ref.read(currentSessionProvider)?.accessToken;

  bool get _hasBackend {
    final token = _token;
    return token != null && token.isNotEmpty;
  }

  /// Muat kontak darurat + incident aktif. Aman dipanggil offline.
  Future<void> load() async {
    if (!_hasBackend) {
      state = state.copyWith(error: null, isLoading: false);
      return;
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final contacts = await _api.listEmergencyContacts(accessToken: _token!);
      final incidents = await _api.listCrisisIncidents(accessToken: _token!);
      if (!mounted) return;
      state = state.copyWith(
        contacts: contacts,
        incidents: incidents,
        isLoading: false,
      );
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.message);
    } on Object catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: friendlyErrorMessage(e));
    }
  }

  Future<BackendEmergencyContact> addContact({
    required String name,
    required String phone,
    String relationship = '',
    bool isDefault = false,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const AuthFailure('Harus login untuk mengelola kontak darurat.');
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final created = await _api.createEmergencyContact(
        accessToken: token,
        contactName: name,
        contactPhone: phone,
        relationship: relationship,
        isDefault: isDefault,
      );
      if (!mounted) return created;
      state = state.copyWith(
        contacts: [...state.contacts, created],
        isLoading: false,
      );
      return created;
    } on MalvaApiException catch (e) {
      if (mounted) state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } on Object catch (e) {
      if (mounted) {
        state =
            state.copyWith(isLoading: false, error: friendlyErrorMessage(e));
      }
      rethrow;
    }
  }

  Future<void> removeContact(String contactId) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const AuthFailure('Harus login untuk mengelola kontak darurat.');
    }
    try {
      await _api.deleteEmergencyContact(
          accessToken: token, contactId: contactId);
      if (!mounted) return;
      state = state.copyWith(
        contacts: state.contacts.where((c) => c.id != contactId).toList(),
      );
    } on MalvaApiException {
      rethrow;
    } on Object catch (e) {
      throw Exception(friendlyErrorMessage(e));
    }
  }

  /// Kirim silent SOS. Wajib ada minimal 1 kontak; GPS opsional.
  /// Mengembalikan incident yang dibuat.
  Future<BackendCrisisIncident> sendSilentSOS({
    String triggeredBy = 'silent_sos',
    int? phq9Q9Score,
    double? latitude,
    double? longitude,
    String message = '',
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const AuthFailure('Harus login untuk mengirim SOS.');
    }
    if (state.contacts.isEmpty) {
      // Coba refresh sekali — mungkin kontak baru saja ditambah.
      await load();
      if (state.contacts.isEmpty) {
        throw const AuthFailure(
          'Tambahkan minimal 1 kontak darurat sebelum mengirim SOS.',
        );
      }
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final incident = await _api.createCrisisAlertV2(
        accessToken: token,
        triggeredBy: triggeredBy,
        phq9Q9Score: phq9Q9Score,
        latitude: latitude,
        longitude: longitude,
        message: message,
      );
      BackendSOSBlastStatus? blast;
      try {
        blast = await _api.getBlastStatus(
          accessToken: token,
          incidentId: incident.id,
        );
      } on Object catch (_) {
        // Status blast boleh gagal — incident tetap valid.
      }
      if (!mounted) return incident;
      state = state.copyWith(
        isLoading: false,
        activeIncident: incident,
        blastStatus: blast,
        incidents: [incident, ...state.incidents],
      );
      return incident;
    } on MalvaApiException catch (e) {
      if (mounted) state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } on Object catch (e) {
      if (mounted) {
        state =
            state.copyWith(isLoading: false, error: friendlyErrorMessage(e));
      }
      rethrow;
    }
  }

  Future<BackendSOSBlastStatus?> refreshBlastStatus(String incidentId) async {
    final token = _token;
    if (token == null || token.isEmpty) return null;
    try {
      final blast =
          await _api.getBlastStatus(accessToken: token, incidentId: incidentId);
      if (!mounted) return blast;
      state = state.copyWith(blastStatus: blast);
      return blast;
    } on Object catch (_) {
      return null;
    }
  }

  void clearActiveIncident() {
    state = state.copyWith(clearActive: true);
  }
}

// ============================================================
// PROVIDER
// ============================================================

final safetyProvider =
    StateNotifierProvider<SafetyNotifier, SafetyState>((ref) {
  return SafetyNotifier(ref);
});

final hasEmergencyContactsProvider = Provider<bool>((ref) {
  return ref.watch(safetyProvider).contacts.isNotEmpty;
});

final activeCrisisIncidentProvider = Provider<BackendCrisisIncident?>((ref) {
  return ref.watch(safetyProvider).activeIncident;
});
