import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../auth_providers.dart';

// ============================================================
// SESSION AUTO-REFRESH (delegasi ke MalvaApp._restorePersistedSession)
//
// Catatan penting: refresh token HANYA boleh ditukar di SATU tempat
// (malva_app) karena server memakai rotasi token sekali-pakai — dua
// pemanggil refresh paralel akan mencabut token satu sama lain dan
// menyebabkan 401 acak (mis. kontak darurat tidak termuat).
//
// Notifier ini kini hanya menjadi penanda status, bukan pemilik token.
// ============================================================

class SessionRefreshNotifier extends StateNotifier<AuthState> {
  SessionRefreshNotifier(this._ref) : super(const AuthState());

  // ignore: unused_field
  final Ref _ref;

  void setSession(AuthSession session) {
    state = AuthState(session: session);
  }

  void clearSession() {
    state = const AuthState();
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
  if (session?.accessToken == null || session!.accessToken!.isEmpty) {
    return false;
  }
  // The notifier handles actual expiry via timer
  return false;
});
