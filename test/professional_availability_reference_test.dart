import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets('editing a shared slot preserves inactive state and other slots',
      (tester) async {
    final api = _AvailabilityApi();
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ProAvailabilityScreen(
          apiClient: api,
          session: const AuthSession(
            role: UserRole.professional,
            identifier: 'pro',
            displayName: 'Pro',
            accessToken: 'token',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opsi jadwal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit jadwal'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).last,
      '75',
    );
    await tester.tap(find.text('Simpan perubahan'));
    await tester.pumpAndSettle();
    expect(api.saved, hasLength(2));
    expect(api.saved!.first['slot_duration_minutes'], 75);
    expect(api.saved!.first['is_active'], false);
    expect(api.saved!.last['day_of_week'], 5);
  });
}

class _AvailabilityApi extends MalvaApiClient {
  final slots = [
    BackendProfessionalSchedule.fromJson({
      'id': 'monday',
      'day_of_week': 1,
      'start_time': '09:00',
      'end_time': '12:00',
      'slot_duration_minutes': 60,
      'is_active': false,
    }),
    BackendProfessionalSchedule.fromJson({
      'id': 'friday',
      'day_of_week': 5,
      'start_time': '09:00',
      'end_time': '12:00',
      'slot_duration_minutes': 60,
      'is_active': true,
    }),
  ];

  List<Map<String, Object?>>? saved;

  @override
  Future<List<BackendProfessionalSchedule>> listMySchedules({
    required String accessToken,
  }) async =>
      slots;

  @override
  Future<BackendProfessionalPricing> getPricing({
    required String accessToken,
    String? professionalId,
  }) async =>
      BackendProfessionalPricing.fromJson({});

  @override
  Future<List<BackendTimeOff>> listTimeOff({
    required String accessToken,
    String? professionalId,
    String? from,
    String? to,
  }) async =>
      [];

  @override
  Future<List<BackendProfessionalSchedule>> updateMySchedules({
    required String accessToken,
    required List<Map<String, Object?>> schedules,
  }) async {
    saved = schedules;
    return slots;
  }
}
