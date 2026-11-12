import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/services/goal_reminder_service.dart';
import 'package:malva_mental_health/src/services/local_notification_router.dart';
import 'package:malva_mental_health/src/services/push_notification_service.dart';
import 'package:malva_mental_health/src/time/wib.dart';

/// SecureStore in-memory untuk test preferensi (tanpa plugin platform).
class _MemoryStore implements SecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// Penjadwal palsu: mencatat pemanggilan tanpa menyentuh plugin.
class _RecordingScheduler implements GoalReminderScheduler {
  int initializeCalls = 0;
  final List<({int id, DateTime scheduledAt, String payload})> scheduled =
      <({int id, DateTime scheduledAt, String payload})>[];
  final List<int> cancelled = <int>[];

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    required String payload,
  }) async {
    scheduled.add((id: id, scheduledAt: scheduledAt, payload: payload));
  }

  @override
  Future<void> scheduleOnce(
      {required int id,
      required String title,
      required String body,
      required DateTime scheduledAt,
      required String payload}) async {}

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}

void main() {
  group('nextGoalReminderOccurrence', () {
    test('sebelum jam pengingat → hari ini pada jam tersebut (WIB)', () {
      final scheduled = GoalReminderService.nextGoalReminderOccurrence(
        19,
        0,
        now: wibFromParts(2026, 11, 2, 10, 0),
      );

      expect(scheduled.year, 2026);
      expect(scheduled.month, 11);
      expect(scheduled.day, 2);
      expect(scheduled.hour, 19);
      expect(scheduled.minute, 0);
      // Selalu WIB, bukan zona perangkat.
      expect(scheduled.location.name, wibLocationName);
      expect(scheduled.timeZoneOffset, const Duration(hours: 7));
    });

    test('tepat pada jam pengingat → besok (tidak menembak dua kali)', () {
      final scheduled = GoalReminderService.nextGoalReminderOccurrence(
        19,
        0,
        now: wibFromParts(2026, 11, 2, 19, 0),
      );

      expect(scheduled.day, 3);
      expect(scheduled.hour, 19);
    });

    test('setelah jam pengingat → besok pada jam yang sama', () {
      final scheduled = GoalReminderService.nextGoalReminderOccurrence(
        7,
        30,
        now: wibFromParts(2026, 11, 2, 20, 15),
      );

      expect(scheduled.day, 3);
      expect(scheduled.hour, 7);
      expect(scheduled.minute, 30);
    });

    test('pergantian bulan ditangani lewat komponen kalender WIB', () {
      final scheduled = GoalReminderService.nextGoalReminderOccurrence(
        19,
        0,
        now: wibFromParts(2026, 11, 30, 20, 0),
      );

      expect(scheduled.month, 12);
      expect(scheduled.day, 1);
      expect(scheduled.hour, 19);
      expect(scheduled.location.name, wibLocationName);
    });
  });

  group('Aturan penjadwalan', () {
    test('hanya dijadwalkan bila aktif DAN ada goal aktif', () {
      expect(
        GoalReminderService.shouldSchedule(hasActiveGoals: true, enabled: true),
        isTrue,
      );
      expect(
        GoalReminderService.shouldSchedule(
            hasActiveGoals: false, enabled: true),
        isFalse,
      );
      expect(
        GoalReminderService.shouldSchedule(
            hasActiveGoals: true, enabled: false),
        isFalse,
      );
    });

    test('sync menjadwalkan satu notifikasi harian saat aktif & ada goal',
        () async {
      final scheduler = _RecordingScheduler();
      final service = GoalReminderService(
        store: _MemoryStore(),
        scheduler: scheduler,
      );

      await service.sync(
        hasActiveGoals: true,
        enabled: true,
        hour: 19,
        minute: 0,
      );

      expect(scheduler.scheduled, hasLength(1));
      expect(scheduler.scheduled.single.id, GoalReminderService.notificationId);
      expect(scheduler.scheduled.single.scheduledAt.hour, 19);
      expect(scheduler.scheduled.single.payload, 'goal_reminder');
      expect(scheduler.cancelled, isEmpty);
    });

    test('sync membatalkan (tidak menjadwalkan) saat pengingat dimatikan',
        () async {
      final scheduler = _RecordingScheduler();
      final service = GoalReminderService(
        store: _MemoryStore(),
        scheduler: scheduler,
      );

      await service.sync(
        hasActiveGoals: true,
        enabled: false,
        hour: 19,
        minute: 0,
      );

      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelled, contains(GoalReminderService.notificationId));
    });

    test('sync membatalkan (tidak menjadwalkan) saat tidak ada goal aktif',
        () async {
      final scheduler = _RecordingScheduler();
      final service = GoalReminderService(
        store: _MemoryStore(),
        scheduler: scheduler,
      );

      await service.sync(
        hasActiveGoals: false,
        enabled: true,
        hour: 19,
        minute: 0,
      );

      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelled, contains(GoalReminderService.notificationId));
    });

    test('service yang dimatikan (web) tidak memanggil penjadwal sama sekali',
        () async {
      final scheduler = _RecordingScheduler();
      final service = GoalReminderService(
        enabled: false,
        store: _MemoryStore(),
        scheduler: scheduler,
      );

      await service.initialize();
      await service.sync(
        hasActiveGoals: true,
        enabled: true,
        hour: 19,
        minute: 0,
      );
      await service.cancel();

      expect(scheduler.initializeCalls, 0);
      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.cancelled, isEmpty);
    });
  });

  group('Preferensi pengingat goals', () {
    test('bawaan: aktif pada 19:00', () async {
      final service = GoalReminderService(store: _MemoryStore());

      final settings = await service.loadSettings();
      expect(settings.enabled, isTrue);
      expect(settings.hour, GoalReminderService.defaultHour);
      expect(settings.minute, GoalReminderService.defaultMinute);
      expect(settings.label, '19:00');
    });

    test('simpan lalu baca kembali mempertahankan nilai', () async {
      final store = _MemoryStore();
      final service = GoalReminderService(store: store);

      await service.saveSettings(
        const GoalReminderSettings(enabled: false, hour: 7, minute: 30),
      );
      final loaded = await service.loadSettings();

      expect(loaded.enabled, isFalse);
      expect(loaded.hour, 7);
      expect(loaded.minute, 30);
      expect(store.values[GoalReminderService.enabledStorageKey], 'false');
    });

    test('nilai rusak di-clamp dan tidak melempar', () async {
      final store = _MemoryStore()
        ..values[GoalReminderService.hourStorageKey] = '99'
        ..values[GoalReminderService.minuteStorageKey] = '-5'
        ..values[GoalReminderService.enabledStorageKey] = 'bukan-bool';
      final service = GoalReminderService(store: store);

      final settings = await service.loadSettings();
      expect(settings.hour, 23);
      expect(settings.minute, 0);
      // Selain 'false' dianggap aktif (bawaan aman).
      expect(settings.enabled, isTrue);
    });
  });

  group('ID notifikasi stabil', () {
    const data = <String, dynamic>{
      'kind': 'chat_message',
      'session_id': 'session-1',
      'notification_id': 'notif-1',
      'patient_id': 'patient-1',
    };

    test('data sama menghasilkan id sama (deterministik antar-instance)', () {
      final first = PushNotificationService.notificationIdFor(data);
      final second = PushNotificationService.notificationIdFor(
          Map<String, dynamic>.from(data));

      expect(first, second);
      expect(first, greaterThan(0));
      expect(first, lessThanOrEqualTo(0x7fffffff));
    });

    test('data berbeda menghasilkan id berbeda', () {
      final base = PushNotificationService.notificationIdFor(data);
      final otherNotification = PushNotificationService.notificationIdFor(
        <String, dynamic>{...data, 'notification_id': 'notif-2'},
      );
      final otherKind = PushNotificationService.notificationIdFor(
        <String, dynamic>{...data, 'kind': 'crisis_alert'},
      );

      expect(base, isNot(otherNotification));
      expect(base, isNot(otherKind));
    });
  });

  group('Pemetaan rute & penekanan chat', () {
    test('chat_message dipetakan ke /chat', () {
      expect(
        PushNotificationService.routeForType('chat_message', const {}),
        '/chat',
      );
    });

    test('pemetaan lama tidak berubah', () {
      expect(PushNotificationService.routeForType('crisis_alert', const {}),
          '/crisis-alert');
      expect(
          PushNotificationService.routeForType('medication_reminder', const {}),
          '/medication');
      expect(
          PushNotificationService.routeForType('follow_up', const {}), '/home');
      expect(PushNotificationService.routeForType('tidak_dikenal', const {}),
          isNull);
    });

    test('chat dari peer yang sedang dibuka ditekan', () {
      const data = <String, dynamic>{
        'type': 'chat_message',
        'sender_id': 'pro-1',
      };

      expect(
        PushNotificationService.shouldShowChatNotification(data, 'pro-1'),
        isFalse,
      );
      expect(
        PushNotificationService.shouldShowChatNotification(data, 'pro-2'),
        isTrue,
      );
      expect(
        PushNotificationService.shouldShowChatNotification(data, null),
        isTrue,
      );
    });

    test('notifikasi remote non-chat tidak ditampilkan', () {
      const data = <String, dynamic>{
        'type': 'crisis_alert',
        'sender_id': 'pro-1',
      };

      expect(
        PushNotificationService.shouldShowChatNotification(data, 'pro-1'),
        isFalse,
      );
    });
  });

  group('Payload backend memakai kunci kind (bukan type)', () {
    test('kind saja tetap terpetakan ke /chat', () {
      // Bentuk nyata dari backend: hanya `kind`, tanpa `type`.
      const data = <String, dynamic>{
        'kind': 'chat_message',
        'sender_id': 'pro-1',
        'sender_name': 'Dr. Ayu',
        'session_id': 'session-1',
        'patient_id': 'patient-1',
      };

      final kind = PushNotificationService.eventKindOf(data);
      expect(kind, 'chat_message');
      expect(PushNotificationService.routeForType(kind, data), '/chat');
    });

    test('kind saja tetap ditekan saat peer itu sedang dibuka', () {
      const data = <String, dynamic>{
        'kind': 'chat_message',
        'sender_id': 'pro-1',
        'sender_name': 'Dr. Ayu',
      };

      expect(
        PushNotificationService.shouldShowChatNotification(data, 'pro-1'),
        isFalse,
      );
      expect(
        PushNotificationService.shouldShowChatNotification(data, 'pro-2'),
        isTrue,
      );
    });

    test('kind lain tetap dipetakan sesuai jenisnya', () {
      expect(
        PushNotificationService.routeForType(
          PushNotificationService.eventKindOf(<String, dynamic>{
            'kind': 'medication_reminder',
          }),
          const <String, dynamic>{},
        ),
        '/medication',
      );
      expect(
        PushNotificationService.eventKindOf(<String, dynamic>{
          'kind': 'crisis_alert',
        }),
        'crisis_alert',
      );
    });

    test('type tetap diutamakan untuk payload lama, lalu fallback ke kind', () {
      expect(
        PushNotificationService.eventKindOf(<String, dynamic>{
          'type': 'follow_up',
          'kind': 'chat_message',
        }),
        'follow_up',
      );
      expect(
        PushNotificationService.eventKindOf(const <String, dynamic>{}),
        '',
      );
    });

    test('ID notifikasi kind-only stabil dan berbeda antar peristiwa', () {
      const first = <String, dynamic>{
        'kind': 'chat_message',
        'sender_id': 'pro-1',
        'notification_id': 'n-1',
      };
      const second = <String, dynamic>{
        'kind': 'chat_message',
        'sender_id': 'pro-1',
        'notification_id': 'n-2',
      };

      expect(
        PushNotificationService.notificationIdFor(first),
        PushNotificationService.notificationIdFor(
          Map<String, dynamic>.from(first),
        ),
      );
      expect(
        PushNotificationService.notificationIdFor(first),
        isNot(PushNotificationService.notificationIdFor(second)),
      );
    });
  });

  group('LocalNotificationRouter', () {
    tearDown(LocalNotificationRouter.reset);

    test('payload JSON diteruskan ke handler push', () {
      Map<String, dynamic>? received;
      var medicationCalls = 0;
      LocalNotificationRouter.onPushPayload = (data) => received = data;
      LocalNotificationRouter.onMedicationPayload = (_) => medicationCalls++;

      LocalNotificationRouter.handlePayload(
        '{"type":"chat_message","sender_id":"pro-1"}',
      );

      expect(received?['sender_id'], 'pro-1');
      expect(medicationCalls, 0);
    });

    test('payload id obat diteruskan ke handler pengingat obat', () {
      var pushCalls = 0;
      String? medicationId;
      var openedMedication = false;
      LocalNotificationRouter.onPushPayload = (_) => pushCalls++;
      LocalNotificationRouter.onMedicationPayload = (id) => medicationId = id;
      LocalNotificationRouter.openMedicationScreen =
          () => openedMedication = true;

      LocalNotificationRouter.handlePayload('med-123');

      expect(pushCalls, 0);
      expect(medicationId, 'med-123');
      expect(openedMedication, isTrue);
    });

    test('payload pengingat goals tidak dianggap id obat', () {
      var medicationCalls = 0;
      var openedMedication = false;
      LocalNotificationRouter.onMedicationPayload = (_) => medicationCalls++;
      LocalNotificationRouter.openMedicationScreen =
          () => openedMedication = true;

      LocalNotificationRouter.handlePayload(
        LocalNotificationRouter.goalReminderPayload,
      );

      expect(medicationCalls, 0);
      expect(openedMedication, isFalse);
    });
  });
}
