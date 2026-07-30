import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../services/malva_api_client.dart';

final apiClientProvider = Provider<MalvaApiClient>((ref) {
  return MalvaApiClient();
});

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
  AuthNotifier() : super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      state = state.copyWith(isLoading: true);
      // Session restoration happens via MalvaStore
      state = state.copyWith(isLoading: false);
    } on Object {
      state = const AuthState();
    }
  }

  void setSession(AuthSession session) {
    state = AuthState(session: session);
  }

  void clearSession() {
    state = const AuthState();
  }

  void updateError(String error) {
    state = state.copyWith(error: error);
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>(
    (ref) => AuthNotifier());

final currentSessionProvider = Provider<AuthSession?>((ref) {
  return ref.watch(authStateProvider).session;
});

final isPatientProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isPatient;
});

final isProfessionalProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isProfessional;
});
