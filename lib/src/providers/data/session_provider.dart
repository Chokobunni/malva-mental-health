import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../models.dart';
import '../auth_providers.dart';

// ============================================================
// SESSION AUTO-REFRESH
// ============================================================

const _refreshKey = 'malva_refresh_token';
const _sessionExpiryKey = 'malva_session_expiry';
const _secureStorage = FlutterSecureStorage();

class SessionRefreshNotifier extends StateNotifier<AuthState> {
  SessionRefreshNotifier(this._ref) : super(const AuthState()) {
    _restoreSession();
  }

  final Ref _ref;
  Timer? _refreshTimer;

  // ----------------------------------------------------------
  // SESSION LIFECYCLE
  // ----------------------------------------------------------

  Future<void> _restoreSession() async {
    try {
      state = state.copyWith(isLoading: true);

      final refreshToken = await _secureStorage.read(key: _refreshKey);
      if (refreshToken == null || refreshToken.isEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final apiClient = _ref.read(apiClientProvider);
      final result = await apiClient.refreshSession(refreshToken: refreshToken);

      final session = AuthSession(
        role: result.role,
        identifier: result.email,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );

      await _persistTokens(session);
      state = AuthState(session: session);
      _scheduleRefresh();
    } on Object {
      await _clearTokens();
      state = const AuthState();
    }
  }

  void setSession(AuthSession session) {
    state = AuthState(session: session);
    _persistTokens(session);
    _scheduleRefresh();
  }

  void clearSession() {
    _refreshTimer?.cancel();
    _clearTokens();
    state = const AuthState();
  }

  // ----------------------------------------------------------
  // TOKEN REFRESH
  // ----------------------------------------------------------

  void _scheduleRefresh() {
    _refreshTimer?.cancel();

    // Refresh 5 minutes before expiry (assuming 1h tokens)
    const refreshBefore = Duration(minutes: 55);
    _refreshTimer = Timer(refreshBefore, _refreshTokens);
  }

  Future<void> _refreshTokens() async {
    final session = state.session;
    final refreshToken = session?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return;

    try {
      final apiClient = _ref.read(apiClientProvider);
      final result = await apiClient.refreshSession(refreshToken: refreshToken);

      final newSession = AuthSession(
        role: session!.role,
        identifier: session.identifier,
        displayName: result.displayName,
        backendUserId: result.userId,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        backendSynced: true,
      );

      await _persistTokens(newSession);
      state = AuthState(session: newSession);
      _scheduleRefresh();
    } on Object {
      // Token refresh failed — force logout
      clearSession();
    }
  }

  // ----------------------------------------------------------
  // PERSISTENCE
  // ----------------------------------------------------------

  Future<void> _persistTokens(AuthSession session) async {
    if (session.refreshToken != null) {
      await _secureStorage.write(key: _refreshKey, value: session.refreshToken);
    }
  }

  Future<void> _clearTokens() async {
    await _secureStorage.delete(key: _refreshKey);
    await _secureStorage.delete(key: _sessionExpiryKey);
  }
}

// ============================================================
// PROVIDERS
// ============================================================

final sessionRefreshProvider =
    StateNotifierProvider<SessionRefreshNotifier, AuthState>((ref) {
  return SessionRefreshNotifier(ref);
});

final sessionIsExpiredProvider = Provider<bool>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (session?.accessToken == null) return true;
  // The notifier handles actual expiry via timer
  return false;
});
