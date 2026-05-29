import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:obfuscateflutter/dart_noise_obfuscator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('class inner noise injects reachable members and required imports', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_inner_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
dependencies:
  flutter:
    sdk: flutter
''');
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 1,
      'classCount': 1,
      'methodCountPerClass': 1,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'classInnerNoise': {
        'enabled': true,
        'targetRatio': 0.5,
        'maxTargetLines': 240,
        'maxMembersPerClass': 16,
        'maxHooksPerFile': 8,
        'templateGroups': {
          'executedLightweight': ['sync_hash'],
          'retainedOnly': [
            'async_future',
            'timer_stub',
            'file_io_stub',
            'network_stub',
            'platform_channel_stub',
            'navigator_stub',
            'set_state_stub',
            'run_app_stub',
            'debug_log_stub',
          ],
        },
      },
    }));
    File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
import 'package:flutter/widgets.dart';

void main() {
  runApp(const SampleApp());
}

class SampleApp extends StatelessWidget {
  const SampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }

  String label(String input) {
    return input.trim();
  }
}
''');

    runClassInnerNoiseObfuscation(projectDir.path);

    final source =
        File(p.join(projectDir.path, 'lib', 'main.dart')).readAsStringSync();
    expect(source, contains("import 'dart:async' as obf_async;"));
    expect(source, contains("import 'dart:io' as obf_io;"));
    expect(
      source,
      contains("import 'package:flutter/services.dart' as obf_services;"),
    );
    expect(
      RegExp("import 'package:flutter/widgets.dart';")
          .allMatches(source)
          .length,
      1,
    );
    expect(
      source,
      contains("import 'package:flutter/widgets.dart' as obf_widgets;"),
    );
    expect(source, contains('obf_async.Future<int>'));
    expect(source, contains('obf_async.Timer('));
    expect(source, contains('obf_io.File('));
    expect(source, contains('obf_io.HttpClient'));
    expect(source, contains('obf_services.MethodChannel'));
    expect(source, contains('obf_widgets.Navigator.of'));
    expect(source, contains('setState'));
    expect(source, contains('obf_widgets.runApp'));
    expect(source, contains('obf_widgets.debugPrint'));
    expect(source, contains('obfuscateflutter: class-inner hook'));
    expect(source, contains('final obfNoise'));
    expect(parseString(content: source).errors, isEmpty);

    final mappingFile = projectDir.listSync().whereType<File>().singleWhere(
          (file) =>
              p.basename(file.path).startsWith('class_inner_noise_mapping_'),
        );
    final mapping =
        jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
    expect(mapping['actual_added_lines'], greaterThan(0));
    expect(mapping['imports_added'], contains('dart:async as obf_async'));
    expect(mapping['imports_added'], contains('dart:io as obf_io'));
    expect(
      mapping['imports_added'],
      contains('package:flutter/services.dart as obf_services'),
    );
    expect(mapping['classes_touched'], contains('SampleApp'));
    expect(mapping['templates_used'], contains('timer_stub'));

    runClassInnerNoiseObfuscation(projectDir.path);
    final secondSource =
        File(p.join(projectDir.path, 'lib', 'main.dart')).readAsStringSync();
    expect(
      RegExp('obfuscateflutter: class-inner members')
          .allMatches(secondSource)
          .length,
      1,
    );
  });

  test('class inner noise skips const constructors and expression bodies', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_inner_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
dependencies:
  flutter:
    sdk: flutter
''');
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 1,
      'classCount': 1,
      'methodCountPerClass': 1,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'classInnerNoise': {
        'enabled': true,
        'targetRatio': 1.0,
        'maxTargetLines': 120,
        'templateGroups': {
          'executedLightweight': ['sync_hash'],
          'retainedOnly': ['timer_stub'],
        },
      },
    }));
    File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
class SampleModel {
  const SampleModel(this.value);

  final int value;

  int get doubled => value * 2;

  int compute(int input) {
    return input + value;
  }
}
''');

    runClassInnerNoiseObfuscation(projectDir.path);

    final source =
        File(p.join(projectDir.path, 'lib', 'main.dart')).readAsStringSync();
    expect(source, contains('const SampleModel(this.value);'));
    expect(source, contains('int get doubled => value * 2;'));
    expect(source, contains('int compute(int input) {'));
    expect(source, contains('final obfNoise'));
    expect(parseString(content: source).errors, isEmpty);
  });

  test('class inner noise uses safe seeds in static methods', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_inner_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
dependencies:
  flutter:
    sdk: flutter
''');
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 1,
      'classCount': 1,
      'methodCountPerClass': 1,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'classInnerNoise': {
        'enabled': true,
        'targetRatio': 1.0,
        'maxTargetLines': 120,
        'templateGroups': {
          'executedLightweight': ['sync_hash'],
          'retainedOnly': ['async_future'],
        },
      },
    }));
    File(p.join(projectDir.path, 'lib', 'api_repo.dart')).writeAsStringSync('''
class ApiRepo {
  static Future<String> load(String key) async {
    return key.trim();
  }
}
''');

    runClassInnerNoiseObfuscation(projectDir.path);

    final source = File(p.join(projectDir.path, 'lib', 'api_repo.dart'))
        .readAsStringSync();
    expect(source, isNot(contains('identityHashCode(this)')));
    expect(source, contains("Object.hash('ApiRepo', 'load')"));
    expect(source, contains('final obfNoise'));
    expect(parseString(content: source).errors, isEmpty);
  });

  test('class inner noise prefixes flutter imports to avoid Key conflicts', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_inner_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
dependencies:
  flutter:
    sdk: flutter
''');
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 1,
      'classCount': 1,
      'methodCountPerClass': 1,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'classInnerNoise': {
        'enabled': true,
        'targetRatio': 1.0,
        'maxTargetLines': 160,
        'templateGroups': {
          'executedLightweight': ['sync_hash'],
          'retainedOnly': [
            'platform_channel_stub',
            'navigator_stub',
            'run_app_stub',
          ],
        },
      },
    }));
    File(p.join(projectDir.path, 'lib', 'crypto_util.dart'))
        .writeAsStringSync('''
import 'package:encrypt/encrypt.dart';

class CryptoUtil {
  static final Key key = Key.fromUtf8('1234567890123456');

  static String encode(String value) {
    return value;
  }
}
''');

    runClassInnerNoiseObfuscation(projectDir.path);

    final source = File(p.join(projectDir.path, 'lib', 'crypto_util.dart'))
        .readAsStringSync();
    expect(source,
        contains("import 'package:flutter/widgets.dart' as obf_widgets;"));
    expect(source, isNot(contains("import 'package:flutter/widgets.dart';")));
    expect(source, contains('static final Key key'));
    expect(source, contains('obf_widgets.Widget'));
    expect(source, contains('obf_services.MethodChannel'));
    expect(source, isNot(contains('identityHashCode(this)')));
    expect(parseString(content: source).errors, isEmpty);
  });

  test('class inner noise does not always insert hook as first statement', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_inner_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
dependencies:
  flutter:
    sdk: flutter
''');
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 1,
      'classCount': 1,
      'methodCountPerClass': 1,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'classInnerNoise': {
        'enabled': true,
        'targetRatio': 1.0,
        'maxTargetLines': 160,
        'templateGroups': {
          'executedLightweight': ['sync_hash'],
          'retainedOnly': ['async_future'],
        },
      },
    }));
    File(p.join(projectDir.path, 'lib', 'worker.dart')).writeAsStringSync('''
class Worker {
  int work(int input) {
    final first = input + 1;
    final second = first * 2;
    return second;
  }
}
''');

    runClassInnerNoiseObfuscation(projectDir.path);

    final source =
        File(p.join(projectDir.path, 'lib', 'worker.dart')).readAsStringSync();
    final firstStatement = source.indexOf('final first = input + 1;');
    final hook = source.indexOf('obfuscateflutter: class-inner hook');
    final secondStatement = source.indexOf('final second = first * 2;');
    expect(hook, greaterThan(firstStatement));
    expect(hook, lessThan(secondStatement));
    expect(parseString(content: source).errors, isEmpty);
  });

  test('class inner noise members are inserted among class members', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_inner_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
dependencies:
  flutter:
    sdk: flutter
''');
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 1,
      'classCount': 1,
      'methodCountPerClass': 1,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'classInnerNoise': {
        'enabled': true,
        'targetRatio': 1.0,
        'maxTargetLines': 160,
        'templateGroups': {
          'executedLightweight': ['sync_hash'],
          'retainedOnly': ['async_future'],
        },
      },
    }));
    File(p.join(projectDir.path, 'lib', 'controller.dart'))
        .writeAsStringSync('''
class Controller {
  int first() {
    return 1;
  }

  int middle() {
    return 2;
  }

  int after() {
    return 3;
  }
}
''');

    runClassInnerNoiseObfuscation(projectDir.path);

    final source = File(p.join(projectDir.path, 'lib', 'controller.dart'))
        .readAsStringSync();
    final firstMember = source.indexOf('int first()');
    final noiseMembers =
        source.indexOf('obfuscateflutter: class-inner members');
    final afterMember = source.indexOf('int after()');
    expect(noiseMembers, greaterThan(firstMember));
    expect(noiseMembers, lessThan(afterMember));
    expect(parseString(content: source).errors, isEmpty);
  });

  test('dart noise generation injects sync retain hook and mapping', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_noise_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
''');
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 2,
      'classCount': 2,
      'methodCountPerClass': 3,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
    }));
    File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
import 'package:flutter/material.dart';

void main() {
  runApp(const SampleApp());
}

class SampleApp extends StatelessWidget {
  const SampleApp({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''');

    runDartNoiseObfuscation(projectDir.path);

    final firstMappingFiles = projectDir
        .listSync()
        .whereType<File>()
        .where(
            (file) => p.basename(file.path).startsWith('dart_noise_mapping_'))
        .toList();
    final firstMapping = jsonDecode(firstMappingFiles.single.readAsStringSync())
        as Map<String, dynamic>;
    final generatedFiles =
        (firstMapping['generated_files'] as List<dynamic>).cast<String>();
    final generatedSources = generatedFiles.map((generatedPath) {
      final file = File(p.joinAll([
        projectDir.path,
        ...generatedPath.split('/'),
      ]));
      expect(file.existsSync(), isTrue);
      return file.readAsStringSync();
    }).toList();
    final generatedSource = generatedSources.join('\n');
    expect(generatedSource, contains("import 'package:flutter/widgets.dart';"));
    expect(generatedSource, isNot(contains('@pragma')));
    expect(generatedSource, contains('Object? obfDartNoiseRetain()'));
    expect(generatedSource, contains('StatelessWidget'));
    expect(generatedSource, contains('Object Function()'));
    expect(generatedSource, isNot(contains('Future')));
    expect(generatedSource, isNot(contains('Stream')));
    expect(generatedSource, isNot(contains('async')));
    expect(generatedSource, isNot(contains('await')));
    for (final source in generatedSources) {
      expect(parseString(content: source).errors, isEmpty);
    }

    final mainFile = File(p.join(projectDir.path, 'lib', 'main.dart'));
    final mainSource = mainFile.readAsStringSync();
    expect(
      mainSource,
      contains(
          "import '${(firstMapping['generated_file'] as String).substring('lib/'.length)}';"),
    );
    expect(mainSource, contains('obfDartNoiseRetain();'));
    expect(parseString(content: mainSource).errors, isEmpty);

    runDartNoiseObfuscation(projectDir.path);
    final mainSourceAfterSecondRun = mainFile.readAsStringSync();
    expect(
      RegExp('obfDartNoiseRetain\\(\\);')
          .allMatches(mainSourceAfterSecondRun)
          .length,
      1,
    );
    expect(
      RegExp('obfuscateflutter: dart-noise import')
          .allMatches(mainSourceAfterSecondRun)
          .length,
      1,
    );

    final mappingFiles = projectDir
        .listSync()
        .whereType<File>()
        .where(
            (file) => p.basename(file.path).startsWith('dart_noise_mapping_'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    expect(mappingFiles, isNotEmpty);
    final mapping = jsonDecode(mappingFiles.last.readAsStringSync())
        as Map<String, dynamic>;
    expect(mapping['generated_file'], startsWith('lib/'));
    expect(mapping['generated_files'], isNotEmpty);
    expect(mapping['retain_function'], 'obfDartNoiseRetain');
    expect(mapping['config'], containsPair('pageCount', 2));
    expect(mapping['page_classes'], hasLength(2));
    expect(mapping['dart_classes'], hasLength(2));
    expect(mapping['methods'], hasLength(6));
  });

  test('dart noise generation falls back to tool config file', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_noise_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
void main() {}
''');

    runDartNoiseObfuscation(projectDir.path);

    final mappingFiles = projectDir
        .listSync()
        .whereType<File>()
        .where(
            (file) => p.basename(file.path).startsWith('dart_noise_mapping_'))
        .toList();
    expect(mappingFiles, hasLength(1));
    final mapping = jsonDecode(mappingFiles.single.readAsStringSync())
        as Map<String, dynamic>;
    final generatedFile = File(p.joinAll([
      projectDir.path,
      ...(mapping['generated_file'] as String).split('/'),
    ]));
    expect(generatedFile.existsSync(), isTrue);
    expect(mapping['config_file'], 'tool_default');
    expect(mapping['config'], containsPair('template', 'page_sync_class'));
  });

  test('dart noise generation supports configurable sync snippets', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_noise_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 3,
      'classCount': 3,
      'methodCountPerClass': 4,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'snippets': [
        'widget_layout_page',
        'sync_string',
        'sync_list',
        'sync_model',
        'sync_enum_switch',
      ],
      'snippetWeights': {
        'widget_layout_page': 1,
        'sync_string': 1,
        'sync_list': 1,
        'sync_model': 1,
        'sync_enum_switch': 1,
      },
    }));
    File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
void main() {
}
''');

    runDartNoiseObfuscation(projectDir.path);

    final mappingFiles = projectDir
        .listSync()
        .whereType<File>()
        .where(
            (file) => p.basename(file.path).startsWith('dart_noise_mapping_'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    final mapping = jsonDecode(mappingFiles.last.readAsStringSync())
        as Map<String, dynamic>;
    final generatedFiles =
        (mapping['generated_files'] as List<dynamic>).map((generatedPath) {
      return File(p.joinAll([
        projectDir.path,
        ...(generatedPath as String).split('/'),
      ]));
    }).toList();
    final generatedSource =
        generatedFiles.map((file) => file.readAsStringSync()).join('\n');
    expect(generatedSource, contains('Padding('));
    expect(generatedSource, contains('codeUnits'));
    expect(generatedSource, contains('List<int>.generate'));
    expect(generatedSource, contains('copyWith'));
    expect(generatedSource, contains('switch ('));
    expect(generatedSource, contains('enum '));
    expect(generatedSource, isNot(contains('Future')));
    expect(generatedSource, isNot(contains('Stream')));
    expect(generatedSource, isNot(contains('async')));
    expect(generatedSource, isNot(contains('await')));
    for (final file in generatedFiles) {
      expect(parseString(content: file.readAsStringSync()).errors, isEmpty);
    }

    expect(
        mapping['config'],
        containsPair('snippets', [
          'widget_layout_page',
          'sync_string',
          'sync_list',
          'sync_model',
          'sync_enum_switch',
        ]));
    expect(mapping['config'], contains('snippetWeights'));
    expect(mapping['snippet_usage'], containsPair('sync_string', isPositive));
    expect(mapping['snippet_usage'], containsPair('sync_list', isPositive));
    expect(mapping['snippet_usage'], containsPair('sync_model', isPositive));
    expect(
        mapping['snippet_usage'], containsPair('sync_enum_switch', isPositive));
    expect(mapping['snippet_usage'], containsPair('widget_layout_page', 3));
  });

  test('dart noise generation supports custom json templates', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_noise_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 1,
      'classCount': 1,
      'methodCountPerClass': 1,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'snippets': ['custom_page_shell', 'custom_sync_mix'],
      'customTemplates': {
        'pageBodies': [
          {
            'id': 'custom_page_shell',
            'body': '''
return const DecoratedBox(
  decoration: BoxDecoration(),
  child: SizedBox(width: {{width}}, height: {{height}}),
);
'''
          }
        ],
        'methodBodies': [
          {
            'id': 'custom_sync_mix',
            'body': '''
final mixed = input + seed + {{salt}};
return ((mixed * {{shift}}) ^ seed) & 0x3fffffff;
'''
          }
        ]
      },
    }));
    File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
void main() {
}
''');

    runDartNoiseObfuscation(projectDir.path);

    final mappingFiles = projectDir
        .listSync()
        .whereType<File>()
        .where(
            (file) => p.basename(file.path).startsWith('dart_noise_mapping_'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    final mapping = jsonDecode(mappingFiles.last.readAsStringSync())
        as Map<String, dynamic>;
    final allSource =
        (mapping['generated_files'] as List<dynamic>).map((generatedPath) {
      return File(p.joinAll([
        projectDir.path,
        ...(generatedPath as String).split('/'),
      ])).readAsStringSync();
    }).join('\n');
    expect(allSource, contains('DecoratedBox('));
    expect(allSource, contains('mixed *'));
    expect(allSource, isNot(contains('@pragma')));
    expect(allSource, isNot(contains('Future')));
    expect(allSource, isNot(contains('async')));
    expect(mapping['snippet_usage'],
        containsPair('custom_page_shell', isPositive));
    expect(
        mapping['snippet_usage'], containsPair('custom_sync_mix', isPositive));
  });

  test('dart noise generation scatters configurable random files under lib',
      () {
    final projectDir = Directory.systemTemp.createTempSync('obf_noise_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib', 'feature', 'home'))
        .createSync(recursive: true);
    Directory(p.join(projectDir.path, 'lib', 'core', 'state'))
        .createSync(recursive: true);
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 2,
      'classCount': 2,
      'methodCountPerClass': 2,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'garbageFileCountMin': 7,
      'garbageFileCountMax': 7,
      'snippets': ['widget_empty_page', 'sync_math'],
    }));
    File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
void main() {
}
''');

    runDartNoiseObfuscation(projectDir.path);

    final mappingFiles = projectDir
        .listSync()
        .whereType<File>()
        .where(
            (file) => p.basename(file.path).startsWith('dart_noise_mapping_'))
        .toList();
    final mapping = jsonDecode(mappingFiles.single.readAsStringSync())
        as Map<String, dynamic>;
    final generatedFiles =
        (mapping['generated_files'] as List<dynamic>).cast<String>();
    expect(generatedFiles, hasLength(7));
    expect(
      generatedFiles.any((file) => file.contains('dart_noise')),
      isFalse,
    );
    expect(
      generatedFiles.any((file) {
        final name = p.posix.basename(file);
        return name.startsWith('page_') ||
            name.startsWith('worker_') ||
            name.startsWith('shard_') ||
            name.startsWith('dart_noise');
      }),
      isFalse,
    );

    final generatedDirs =
        generatedFiles.map((file) => p.posix.dirname(file)).toSet();
    expect(generatedDirs.length, greaterThanOrEqualTo(3));
    expect(
      generatedFiles.any((file) => file.startsWith('lib/dart_noise/')),
      isFalse,
    );
    expect(
      generatedFiles.any((file) => file.startsWith('lib/feature/home/')),
      isTrue,
    );
    expect(
      generatedFiles.any((file) => file.startsWith('lib/core/state/')),
      isTrue,
    );
    final filesByDir = <String, List<String>>{};
    for (final generatedFile in generatedFiles) {
      filesByDir
          .putIfAbsent(p.posix.dirname(generatedFile), () => [])
          .add(generatedFile);
    }
    expect(
      filesByDir.values.any((files) {
        if (files.length <= 1) return false;
        final contents = files.map((generatedFile) {
          return File(p.joinAll([
            projectDir.path,
            ...generatedFile.split('/'),
          ])).readAsStringSync();
        }).toList();
        return contents.any((source) => source.contains('StatelessWidget')) &&
            contents.any((source) => source.contains('class NoiseWorker'));
      }),
      isTrue,
    );
    for (final entry in filesByDir.entries) {
      final dir = entry.key;
      final isKnownProjectDir = dir.startsWith('lib/feature/') ||
          dir.startsWith('lib/core/') ||
          dir == 'lib/features' ||
          dir == 'lib/core';
      if (!isKnownProjectDir) {
        expect(entry.value.length, greaterThanOrEqualTo(2));
      }
    }

    for (final generatedFile in generatedFiles) {
      final file = File(p.joinAll([
        projectDir.path,
        ...generatedFile.split('/'),
      ]));
      expect(file.existsSync(), isTrue);
      expect(parseString(content: file.readAsStringSync()).errors, isEmpty);
    }

    final entryPath = mapping['generated_file'] as String;
    expect(entryPath.contains('dart_noise'), isFalse);
    final entrySource = File(p.joinAll([
      projectDir.path,
      ...entryPath.split('/'),
    ])).readAsStringSync();
    expect(entrySource, contains('obfDartNoiseRetain'));
    expect(entrySource, contains('dartNoisePageBridge'));
    expect(entrySource, contains('dartNoiseWorkerBridge'));
    expect(entrySource, contains('checksum ^='));
  });

  test('dart noise generation avoids single-file random directories', () {
    final projectDir = Directory.systemTemp.createTempSync('obf_noise_test_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    Directory(p.join(projectDir.path, 'lib')).createSync(recursive: true);
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 1,
      'classCount': 1,
      'methodCountPerClass': 1,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'garbageFileCountMin': 9,
      'garbageFileCountMax': 9,
      'snippets': ['widget_empty_page', 'sync_math'],
    }));
    File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
void main() {
}
''');

    runDartNoiseObfuscation(projectDir.path);

    final mappingFile = projectDir.listSync().whereType<File>().singleWhere(
        (file) => p.basename(file.path).startsWith('dart_noise_mapping_'));
    final mapping =
        jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
    final generatedFiles =
        (mapping['generated_files'] as List<dynamic>).cast<String>();
    expect(
      generatedFiles.any((file) => file.startsWith('lib/dart_noise/')),
      isFalse,
    );

    final filesByDir = <String, List<String>>{};
    for (final generatedFile in generatedFiles) {
      filesByDir
          .putIfAbsent(p.posix.dirname(generatedFile), () => [])
          .add(generatedFile);
    }
    for (final files in filesByDir.values) {
      expect(files.length, greaterThanOrEqualTo(2));
    }
  });
}
