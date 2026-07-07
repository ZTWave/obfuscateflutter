import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:obfuscateflutter/img_change_md5.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('changeImageMd5 supports file entries in pubspec assets', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_md5_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    final imageDir = Directory(p.join(projectDir.path, 'assets', 'images'))
      ..createSync(recursive: true);
    final imageFile = File(p.join(imageDir.path, 'anonymous_avatars.png'));
    final image = img.Image(width: 2, height: 2)
      ..setPixelRgb(0, 0, 20, 40, 60)
      ..setPixelRgb(1, 0, 80, 100, 120)
      ..setPixelRgb(0, 1, 140, 160, 180)
      ..setPixelRgb(1, 1, 200, 220, 240);
    imageFile.writeAsBytesSync(img.PngEncoder().encode(image));

    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
flutter:
  assets:
    - assets/images/anonymous_avatars.png
''');

    expect(() => changeImageMd5(projectDir.path), returnsNormally);
    expect(imageFile.existsSync(), isTrue);
  });

  test('changeImageMd5 still scans directory entries in pubspec assets', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_md5_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    final imageDir = Directory(p.join(projectDir.path, 'assets', 'images'))
      ..createSync(recursive: true);
    final imageFile = File(p.join(imageDir.path, 'avatar.png'));
    final image = img.Image(width: 1, height: 1)..setPixelRgb(0, 0, 20, 40, 60);
    imageFile.writeAsBytesSync(img.PngEncoder().encode(image));

    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
flutter:
  assets:
    - assets/images/
''');

    expect(() => changeImageMd5(projectDir.path), returnsNormally);
    expect(imageFile.existsSync(), isTrue);
  });

  test('changeImageMd5 falls back when image decoding throws', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_md5_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    final imageDir = Directory(p.join(projectDir.path, 'assets', 'images'))
      ..createSync(recursive: true);
    final imageFile = File(p.join(imageDir.path, 'broken.webp'));
    imageFile.writeAsBytesSync([
      ...'RIFF'.codeUnits,
      8,
      0,
      0,
      0,
      ...'WEBP'.codeUnits,
      ...'VP8L'.codeUnits,
    ]);
    final originalLength = imageFile.lengthSync();

    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
flutter:
  assets:
    - assets/images/broken.webp
''');

    expect(() => changeImageMd5(projectDir.path), returnsNormally);
    expect(imageFile.lengthSync(), greaterThan(originalLength));
  });

  test('changeImageMd5 falls back when palette pixel access throws', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_md5_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    final imageDir = Directory(p.join(projectDir.path, 'assets', 'images'))
      ..createSync(recursive: true);
    final imageFile = File(p.join(imageDir.path, 'palette.webp'));
    imageFile.writeAsBytesSync(base64Decode(_paletteWebpBase64));
    final originalLength = imageFile.lengthSync();

    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
flutter:
  assets:
    - assets/images/palette.webp
''');

    expect(() => changeImageMd5(projectDir.path), returnsNormally);
    expect(imageFile.lengthSync(), greaterThan(originalLength));
  });
}

const _paletteWebpBase64 =
    'UklGRp4BAABXRUJQVlA4WAoAAAAQAAAAHwAAHwAAQUxQSKoAAAABf6AmkiQ1e3z3TOmHL+MjIuDJrfv84edoIoKbatuW5f0NaWA7K0RgJYQXYHdI4B0YOSSgAUzMFHB3fv9vIkT0n4HbRoq8zHvwCnFDZbJZ1FLiD2PTE3I+XdMXYh6Zt99cc63MgJB3y2+QtSYyMwNDUuQRrCdZE4LeJ9ETSd9I9U7aLzL9kOWP7Bk3eApvxO+B3xO/R37P+B34O/F3xO/M/wH+J3/9R/ifCVZQOCDOAAAAcAYAnQEqIAAgAD5RHoxEI6GhGAwGADgFBLUAM8EEAegB0kBENHv6/QLMPRVeRSf3cRR+hiiFARUGaAAAAP78eYzR/zn/R1jCKjUFYwBqT//vCOIQydxP/6J/+P50tRfn/g1pGIAHfX6hqG3w4RhIn71yYcpkm3cHnL/ioPPaAaUe/vRHfCis1f8uWDnXdFCnWdTyrWlLG5Vqj/O/N//9lT8w6a/27UG0/xppIkPT0i/yWH/AYdB+ZRrprH6B6rNvLSqAHbqG3Juaw9xAAABWRQ==';
