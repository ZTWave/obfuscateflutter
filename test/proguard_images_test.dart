import 'dart:io';

import 'package:obfuscateflutter/consts.dart';
import 'package:obfuscateflutter/proguard_images.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('proguardImages supports file entries in pubspec assets', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_images_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    final imageDir = Directory(
      p.join(projectDir.path, 'assets', 'images'),
    )..createSync(recursive: true);
    final imageFile = File(p.join(imageDir.path, 'anonymous_avatars.png'))
      ..writeAsBytesSync([0, 1, 2, 3]);

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
const avatar = 'assets/images/anonymous_avatars.png';
''');
    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
flutter:
  assets:
    - assets/images/anonymous_avatars.png
''');

    proguardImages(projectDir.path);

    expect(imageFile.existsSync(), isFalse);
    final renamedImages = imageDir
        .listSync()
        .whereType<File>()
        .where((file) => getFileExtName(file) == '.png')
        .toList();
    expect(renamedImages, hasLength(1));
    expect(p.basename(renamedImages.single.path),
        isNot(equals('anonymous_avatars.png')));

    final source =
        File(p.join(projectDir.path, 'lib', 'main.dart')).readAsStringSync();
    expect(source, isNot(contains('anonymous_avatars.png')));
    expect(source,
        contains('assets/images/${p.basename(renamedImages.single.path)}'));

    final pubspec =
        File(p.join(projectDir.path, 'pubspec.yaml')).readAsStringSync();
    expect(pubspec, isNot(contains('assets/images/anonymous_avatars.png')));
    expect(pubspec,
        contains('assets/images/${p.basename(renamedImages.single.path)}'));
  });
}
