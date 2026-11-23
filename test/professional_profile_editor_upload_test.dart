import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// `hide PickedFile`: platform interface mengekspor PickedFile-nya sendiri yang
// bertabrakan dengan PickedFile (port) di contracts/ports.dart.
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    hide PickedFile;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/io/file_picker_io.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/screens/professional_profile_editor_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

/// Merekam parameter kompresi yang diteruskan ke port, lalu membatalkan
/// pemilihan (return null) agar layar tidak lanjut ke unggah.
class _RecordingFilePickerPort implements FilePickerPort {
  int calls = 0;
  String? kind;
  int? maxWidth;
  int? maxHeight;
  int? imageQuality;

  @override
  Future<PickedFile?> pick(
    String kind, {
    int? maxWidth,
    int? maxHeight,
    int? imageQuality,
  }) async {
    calls++;
    this.kind = kind;
    this.maxWidth = maxWidth;
    this.maxHeight = maxHeight;
    this.imageQuality = imageQuality;
    return null;
  }
}

/// Menangkap [ImagePickerOptions] yang sampai ke platform plugin.
class _RecordingImagePickerPlatform extends ImagePickerPlatform {
  ImagePickerOptions? lastOptions;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    lastOptions = options;
    return XFile.fromData(
      Uint8List.fromList(<int>[1, 2, 3]),
      name: 'x.png',
      mimeType: 'image/png',
    );
  }
}

/// Api client palsu: getMyCredentials null → layar tampil normal (tombol galeri).
class _FakeApi extends MalvaApiClient {
  _FakeApi() : super(baseUrl: 'http://backend.test');

  @override
  Future<BackendUserProfile> fetchUserProfile({
    required String accessToken,
  }) async =>
      const BackendUserProfile(
        id: 'test-professional',
        email: 'pro@malva.app',
        role: 'professional',
        displayName: 'dr. Malva',
        dateOfBirth: '1990-03-21',
      );

  @override
  Future<BackendProfessionalCredential?> getMyCredentials({
    required String accessToken,
  }) async =>
      null;
}

void main() {
  group('kompresi foto', () {
    late ImagePickerPlatform originalPlatform;
    setUp(() => originalPlatform = ImagePickerPlatform.instance);
    tearDown(() => ImagePickerPlatform.instance = originalPlatform);

    test('ImagePickerAdapter (io) meneruskan maxWidth/maxHeight/imageQuality',
        () async {
      final platform = _RecordingImagePickerPlatform();
      ImagePickerPlatform.instance = platform;

      final adapter = ImagePickerAdapter();
      await adapter.pick(
        'image',
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      expect(platform.lastOptions, isNotNull);
      expect(platform.lastOptions!.maxWidth, 1024);
      expect(platform.lastOptions!.maxHeight, 1024);
      expect(platform.lastOptions!.imageQuality, 85);
    });

    testWidgets('layar meneruskan 1024/1024/85 ke FilePickerPort',
        (tester) async {
      final picker = _RecordingFilePickerPort();
      final api = _FakeApi();
      const session = AuthSession(
        role: UserRole.professional,
        identifier: 'pro@malva.app',
        displayName: 'dr. Malva',
        accessToken: 'token_123',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [filePickerProvider.overrideWithValue(picker)],
          child: MaterialApp(
            home: ProfessionalProfileEditorScreen(
              session: session,
              apiClient: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('21/03/1990'), findsOneWidget);
      expect(find.text('Simpan Profil'), findsOneWidget);

      final gallery = find.text('Pilih dari Galeri');
      expect(gallery, findsOneWidget);

      await tester.tap(gallery);
      await tester.pumpAndSettle();

      expect(picker.calls, 1);
      expect(picker.kind, 'image');
      expect(picker.maxWidth, 1024);
      expect(picker.maxHeight, 1024);
      expect(picker.imageQuality, 85);
    });

    testWidgets('saves the selected calendar day through the account API',
        (tester) async {
      String? savedBirthDate;
      var credentialSaves = 0;
      final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/me') {
            if (request.method == 'PATCH') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              savedBirthDate = body['date_of_birth'] as String?;
            }
            return http.Response(
                jsonEncode({
                  'user': {
                    'id': 'test-professional',
                    'date_of_birth': savedBirthDate ?? '1990-03-21',
                  },
                }),
                200);
          }
          if (request.method == 'POST') credentialSaves++;
          return http.Response(
              jsonEncode({
                'credential': {
                  'id': 'test-credentials',
                  'user_id': 'test-professional',
                },
              }),
              200);
        }),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ProfessionalProfileEditorScreen(
              session: const AuthSession(
                role: UserRole.professional,
                identifier: 'pro@malva.app',
                displayName: 'dr. Malva',
                accessToken: 'token_123',
              ),
              apiClient: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('21/03/1990'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1990').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('22').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('22/03/1990'), findsOneWidget);
      expect(savedBirthDate, isNull);
      await tester.tap(find.text('Simpan Profil'));
      await tester.pumpAndSettle();
      expect(savedBirthDate, '1990-03-22');
      expect(credentialSaves, 1);
      expect(find.text('Profil berhasil disimpan.'), findsOneWidget);
    });
  });
}
