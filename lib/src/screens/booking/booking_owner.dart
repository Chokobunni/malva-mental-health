import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';

class BookingOwner {
  BookingOwner(this._ref, AuthSession? explicit)
      : _original = explicit ?? _ref.read(currentSessionProvider) {
    final current = _ref.read(currentSessionProvider);
    if (current != null && !_matches(current)) _changed = true;
    _ref.listenManual<AuthState>(authStateProvider, (_, state) {
      if (!_matches(state.session)) _changed = true;
    });
  }

  final WidgetRef _ref;
  final AuthSession? _original;
  bool _changed = false;

  AuthSession? get session {
    if (_changed) return null;
    final current = _ref.read(currentSessionProvider);
    return current == null
        ? _original
        : _matches(current)
            ? current
            : null;
  }

  bool _matches(AuthSession? session) =>
      session?.role == _original?.role && _id(session) == _id(_original);

  static String? _id(AuthSession? session) =>
      session?.backendUserId?.isNotEmpty == true
          ? session?.backendUserId
          : session?.identifier;
}
