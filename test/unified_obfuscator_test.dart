import 'dart:io';

import 'package:obfuscateflutter/unified_obfuscator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mapping_test_utils.dart';

void main() {
  test('unified obfuscation renames files without encrypting strings', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_unified_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
''');

    final libDir = Directory(p.join(projectDir.path, 'lib'))..createSync();
    final homeDir = Directory(p.join(libDir.path, 'features', 'home'))
      ..createSync(recursive: true);
    final sharedDir = Directory(p.join(libDir.path, 'features', 'shared'))
      ..createSync(recursive: true);

    File(p.join(libDir.path, 'main.dart')).writeAsStringSync('''
import 'package:sample_app/features/home/home_page.dart';

String appTitle() => 'visible app title';
String homeTitle() => homeLabel();
''');
    File(p.join(homeDir.path, 'home_page.dart')).writeAsStringSync('''
import '../shared/labels.dart';
import '../../../core/managers/step_tracker.dart';

String homeLabel() => sharedLabel();
''');
    File(p.join(homeDir.path, 'home_page.g.dart')).writeAsStringSync('''
part of 'home_page.dart';
''');
    File(p.join(sharedDir.path, 'labels.dart')).writeAsStringSync('''
String sharedLabel() => 'visible home title';
''');
    final managersDir = Directory(p.join(libDir.path, 'core', 'managers'))
      ..createSync(recursive: true);
    File(p.join(managersDir.path, 'step_tracker.dart')).writeAsStringSync('''
class StepTracker {}
''');

    runUnifiedObfuscation(projectDir.path);

    final keyFile = File(p.join(libDir.path, 'stren_arg.dart'));
    expect(keyFile.existsSync(), isFalse);

    final mainContent =
        File(p.join(libDir.path, 'main.dart')).readAsStringSync();
    expect(mainContent, contains("'visible app title'"));
    expect(mainContent, isNot(contains('des("')));
    expect(mainContent, isNot(contains('stren_arg.dart')));
    expect(mainContent, isNot(contains('features/home/home_page.dart')));

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    final relativeDartPaths = dartFiles
        .map((file) => p.relative(file.path, from: libDir.path))
        .toList();
    expect(relativeDartPaths, isNot(contains('features/home/home_page.dart')));
    expect(relativeDartPaths, isNot(contains('features/shared/labels.dart')));
    expect(relativeDartPaths, contains('main.dart'));
    expect(relativeDartPaths.any((path) => path.endsWith('.g.dart')), isTrue);

    final allSource =
        dartFiles.map((file) => file.readAsStringSync()).join('\n');
    expect(allSource, contains("'visible home title'"));
    expect(allSource, isNot(contains('features/home')));
    expect(allSource, isNot(contains('features/shared')));
    expect(allSource, isNot(contains('../shared/labels.dart')));
    expect(
        allSource, isNot(contains('../../../core/managers/step_tracker.dart')));
    expect(allSource, isNot(contains('core/managers')));
    expect(allSource, contains("part of '"));
    expect(allSource, isNot(contains("part of 'home_page.dart';")));

    final mapping = readHtmlFeatureMapping(projectDir, 'unified_obfuscation');
    expect(mapping, isNot(contains('string_encryption')));
    expect(mapping['file_renames'],
        containsPair('features/home/home_page.dart', anything));
    expect(mapping['file_renames'],
        containsPair('core/managers/step_tracker.dart', anything));
    expect(mapping['directory_renames'], containsPair('features', anything));
    expect(mapping['directory_renames'], containsPair('core', anything));
    expect(
        mapping['directory_renames'], containsPair('core/managers', anything));
    expect(
        mapping['directory_renames'], containsPair('features/home', anything));
    expect(mapping['directory_renames'],
        containsPair('features/shared', anything));
    expect(mapping['summary'], isNot(contains('total_strings_encrypted')));
    expect(mapping['summary'], containsPair('total_dirs_renamed', 5));

    final processedFiles =
        (mapping['processed_files'] as List<dynamic>).cast<Map>();
    expect(processedFiles, isNotEmpty);
    expect(processedFiles.first, isNot(contains('strings_encrypted')));
  });
}
