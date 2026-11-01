// `hide PickedFile`: image_picker mengekspor PickedFile-nya sendiri yang
// bertabrakan dengan PickedFile (port) di contracts/ports.dart.
import 'package:image_picker/image_picker.dart' hide PickedFile;

import '../contracts/ports.dart';

/// [FilePickerPort] berbasis `image_picker`. Selalu membaca byte
/// (`readAsBytes`) sehingga tidak pernah memakai `File(picked.path)` —
/// akar kerusakan unggah berkas di web.
class ImagePickerAdapter implements FilePickerPort {
  ImagePickerAdapter({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedFile?> pick(
    String kind, {
    int? maxWidth,
    int? maxHeight,
    int? imageQuality,
  }) async {
    final XFile? picked;
    if (kind == 'video') {
      // Video tidak dikompresi (sama seperti perilaku lama).
      picked = await _picker.pickVideo(source: ImageSource.gallery);
    } else {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth?.toDouble(),
        maxHeight: maxHeight?.toDouble(),
        imageQuality: imageQuality,
      );
    }
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return PickedFile(
      name: picked.name,
      bytes: bytes,
      mimeType: picked.mimeType ?? _defaultMimeType(kind),
    );
  }

  String _defaultMimeType(String kind) =>
      kind == 'video' ? 'video/mp4' : 'image/jpeg';
}
