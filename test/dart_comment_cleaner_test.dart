import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:obfuscateflutter/dart_comment_cleaner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mapping_test_utils.dart';

void main() {
  late Directory projectDir;

  setUp(() {
    projectDir = Directory.systemTemp.createTempSync('dart_comment_cleaner_');
    Directory(p.join(projectDir.path, 'lib')).createSync();
  });

  tearDown(() {
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }
  });

  test('removes every comment kind and preserves comment-like strings', () {
    final file = File(p.join(projectDir.path, 'lib', 'main.dart'))
      ..writeAsStringSync(r'''
/// Library docs.
void main() {
  // line
  final url = 'https://example.com/a//b';
  final raw = r'/* raw */';
  final triple = """// text
/* text */""";
  print(url); /* block */
  print(raw); /** docs */
  print(triple);
}
''');

    final result = cleanDartComments(projectDir.path);
    final updated = file.readAsStringSync();

    expect(result.scannedFiles, 1);
    expect(result.modifiedFiles, 1);
    expect(result.removedComments, 4);
    expect(result.failedFiles, isEmpty);
    expect(updated, isNot(contains('Library docs')));
    expect(updated, contains("'https://example.com/a//b'"));
    expect(updated, contains("r'/* raw */'"));
    expect(updated, contains('"""// text\n/* text */"""'));
    expect(parseString(content: updated).errors, isEmpty);
  });

  test('keeps token boundaries valid when an inline comment is removed', () {
    final file = File(p.join(projectDir.path, 'lib', 'main.dart'))
      ..writeAsStringSync('''
void main() {
  final value = 1/* separator */is int;
  print(value);
}
''');

    cleanDartComments(projectDir.path);
    final updated = file.readAsStringSync();

    expect(updated, contains('1 is int'));
    expect(parseString(content: updated).errors, isEmpty);
  });

  test('processes generated files under lib and ignores files outside lib', () {
    final generated = File(p.join(projectDir.path, 'lib', 'model.g.dart'))
      ..writeAsStringSync('const value = 1; // generated\n');
    final outside = File(p.join(projectDir.path, 'tool.dart'))
      ..writeAsStringSync('const value = 1; // outside\n');

    final result = cleanDartComments(projectDir.path);

    expect(generated.readAsStringSync(), isNot(contains('generated')));
    expect(outside.readAsStringSync(), contains('// outside'));
    expect(result.scannedFiles, 1);
    expect(result.removedComments, 1);
  });

  test('preserves line breaks from multiline block comments', () {
    const source = 'void main() {\r\n'
        '  final value = 1; /* first\r\nsecond\nthird */\r\n'
        '  print(value);\r\n'
        '}\r\n';
    final file = File(p.join(projectDir.path, 'lib', 'main.dart'))
      ..writeAsStringSync(source);

    cleanDartComments(projectDir.path);
    final updated = file.readAsStringSync();

    expect(updated, isNot(contains('first')));
    expect(
      '\r\n'.allMatches(updated).length,
      '\r\n'.allMatches(source).length,
    );
    expect('\n'.allMatches(updated).length, '\n'.allMatches(source).length);
    expect(parseString(content: updated).errors, isEmpty);
  });

  test('is idempotent and does not rewrite a comment-free file', () {
    final file = File(p.join(projectDir.path, 'lib', 'main.dart'))
      ..writeAsStringSync('void main() {} // remove\n');

    cleanDartComments(projectDir.path);
    final firstContent = file.readAsStringSync();
    final firstModified = file.lastModifiedSync();
    sleep(const Duration(milliseconds: 20));
    final second = cleanDartComments(projectDir.path);

    expect(file.readAsStringSync(), firstContent);
    expect(file.lastModifiedSync(), firstModified);
    expect(second.modifiedFiles, 0);
    expect(second.removedComments, 0);
  });

  test('continues after an unreadable source and writes mapping statistics',
      () {
    final good = File(p.join(projectDir.path, 'lib', 'good.dart'))
      ..writeAsStringSync('const good = true; // remove\n');
    File(p.join(projectDir.path, 'lib', 'bad.dart')).writeAsBytesSync([0xFF]);

    final result = cleanDartComments(projectDir.path);
    final mapping = readHtmlFeatureMapping(projectDir, 'dart_comment_cleanup');

    expect(good.readAsStringSync(), isNot(contains('remove')));
    expect(result.failedFiles, hasLength(1));
    expect(result.failedFiles.single.path, 'lib/bad.dart');
    expect(mapping['scanned_files'], 2);
    expect(mapping['modified_files'], 1);
    expect(mapping['removed_comments'], 1);
    expect(mapping['failed_files'], hasLength(1));
  });

  test('throws when the target project has no lib directory', () {
    projectDir.deleteSync(recursive: true);
    projectDir = Directory.systemTemp.createTempSync('dart_comment_cleaner_');

    expect(
      () => cleanDartComments(projectDir.path),
      throwsA(isA<StateError>()),
    );
  });
}
