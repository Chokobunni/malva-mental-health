import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/widgets/professional_avatar.dart';

void main() {
  group('isSvgPhotoUrl', () {
    test('URL DiceBear notionists SVG terdeteksi sebagai SVG', () {
      expect(
        isSvgPhotoUrl(
            'https://api.dicebear.com/9.x/notionists/svg?seed=6666555544443333'),
        isTrue,
      );
    });

    test('URL berakhiran .svg terdeteksi sebagai SVG', () {
      expect(isSvgPhotoUrl('https://api.malva.web.id/uploads/avatar.svg'), isTrue);
    });

    test('URL raster (png/jpg/webp) bukan SVG', () {
      expect(
        isSvgPhotoUrl(
            'https://api.malva.web.id/uploads/a1111111/1792682034485_c35b1528e61562cc.png'),
        isFalse,
      );
      expect(isSvgPhotoUrl('https://example.com/foto.jpg'), isFalse);
      expect(isSvgPhotoUrl('https://example.com/foto.webp'), isFalse);
    });

    test('query string tidak mengganggu deteksi ekstensi', () {
      expect(isSvgPhotoUrl('https://example.com/foto.png?size=200'), isFalse);
      expect(isSvgPhotoUrl('https://example.com/foto.svg?size=200'), isTrue);
    });

    test('huruf besar/kecil diabaikan', () {
      expect(isSvgPhotoUrl('https://example.com/AVATAR.SVG'), isTrue);
    });
  });
}
