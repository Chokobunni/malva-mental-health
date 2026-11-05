import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/client_intent_id.dart';

void main() {
  test('independent user actions get distinct valid UUIDv4 retry identifiers',
      () {
    final ids = List.generate(100, (_) => newClientIntentId());
    expect(ids.toSet(), hasLength(100));
    for (final id in ids) {
      expect(
          id,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    }
  });
}
