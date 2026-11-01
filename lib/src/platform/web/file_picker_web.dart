// `hide PickedFile`: image_picker mengekspor PickedFile-nya sendiri yang
// bertabrakan dengan PickedFile (port) di contracts/ports.dart.
import 'package:image_picker/image_picker.dart' hide PickedFile;

import '../contracts/ports.dart';

/// [FilePickerPort] web: `image_picker` punya implementasi web (input file
/// browser). Selalu membaca byte; `XFile.path` di web adalah blob URL, bukan
/// berkas nyata, sehingga byte adalah satu-satunya sumber kebenaran.
class ImagePickerAdapterWeb implements FilePickerPort {
  ImagePickerAdapterWeb({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

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
      // image_picker_for_web mengecilkan gambar via canvas (image_resizer.dart)
      // memakai maxWidth/maxHeight/imageQuality — bukan diabaikan.
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
