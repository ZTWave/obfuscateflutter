import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
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

  test('generates string encryption helper under project test directory', () {
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
    final debugFile =
        File('${projectDir.path}/test/obfuscate_string_debug.dart');
    final debugFileContent = debugFile.readAsStringSync();

    expect(parseString(content: keyFileContent).errors, isEmpty);
    expect(keyFileContent, isNot(contains('class ObfuscateStringTest')));
    expect(debugFile.existsSync(), isTrue);
    expect(parseString(content: debugFileContent).errors, isEmpty);
    expect(debugFileContent, contains('class ObfuscateStringTest'));
    expect(debugFileContent,
        contains("import 'package:flutter_test/flutter_test.dart';"));
    expect(debugFileContent,
        contains("import 'package:sample_app/stren_arg.dart';"));
    expect(debugFileContent, contains('static String encrypt(String text)'));
    expect(
        debugFileContent, contains('static String decrypt(String encrypted)'));
    expect(
      debugFileContent,
      contains('static Map<String, String> inspect(String text)'),
    );
    expect(debugFileContent, contains('static bool verify(String text)'));
    expect(debugFileContent, contains("return '\$$defaultStringPrefixName\$"));
    expect(debugFileContent, contains('return $obfStringFuncName(encrypted);'));
    expect(debugFileContent, contains('test("test $obfStringFuncName", () {'));
    expect(
        debugFileContent, contains('final b = ObfuscateStringTest.decrypt("'));
    expect(debugFileContent, contains('print(b);'));
    expect(debugFileContent, contains("expect(b, 'replace this text');"));
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
    expect(keyFileContent, isNot(contains('class ObfuscateStringTest')));
    expect(
      File('${projectDir.path}/test/obfuscate_string_debug.dart').existsSync(),
      isTrue,
    );
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

    expect(sourceFile.readAsStringSync(), contains('$obfStringFuncName("'));
    expect(File('${projectDir.path}/lib/stren_arg.dart').existsSync(), isTrue);

    decryptStrings(projectDir.path);

    final restored = sourceFile.readAsStringSync();
    expect(restored, contains(r'''String label() => 'hello "world"\n中文';'''));
    expect(restored,
        isNot(contains("import 'package:sample_app/stren_arg.dart';")));
    expect(File('${projectDir.path}/lib/stren_arg.dart').existsSync(), isFalse);
  });

  test('does not encrypt part-of directive uri paths', () {
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
    Directory('${projectDir.path}/lib/src').createSync(recursive: true);
    File('${projectDir.path}/lib/user_model.dart').writeAsStringSync('''
part 'src/user_model_fields.dart';

String rootLabel() => 'root';
''');
    final partFile = File('${projectDir.path}/lib/src/user_model_fields.dart')
      ..writeAsStringSync('''
part of '../user_model.dart';

String partLabel() => 'part runtime';
''');

    encryptStrings(projectDir.path);

    final partContent = partFile.readAsStringSync();

    expect(partContent, contains("part of '../user_model.dart';"));
    expect(partContent, contains('$obfStringFuncName("'));
    expect(partContent, isNot(contains("'part runtime'")));
  });
}
