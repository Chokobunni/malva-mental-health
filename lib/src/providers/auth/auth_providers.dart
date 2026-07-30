import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models.dart';
import '../services/malva_api_client.dart';
import 'core_providers.dart';

const _sessionKey = 'malva_active_session';

class AuthState {
  final AuthSession? session;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.session,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    AuthSession? session,
    bool? isLoading,
    String? error,
    bool clearSession = false,
    bool clearError = false,
  }) {
    return AuthState(
      session: clearSession ? null : (session ?? this.session),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get isAuthenticated => session != null;
  bool get isPatient => session?.role == UserRole.patient;
  bool get isProfessional => session?.role == UserRole.professional;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final MalvaApiClient _apiClient;
  final FlutterSecureStorage _storage;

  AuthNotifier(this._apiClient, this._storage) : super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      state = state.copyWith(isLoading: true);
      final data = await _storage.read(key: _sessionKey);
      if (data == null || data.isEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }
      final map = jsonDecode(data) as Map<String, dynamic>;
      final role = map['role'] == UserRole.professional.name
          ? UserRole.professional
          : UserRole.patient;
      final session = AuthSession(
        role: role,
        identifier: map['identifier']?.toString() ?? '',
        displayName: map['displayName']?.toString() ?? '',
        backendUserId: map['backendUserId']?.toString(),
        accessToken: map['accessToken']?.toString(),
        refreshToken: map['refreshToken']?.toString(),
        backendSynced: map['backendSynced'] == true,
      );
      state = AuthState(session: session);
    } on Object {
      state = const AuthState();
    }
  }

  Future<void> loginPatient({
    required String email,
    required String password,
  }) async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      final result = await _apiClient.login(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (result.role != UserRole.patient) {
        throw const AuthFailure('Akun ini bukan akun pasien.');
      }
      final session = AuthSession(
        role: UserRole.patient,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
      await _persistSession(session);
      state = AuthState(session: session);
    } on AuthFailure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } on MalvaApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> registerPatient({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      final result = await _apiClient.register(
        role: UserRole.patient,
        email: email.trim().toLowerCase(),
        password: password,
        displayName: displayName.trim(),
      );
      final session = AuthSession(
        role: UserRole.patient,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
      await _persistSession(session);
      state = AuthState(session: session);
    } on MalvaApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> loginProfessional({
    required String professionalId,
    required String password,
  }) async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      final result = await _apiClient.login(
        email: '$professionalId@professional.malva.local',
        password: password,
      );
      if (result.role != UserRole.professional) {
        throw const AuthFailure('Akun ini bukan akun profesional.');
      }
      final session = AuthSession(
        role: UserRole.professional,
        identifier: professionalId,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
      await _persistSession(session);
      state = AuthState(session: session);
    } on AuthFailure catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } on MalvaApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> registerProfessional({
    required String professionalId,
    required String password,
    required String displayName,
  }) async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      final result = await _apiClient.register(
        role: UserRole.professional,
        email: '$professionalId@professional.malva.local',
        password: password,
        displayName: displayName.trim(),
        professionalId: professionalId.trim(),
      );
      final session = AuthSession(
        role: UserRole.professional,
        identifier: professionalId,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );
      await _persistSession(session);
      state = AuthState(session: session);
    } on MalvaApiException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      rethrow;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  void updateTokens(String accessToken, String refreshToken) {
    final current = state.session;
    if (current == null) return;
    final updated = AuthSession(
      role: current.role,
      identifier: current.identifier,
      displayName: current.displayName,
      backendUserId: current.backendUserId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      backendSynced: current.backendSynced,
    );
    state = state.copyWith(session: updated);
    _persistSession(updated);
  }

  Future<void> logout() async {
    await _storage.delete(key: _sessionKey);
    state = const AuthState();
  }

  Future<void> _persistSession(AuthSession session) async {
    final data = jsonEncode({
      'role': session.role.name,
      'identifier': session.identifier,
      'displayName': session.displayName,
      'backendUserId': session.backendUserId,
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'backendSynced': session.backendSynced,
    });
    await _storage.write(key: _sessionKey, value: data);
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(apiClientProvider),
    ref.watch(secureStorageProvider),
  );
});

final currentSessionProvider = Provider<AuthSession?>((ref) {
  return ref.watch(authStateProvider).session;
});

final isPatientProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isPatient;
});

final isProfessionalProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isProfessional;
});
