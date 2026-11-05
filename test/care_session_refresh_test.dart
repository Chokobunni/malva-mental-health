import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/care_session_refresh.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  testWidgets('session end refresh remains armed when opening reload fails',
      (tester) async {
    initializeWib();
    ServerClock.reset();
    var refreshes = 0;
    final refresh = CareSessionRefresh(() => refreshes++, poll: false);
    refresh.update([
      BackendCareSession(
          id: 'session',
          patientId: 'patient',
          professionalId: 'professional',
          sessionType: 'chat',
          scheduledAt: wibIso(
              ServerClock.now().add(const Duration(minutes: 10, seconds: 2))),
          durationMinutes: 30,
          status: 'scheduled')
    ]);
    await tester.pump(const Duration(seconds: 3));
    expect(refreshes, 1, reason: 'opening refresh fires without a reload');
    await tester.pump(const Duration(minutes: 40));
    expect(refreshes, 2,
        reason: 'end refresh must not depend on network success');
    refresh.dispose();
    ServerClock.reset();
  });
}
