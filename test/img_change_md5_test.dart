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
}
