import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  final readers = <String, Future<List<Object>> Function(MalvaApiClient)>{
    'moods': (api) => api.listMoodCheckins(accessToken: 'test'),
    'diaries': (api) => api.listDiaryEntries(accessToken: 'test'),
    'goals': (api) => api.listGoals(accessToken: 'test'),
    'medications': (api) => api.listMedications(accessToken: 'test'),
    'medication_logs': (api) => api.listMedicationLogs(accessToken: 'test'),
  };
  for (final reader in readers.entries) {
    MalvaApiClient client(Object payload, {int status = 200}) => MalvaApiClient(
          baseUrl: 'http://backend.test',
          httpClient: MockClient((_) async => http.Response(
              jsonEncode(payload), status,
              headers: {'content-type': 'application/json'})),
        );
    test('${reader.key}: explicit null collection is a valid empty result',
        () async {
      expect(await reader.value(client({reader.key: null})), isEmpty);
    });
    for (final payload in [
      {},
      {reader.key: 'broken'},
      {reader.key: {}},
      {
        reader.key: [1]
      },
      {
        reader.key: [null]
      }
    ]) {
      test('${reader.key}: malformed collection stays an error ($payload)',
          () async {
        await expectLater(
            reader.value(client(payload)), throwsA(isA<MalvaApiException>()));
      });
    }
    test('${reader.key}: server failure stays an error', () async {
      await expectLater(
          reader.value(client({'error': 'unavailable'}, status: 503)),
          throwsA(isA<MalvaApiException>()));
    });
  }
}
