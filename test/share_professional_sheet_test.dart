import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/share_professional_sheet.dart';

void main() {
  test('lists connected packages and live one-off sessions once each', () {
    BackendPatientProfessionalLink link(String id,
            {String status = 'active'}) =>
        BackendPatientProfessionalLink(
          patientId: 'patient',
          professionalUserId: id,
          professionalId: 'credential-$id',
          patientDisplayName: 'Pasien',
          professionalDisplayName: id,
          status: status,
        );
    BackendCarePackage package(String id, {String? expiry}) =>
        BackendCarePackage(
          id: 'package-$id',
          patientId: 'patient',
          professionalId: id,
          status: 'active',
          expiresAt: expiry,
        );
    BackendCareSession session(String id, String time,
            {String type = 'chat'}) =>
        BackendCareSession(
          id: 'session-$id',
          patientId: 'patient',
          professionalId: id,
          professionalName: id,
          status: 'scheduled',
          sessionType: type,
          scheduledAt: '2026-11-28T$time:00+07:00',
        );
    final recipients = eligibleShareRecipients(
      now: wibFromParts(2026, 11, 28, 13),
      packages: [
        package('linked'),
        package('expired', expiry: '2026-11-28T13:00:00+07:00'),
        package('unlinked'),
      ],
      links: [
        link('linked'),
        link('expired'),
        link('unlinked', status: 'ended')
      ],
      sessions: [
        session('linked', '13:00'),
        session('chat', '13:00'),
        session('video', '12:59', type: 'video'),
        session('waiting room', '13:05'),
        session('ended', '12:00'),
      ],
    );
    expect(recipients.map((recipient) => recipient.id), [
      'linked',
      'chat',
      'video',
    ]);
  });
}
