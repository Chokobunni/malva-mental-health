import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../assessment_engine.dart';
import '../malva_store_provider.dart';

// ============================================================
// CRISIS HOTLINE CONSTANTS
// ============================================================

const crisisHotlineNumber = '119';
const crisisHotlineExtension = '8';
const crisisHotlineName = 'Kementerian Kesehatan RI';
const crisisHotlineDescription = 'Layanan Darurat Kesehatan Jiwa 24 jam';

// ============================================================
// CRISIS STATE
// ============================================================

class CrisisState {
  const CrisisState({this.isActive = false, this.lastTriggered});

  final bool isActive;
  final DateTime? lastTriggered;

  CrisisState copyWith({bool? isActive, DateTime? lastTriggered}) {
    return CrisisState(
      isActive: isActive ?? this.isActive,
      lastTriggered: lastTriggered ?? this.lastTriggered,
    );
  }
}

// ============================================================
// CRISIS NOTIFIER
// ============================================================

class CrisisNotifier extends StateNotifier<CrisisState> {
  CrisisNotifier(this._ref) : super(const CrisisState()) {
    _checkCrisisFlag();
  }

  final Ref _ref;

  void _checkCrisisFlag() {
    final screening = _ref.read(latestScreeningBundleProvider);
    final hasCrisis = screening?.crisisFlag == true;
    if (hasCrisis != state.isActive) {
      state = state.copyWith(isActive: hasCrisis);
    }
  }

  void checkLatestScreening() => _checkCrisisFlag();

  Future<void> callHotline() async {
    final uri = Uri(scheme: 'tel', path: crisisHotlineNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      state = state.copyWith(lastTriggered: DateTime.now());
    }
  }

  Future<void> callExtension() async {
    final uri =
        Uri(scheme: 'tel', path: '$crisisHotlineNumber$crisisHotlineExtension');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      state = state.copyWith(lastTriggered: DateTime.now());
    }
  }

  void dismiss() {
    state = state.copyWith(isActive: false);
  }
}

// ============================================================
// PROVIDER
// ============================================================

final crisisProvider =
    StateNotifierProvider<CrisisNotifier, CrisisState>((ref) {
  final notifier = CrisisNotifier(ref);
  ref.listen<ScreeningBundle?>(latestScreeningBundleProvider, (_, __) {
    notifier.checkLatestScreening();
  });
  return notifier;
});

final hasCrisisFlagProvider = Provider<bool>((ref) {
  return ref.watch(crisisProvider).isActive;
});
