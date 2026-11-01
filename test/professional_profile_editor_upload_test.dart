import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
