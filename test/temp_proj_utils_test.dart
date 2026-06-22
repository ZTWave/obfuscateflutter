import 'dart:io';

import 'package:obfuscateflutter/temp_proj_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('copyProjectToTemp skips git metadata while copying project files',
      () async {
    final root = Directory.systemTemp.createTempSync('obf_temp_copy_');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    final source = Directory(p.join(root.path, 'source'))..createSync();
    final target = Directory(p.join(root.path, 'target'))..createSync();
    File(p.join(source.path, '.git')).writeAsStringSync('gitdir: ../repo.git');
    File(p.join(source.path, 'pubspec.yaml')).writeAsStringSync('name: app');
    Directory(p.join(source.path, 'lib')).createSync();
    File(p.join(source.path, 'lib', 'main.dart'))
        .writeAsStringSync('void main() {}');

    await copyProjectToTemp(source.path, target.path);

    expect(File(p.join(target.path, '.git')).existsSync(), isFalse);
    expect(File(p.join(target.path, 'pubspec.yaml')).readAsStringSync(),
        equals('name: app'));
    expect(File(p.join(target.path, 'lib', 'main.dart')).readAsStringSync(),
        equals('void main() {}'));
  });

  test('copyProjectToTemp skips git directories', () async {
    final root = Directory.systemTemp.createTempSync('obf_temp_copy_');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    final source = Directory(p.join(root.path, 'source'))..createSync();
    final target = Directory(p.join(root.path, 'target'))..createSync();
    Directory(p.join(source.path, '.git', 'objects'))
        .createSync(recursive: true);
    File(p.join(source.path, '.git', 'config')).writeAsStringSync('[core]');
    File(p.join(source.path, 'README.md')).writeAsStringSync('sample');

    await copyProjectToTemp(source.path, target.path);

    expect(Directory(p.join(target.path, '.git')).existsSync(), isFalse);
    expect(File(p.join(target.path, 'README.md')).readAsStringSync(),
        equals('sample'));
  });
}
