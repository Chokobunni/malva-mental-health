import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_factory_io.dart'
    as io;
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/platform/web/push_registrar_web.dart';
import 'package:malva_mental_health/src/platform/web/reminder_scheduler_web.dart';
import 'package:malva_mental_health/src/platform/web/web_capabilities.dart';

// Test ini berjalan di VM (`flutter test`). Sisi web dibuktikan lewat berkas
// Dart murni (`web_capabilities.dart`, `*_web.dart`) — BUKAN dengan mengimpor
// `platform_factory_web.dart`, karena berkas itu kini menarik `package:web`
// (API khusus browser) yang tidak bisa dikompilasi ke VM.
void main() {
  group('capabilities impl io (VM/mobile)', () {
    test('factory io mengaktifkan semua kemampuan native', () {
      final caps = io.createCapabilities();
      expect(caps.canScheduleOsReminders, isTrue);
      expect(caps.canRegisterPush, isTrue);
      expect(caps.canExportFiles, isTrue);
      expect(caps.canDialTel, isTrue);
      expect(caps.canPickFiles, isTrue);
      expect(caps.canGeolocate, isTrue);
      expect(caps.canBindGoogleCalendar, isTrue);
      expect(caps.isWebBuild, isFalse);
    });

    test('capabilitiesProvider (VM) memberi canScheduleOsReminders == true',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final caps = container.read(capabilitiesProvider);
      expect(caps.canScheduleOsReminders, isTrue);
      expect(caps.isWebBuild, isFalse);
    });

    test('reminderScheduler io melaporkan penjadwalan OS aktif', () {
      final scheduler = io.createReminderScheduler();
      expect(scheduler.canScheduleOsReminders, isTrue);
    });
  });

  group('capabilities impl web', () {
    test('capability web mematikan fitur yang belum aman di browser', () {
      const caps = webCapabilities;
      expect(caps.canScheduleOsReminders, isFalse);
      expect(caps.canRegisterPush, isFalse);
      expect(caps.canExportFiles, isTrue); // Blob berfungsi di browser
      expect(caps.canDialTel, isFalse);
      expect(caps.canBindGoogleCalendar, isFalse);
      expect(caps.canPickFiles, isTrue);
      expect(caps.canGeolocate, isTrue);
      expect(caps.isWebBuild, isTrue);
    });

    test('reminderScheduler web melaporkan penjadwalan OS nonaktif', () {
      const scheduler = NoopReminderScheduler();
      expect(scheduler.canScheduleOsReminders, isFalse);
    });

    test('pushRegistrar web tidak mendaftarkan token', () {
      final registrar = NoopPushRegistrar();
      expect(registrar.canRegister, isFalse);
    });
  });

  group('kontrak port', () {
    test('PickedFile.size mengikuti panjang byte', () {
      final file = PickedFile(
        name: 'a.txt',
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        mimeType: 'text/plain',
      );
      expect(file.size, 4);
      expect(file.name, 'a.txt');
      expect(file.mimeType, 'text/plain');
    });
  });
}
