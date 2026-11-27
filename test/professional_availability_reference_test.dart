import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/professional_availability_summary.dart';

void main() {
  test(
      'inactive category rows suppress the shared schedule only for that service',
      () {
    final api = _AvailabilityApi();
    expect(professionalServiceSchedules(api.slots, 'quick_chat').single.id,
        'monday');
    expect(
        professionalServiceSchedules(api.slots, 'quick_chat').single.isActive,
        isFalse);
    expect(professionalServiceSchedules(api.slots, 'quick_video').single.id,
        'friday');
  });

  testWidgets(
      'editing a categorized slot preserves inactive state and other slots',
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
    final chatOption = find.byTooltip('Opsi jadwal').last;
    await tester.scrollUntilVisible(chatOption.hitTestable(), 150);
    await tester.tap(chatOption);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit jadwal'));
    await tester.pumpAndSettle();
    final dialog = find.byType(BottomSheet);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)).last,
      '75',
    );
    await tester.tap(find.text('Simpan perubahan'));
    await tester.pumpAndSettle();
    expect(api.saved, hasLength(1));
    expect(api.saved!.first['slot_duration_minutes'], 75);
    expect(api.saved!.first['is_active'], false);
    expect(api.saved!.first['id'], 'monday');
    expect(api.saved!.first['service_category'], 'quick_chat');
  });

  testWidgets('capacity can close new packages and stays finite',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    final decrease = find.byTooltip('Kurangi kapasitas');
    await tester.scrollUntilVisible(decrease.hitTestable(), 180);
    await tester.tap(decrease);
    await tester.pumpAndSettle();
    var save = find.text('Simpan kapasitas');
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(api.savedCapacity, 0);
    expect(api.clearedCapacity, isFalse);
    expect(find.text('Ditutup untuk pasien baru'), findsOneWidget);

    expect(find.text('Tanpa batas'), findsNothing);
    expect(find.text('Jadwal bersama'), findsNothing);
    expect(find.text('Hari libur'), findsNothing);
    expect(find.text('Mengikuti jadwal bersama.'), findsNothing);
  });

  testWidgets('summary shows effective rows, real durations and finite default',
      (tester) async {
    final api = _AvailabilityApi();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: ProfessionalAvailabilitySummary(
          schedules: api.slots,
          pricing: BackendProfessionalPricing.fromJson({})),
    ))));
    expect(find.text('Jadwal & tarif'), findsOneWidget);
    expect(find.text('Hari libur: belum ada'), findsNothing);
    expect(find.text('Maks. 2 pasien aktif'), findsOneWidget);
    expect(find.text('60 mnt/sesi'), findsNWidgets(3));
    expect(find.text('Nonaktif'), findsOneWidget);
    expect(find.text('Aktif'), findsNWidgets(2));
  });

  testWidgets('editor defaults a missing legacy quota to two patients',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: ProAvailabilityScreen(
                apiClient: _AvailabilityApi(capacity: null),
                session: const AuthSession(
                    role: UserRole.professional,
                    identifier: 'pro',
                    displayName: 'Pro',
                    accessToken: 'token')))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Maks. 2 pasien aktif'), 180);
    expect(find.text('Maks. 2 pasien aktif'), findsOneWidget);
    expect(find.text('Tanpa batas'), findsNothing);
    expect(find.text('Simpan kapasitas'), findsNothing);
  });

  testWidgets(
      'package warning responds to effective schedule and draft overlap',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    expect(find.text('Jadwal praktik utama'), findsOneWidget);
    final warning =
        find.textContaining('Jam ini juga tersedia untuk Quick Session.');
    expect(warning, findsNothing);
    final packageSwitch = find
        .widgetWithText(SwitchListTile, 'Gunakan jadwal praktik utama')
        .last;
    await tester.ensureVisible(packageSwitch);
    await tester.tap(packageSwitch);
    await tester.pumpAndSettle();
    expect(api.preferences['package'], isTrue);
    expect(api.saved, isNull);
    expect(warning, findsOneWidget);
    expect(api.slots.map((slot) => slot.id), ['monday', 'friday']);
    await tester.tap(packageSwitch);
    await tester.pumpAndSettle();
    expect(api.preferences['package'], isFalse);
    expect(warning, findsNothing);

    final add = find.text('Tambah jadwal khusus').last;
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Senin').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jumat').last);
    await tester.pumpAndSettle();
    expect(warning, findsOneWidget);
    final active = find.widgetWithText(SwitchListTile, 'Aktif');
    await tester.tap(active);
    await tester.pumpAndSettle();
    expect(warning, findsNothing);
  });
}

class _AvailabilityApi extends MalvaApiClient {
  _AvailabilityApi({this.capacity = 1});
  final int? capacity;
  final slots = [
    BackendProfessionalSchedule.fromJson({
      'id': 'monday',
      'service_category': 'quick_chat',
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
  int? savedCapacity;
  bool clearedCapacity = false;
  final preferences = {
    'quick_chat': false,
    'quick_video': true,
    'package': false
  };

  @override
  Future<BackendProfessionalScheduleSettings> getMyScheduleSettings({
    required String accessToken,
  }) async =>
      (schedules: slots, usePrimarySchedule: Map.of(preferences));

  @override
  Future<BackendProfessionalPricing> getPricing({
    required String accessToken,
    String? professionalId,
  }) async =>
      BackendProfessionalPricing.fromJson({'patient_capacity': capacity});

  @override
  Future<BackendProfessionalPricing> updatePricing({
    required String accessToken,
    int? quickChatPrice,
    int? quickVideoPrice,
    int? packagePrice,
    int? patientCapacity,
    bool clearPatientCapacity = false,
  }) async {
    savedCapacity = patientCapacity;
    clearedCapacity = clearPatientCapacity;
    return BackendProfessionalPricing.fromJson(
        {'patient_capacity': patientCapacity});
  }

  @override
  Future<List<BackendTimeOff>> listTimeOff({
    required String accessToken,
    String? professionalId,
    String? from,
    String? to,
  }) async =>
      [];

  @override
  Future<BackendProfessionalScheduleSettings> updateMyScheduleSettings({
    required String accessToken,
    List<Map<String, Object?>>? schedules,
    Map<String, bool>? usePrimarySchedule,
  }) async {
    saved = schedules;
    if (usePrimarySchedule != null) preferences.addAll(usePrimarySchedule);
    return getMyScheduleSettings(accessToken: accessToken);
  }
}
