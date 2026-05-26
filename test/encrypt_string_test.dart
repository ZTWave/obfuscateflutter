import 'dart:io';

import 'package:obfuscateflutter/encrypt_string.dart';
import 'package:test/test.dart';

void main() {
  test('generated string decryptor uses a bounded lru cache', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_string_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    File('${projectDir.path}/pubspec.yaml').writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
''');
    Directory('${projectDir.path}/lib').createSync();
    File('${projectDir.path}/lib/main.dart').writeAsStringSync('''
String label() => 'runtime';
''');

    encryptStrings(projectDir.path);

    final keyFileContent =
        File('${projectDir.path}/lib/stren_arg.dart').readAsStringSync();

    expect(keyFileContent, contains("import 'dart:collection';"));
    expect(keyFileContent, contains('const int _DES_CACHE_LIMIT = 512;'));
    expect(keyFileContent, contains('final _desCache = LinkedHashMap'));
    expect(keyFileContent, contains('_desCache.remove(s)'));
    expect(keyFileContent, contains('_desCache.remove(_desCache.keys.first)'));
  });

  test('existing decryptor without cache is regenerated', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_string_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    File('${projectDir.path}/pubspec.yaml').writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
''');
    Directory('${projectDir.path}/lib').createSync();
    File('${projectDir.path}/lib/main.dart').writeAsStringSync('''
String label() => 'runtime';
''');
    File('${projectDir.path}/lib/stren_arg.dart').writeAsStringSync('''
import 'dart:convert';

const String SEP = 'abc';
const int SEK = 7;

String des(String s) {
  return s;
}
''');

    encryptStrings(projectDir.path);

    final keyFileContent =
        File('${projectDir.path}/lib/stren_arg.dart').readAsStringSync();

    expect(keyFileContent, contains('const int _DES_CACHE_LIMIT = 512;'));
  });

  test('decrypts encrypted strings back to source literals', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_string_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    File('${projectDir.path}/pubspec.yaml').writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
''');
    Directory('${projectDir.path}/lib').createSync();
    final sourceFile = File('${projectDir.path}/lib/main.dart')
      ..writeAsStringSync(r'''
String label() => 'hello "world"\n中文';
''');

    encryptStrings(projectDir.path);

    expect(sourceFile.readAsStringSync(), contains('des("'));
    expect(File('${projectDir.path}/lib/stren_arg.dart').existsSync(), isTrue);

    decryptStrings(projectDir.path);

    final restored = sourceFile.readAsStringSync();
    expect(restored, contains(r'''String label() => 'hello "world"\n中文';'''));
    expect(restored,
        isNot(contains("import 'package:sample_app/stren_arg.dart';")));
    expect(File('${projectDir.path}/lib/stren_arg.dart').existsSync(), isFalse);
  });
}
