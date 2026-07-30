import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return GlobalKey<NavigatorState>();
});

final scaffoldMessengerKeyProvider = Provider<GlobalKey<ScaffoldMessengerState>>((ref) {
  return GlobalKey<ScaffoldMessengerState>();
});

// App navigation state
enum AppRoute { splash, login, patientHome, professionalHome }

class AppState {
  final bool showSplash;
  final AppRoute route;

  const AppState({
    this.showSplash = true,
    this.route = AppRoute.splash,
  });

  AppState copyWith({
    bool? showSplash,
    AppRoute? route,
  }) {
    return AppState(
      showSplash: showSplash ?? this.showSplash,
      route: route ?? this.route,
    );
  }
}

class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(const AppState());

  void hideSplash() {
    state = state.copyWith(showSplash: false);
  }

  void goToLogin() {
    state = state.copyWith(route: AppRoute.login);
  }

  void goToPatientHome() {
    state = state.copyWith(route: AppRoute.patientHome);
  }

  void goToProfessionalHome() {
    state = state.copyWith(route: AppRoute.professionalHome);
  }

  void handleAuth(String role) {
    if (role == 'professional') {
      goToProfessionalHome();
    } else {
      goToPatientHome();
    }
  }

  void handleLogout() {
    goToLogin();
  }
}

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});
