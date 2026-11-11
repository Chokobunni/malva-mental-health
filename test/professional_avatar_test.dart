import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/widgets/professional_avatar.dart';

void main() {
  for (final roundedSquare in [false, true]) {
    testWidgets(
        'refreshes changed SVG URL after a failed photo ($roundedSquare)',
        (tester) async {
      final requested = <String>[];
      await http.runWithClient(() async {
        Widget avatar(String photo) => MaterialApp(
            home: Scaffold(
                body: ProfessionalAvatar(
                    displayName: 'Profesional',
                    photoUrl: photo,
                    borderRadius:
                        roundedSquare ? BorderRadius.circular(12) : null)));
        await tester.pumpWidget(avatar('https://photo.test/old.svg'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(avatar('https://photo.test/new.svg'));
        await tester.pumpAndSettle();
        expect(requested, ['/old.svg', '/new.svg']);
        expect(tester.takeException(), isNull);
      },
          () => MockClient((request) async {
                requested.add(request.url.path);
                return http.Response('', 404);
              }));
    });
  }
  group('isSvgPhotoUrl', () {
    test('URL DiceBear notionists SVG terdeteksi sebagai SVG', () {
      expect(
        isSvgPhotoUrl(
            'https://api.dicebear.com/9.x/notionists/svg?seed=6666555544443333'),
        isTrue,
      );
    });

    test('URL berakhiran .svg terdeteksi sebagai SVG', () {
      expect(
          isSvgPhotoUrl('https://api.malva.web.id/uploads/avatar.svg'), isTrue);
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
