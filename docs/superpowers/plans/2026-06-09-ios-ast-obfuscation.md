# iOS AST Obfuscation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build menu item 10 that scans Flutter `ios` sources, reads Objective-C and Swift through native AST tools, injects safe useless code from language-specific templates, and writes a traceable mapping document.

**Architecture:** Add a focused `lib/ios_noise_obfuscator.dart` module with config parsing, file discovery, AST command execution, insertion target discovery, template rendering, source rewriting, and mapping output. Keep the first version conservative: only inject marked local code inside function or method bodies, skip files when AST/source ranges are ambiguous, and leave all public symbols and existing business statements intact.

**Tech Stack:** Dart 3.2, `dart:io`, `dart:convert`, `path`, `test`, native Xcode tools `xcrun clang` and `xcrun swiftc`.

---

## File Structure

- Create `lib/ios_noise_obfuscator.dart`: iOS config, scanner, AST invoker, insertion planner, template renderer, mapping writer, and public `runIosNoiseObfuscation`.
- Create `test/ios_noise_obfuscator_test.dart`: temp Flutter-like iOS fixtures and behavior tests.
- Modify `bin/obfuscateflutter.dart`: import and menu item 10.
- Modify `obfuscate_dart_noise.json`: add default `iosNoise`.
- Modify `README.md`: document menu item 10 and config.

---

### Task 1: Config And Skip Rules

**Files:**
- Create: `test/ios_noise_obfuscator_test.dart`
- Create: `lib/ios_noise_obfuscator.dart`

- [ ] **Step 1: Write the failing config test**

Add this test file:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/ios_noise_obfuscator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('IosNoiseConfig', () {
    test('loads project config with defaults and template groups', () {
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_cfg_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });

      File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
          .writeAsStringSync(jsonEncode({
        'iosNoise': {
          'enabled': true,
          'targetRatio': 0.25,
          'maxTargetLines': 120,
          'maxInsertionsPerFile': 3,
          'astFallback': 'skip',
          'skipFiles': ['**/Pods/**', '**/GeneratedPluginRegistrant.*'],
          'templateGroups': {
            'objectiveC': ['oc_string_table'],
            'swift': ['swift_string_table'],
          },
          'stringTemplates': [
            {'id': 'trace_context', 'value': 'trace.{{methodName}}.{{index}}'}
          ],
        }
      }));

      final config = IosNoiseConfig.load(projectDir.path);

      expect(config.enabled, isTrue);
      expect(config.targetRatio, 0.25);
      expect(config.maxTargetLines, 120);
      expect(config.maxInsertionsPerFile, 3);
      expect(config.astFallback, 'skip');
      expect(config.objectiveCTemplates, ['oc_string_table']);
      expect(config.swiftTemplates, ['swift_string_table']);
      expect(config.stringTemplates.single.id, 'trace_context');
      expect(config.configSource, 'project');
      expect(config.shouldSkip('ios/Pods/A.m'), isTrue);
      expect(config.shouldSkip('ios/Runner/AppDelegate.m'), isFalse);
    });

    test('rejects invalid iosNoise values', () {
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_cfg_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });

      File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
          .writeAsStringSync(jsonEncode({
        'iosNoise': {'targetRatio': 9}
      }));

      expect(
        () => IosNoiseConfig.load(projectDir.path),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('iosNoise.targetRatio'),
        )),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
dart test test/ios_noise_obfuscator_test.dart
```

Expected: FAIL because `package:obfuscateflutter/ios_noise_obfuscator.dart` does not exist.

- [ ] **Step 3: Implement minimal config code**

Create `lib/ios_noise_obfuscator.dart` with:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:obfuscateflutter/log.dart';
import 'package:path/path.dart' as p;

const _configFileName = 'obfuscate_dart_noise.json';
const _marker = 'obfuscateflutter: ios-noise';
const _defaultObjectiveCTemplates = [
  'oc_string_table',
  'oc_numeric_fold',
  'oc_guarded_branch',
];
const _defaultSwiftTemplates = [
  'swift_string_table',
  'swift_numeric_fold',
  'swift_guarded_branch',
];
const _defaultSkipFiles = [
  '**/Pods/**',
  '**/.symlinks/**',
  '**/Flutter/**',
  '**/GeneratedPluginRegistrant.*',
  '**/build/**',
  '**/*.pbobjc.*',
];
const _defaultStringTemplates = [
  {'id': 'session_word_seed', 'value': 'session.{{word}}.{{seed}}'},
  {'id': 'trace_context', 'value': 'trace.{{fileName}}.{{methodName}}.{{index}}'},
];

class IosNoiseConfig {
  IosNoiseConfig({
    required this.enabled,
    required this.targetRatio,
    required this.maxTargetLines,
    required this.maxInsertionsPerFile,
    required this.astFallback,
    required this.skipFiles,
    required this.objectiveCTemplates,
    required this.swiftTemplates,
    required this.stringTemplates,
    required this.configSource,
  });

  final bool enabled;
  final double targetRatio;
  final int maxTargetLines;
  final int maxInsertionsPerFile;
  final String astFallback;
  final List<String> skipFiles;
  final List<String> objectiveCTemplates;
  final List<String> swiftTemplates;
  final List<IosStringTemplate> stringTemplates;
  final String configSource;

  static IosNoiseConfig load(String projectPath) {
    final file = _resolveConfigFile(projectPath);
    final source = file.existsSync() && p.equals(p.dirname(file.path), p.normalize(projectPath))
        ? 'project'
        : 'tool_default';
    final decoded = file.existsSync() ? jsonDecode(file.readAsStringSync()) : <String, dynamic>{};
    if (decoded is! Map<String, dynamic>) {
      throw StateError('$_configFileName must contain a JSON object.');
    }
    final value = decoded['iosNoise'];
    if (value == null) return _defaults(source);
    if (value is! Map<String, dynamic>) {
      throw StateError('iosNoise must be a JSON object.');
    }
    final ratio = value['targetRatio'] ?? 0.4;
    if (ratio is! num || ratio <= 0 || ratio > 3) {
      throw StateError('iosNoise.targetRatio must be from 0 to 3.');
    }
    final fallback = value['astFallback'] ?? 'skip';
    if (fallback is! String || fallback != 'skip') {
      throw StateError('iosNoise.astFallback only supports skip.');
    }
    final groups = value['templateGroups'];
    final groupJson = groups is Map<String, dynamic> ? groups : <String, dynamic>{};
    return IosNoiseConfig(
      enabled: value['enabled'] != false,
      targetRatio: ratio.toDouble(),
      maxTargetLines: _readOptionalBoundedInt(value, 'maxTargetLines', 20, 500000, 20000),
      maxInsertionsPerFile: _readOptionalBoundedInt(value, 'maxInsertionsPerFile', 1, 200, 20),
      astFallback: fallback,
      skipFiles: _readStringList(value, 'skipFiles', _defaultSkipFiles),
      objectiveCTemplates: _readTemplateIds(groupJson, 'objectiveC', _defaultObjectiveCTemplates),
      swiftTemplates: _readTemplateIds(groupJson, 'swift', _defaultSwiftTemplates),
      stringTemplates: _readStringTemplates(value),
      configSource: source,
    );
  }

  static IosNoiseConfig _defaults(String source) {
    return IosNoiseConfig(
      enabled: true,
      targetRatio: 0.4,
      maxTargetLines: 20000,
      maxInsertionsPerFile: 20,
      astFallback: 'skip',
      skipFiles: List<String>.from(_defaultSkipFiles),
      objectiveCTemplates: List<String>.from(_defaultObjectiveCTemplates),
      swiftTemplates: List<String>.from(_defaultSwiftTemplates),
      stringTemplates: _defaultStringTemplates
          .map((item) => IosStringTemplate(id: item['id']!, value: item['value']!))
          .toList(),
      configSource: source,
    );
  }

  bool shouldSkip(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return skipFiles.any((pattern) => _globMatches(pattern, normalized));
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'targetRatio': targetRatio,
        'maxTargetLines': maxTargetLines,
        'maxInsertionsPerFile': maxInsertionsPerFile,
        'astFallback': astFallback,
        'skipFiles': skipFiles,
        'templateGroups': {
          'objectiveC': objectiveCTemplates,
          'swift': swiftTemplates,
        },
        'stringTemplates': stringTemplates.map((template) => template.toJson()).toList(),
        'configSource': configSource,
      };
}

class IosStringTemplate {
  IosStringTemplate({required this.id, required this.value});

  final String id;
  final String value;

  Map<String, dynamic> toJson() => {'id': id, 'value': value};
}

File _resolveConfigFile(String projectPath) {
  final projectConfig = File(p.join(projectPath, _configFileName));
  if (projectConfig.existsSync()) return projectConfig;
  return File(p.join(Directory.current.path, _configFileName));
}

int _readOptionalBoundedInt(Map<String, dynamic> json, String key, int min, int max, int defaultValue) {
  final value = json[key];
  if (value == null) return defaultValue;
  if (value is! int || value < min || value > max) {
    throw StateError('iosNoise.$key must be from $min to $max.');
  }
  return value;
}

List<String> _readStringList(Map<String, dynamic> json, String key, List<String> defaults) {
  final value = json[key];
  if (value == null) return List<String>.from(defaults);
  if (value is! List || value.any((item) => item is! String || item.trim().isEmpty)) {
    throw StateError('iosNoise.$key must be a non-empty string array.');
  }
  return value.cast<String>();
}

List<String> _readTemplateIds(Map<String, dynamic> json, String key, List<String> defaults) {
  final values = _readStringList(json, key, defaults);
  final known = key == 'objectiveC' ? _defaultObjectiveCTemplates : _defaultSwiftTemplates;
  for (final value in values) {
    if (!known.contains(value)) throw StateError('iosNoise.templateGroups.$key contains unsupported template: $value.');
  }
  return values;
}

List<IosStringTemplate> _readStringTemplates(Map<String, dynamic> json) {
  final value = json['stringTemplates'];
  final defaults = _defaultStringTemplates
      .map((item) => IosStringTemplate(id: item['id']!, value: item['value']!))
      .toList();
  if (value == null) return defaults;
  if (value is! List) throw StateError('iosNoise.stringTemplates must be an array.');
  return value.map((item) {
    if (item is! Map<String, dynamic>) throw StateError('iosNoise.stringTemplates entries must be objects.');
    final id = item['id'];
    final template = item['value'];
    if (id is! String || !_identifierPattern.hasMatch(id)) {
      throw StateError('iosNoise.stringTemplates.id must be an identifier.');
    }
    if (template is! String || template.trim().isEmpty || template.contains('\n')) {
      throw StateError('iosNoise.stringTemplates.value must be a single-line string.');
    }
    return IosStringTemplate(id: id, value: template);
  }).toList();
}

final _identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

bool _globMatches(String pattern, String path) {
  var source = RegExp.escape(pattern.replaceAll('\\', '/'));
  source = source.replaceAll(r'\*\*/', '(?:.*/)?');
  source = source.replaceAll(r'\*\*', '.*');
  source = source.replaceAll(r'\*', '[^/]*');
  return RegExp('^$source\$').hasMatch(path);
}

void runIosNoiseObfuscation(String projectPath) {
  throw UnimplementedError('Task 4 implements runIosNoiseObfuscation.');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
dart test test/ios_noise_obfuscator_test.dart
```

Expected: PASS for the config group.

- [ ] **Step 5: Commit**

```bash
git add lib/ios_noise_obfuscator.dart test/ios_noise_obfuscator_test.dart
git commit -m "feat: add ios noise config"
```

---

### Task 2: Source Discovery And Template Rendering

**Files:**
- Modify: `test/ios_noise_obfuscator_test.dart`
- Modify: `lib/ios_noise_obfuscator.dart`

- [ ] **Step 1: Write failing tests for discovery and templates**

Append these tests to `test/ios_noise_obfuscator_test.dart`:

```dart
  group('iOS source planning', () {
    test('discovers Objective-C and Swift sources while skipping generated paths', () {
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_scan_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });
      Directory(p.join(projectDir.path, 'ios', 'Runner')).createSync(recursive: true);
      Directory(p.join(projectDir.path, 'ios', 'Pods')).createSync(recursive: true);
      File(p.join(projectDir.path, 'ios', 'Runner', 'AppDelegate.m')).writeAsStringSync('@implementation AppDelegate\n@end\n');
      File(p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift')).writeAsStringSync('final class Scene {}\n');
      File(p.join(projectDir.path, 'ios', 'Runner', 'AppDelegate.h')).writeAsStringSync('@interface AppDelegate\n@end\n');
      File(p.join(projectDir.path, 'ios', 'Pods', 'Ignored.m')).writeAsStringSync('@implementation Ignored\n@end\n');

      final config = IosNoiseConfig.load(projectDir.path);
      final files = discoverIosSourceFiles(projectDir.path, config);

      expect(files.map((file) => file.relativePath), [
        'ios/Runner/AppDelegate.h',
        'ios/Runner/AppDelegate.m',
        'ios/Runner/Scene.swift',
      ]);
      expect(files.singleWhere((file) => file.relativePath.endsWith('.h')).injectable, isFalse);
      expect(files.singleWhere((file) => file.relativePath.endsWith('.m')).language, IosLanguage.objectiveC);
      expect(files.singleWhere((file) => file.relativePath.endsWith('.swift')).language, IosLanguage.swift);
    });

    test('renders language-specific marked templates', () {
      final swift = renderIosNoiseTemplate(
        language: IosLanguage.swift,
        templateId: 'swift_string_table',
        fileName: 'Scene.swift',
        methodName: 'viewDidLoad',
        index: 2,
        seed: 17,
        stringTemplate: IosStringTemplate(id: 'trace', value: 'trace.{{fileName}}.{{methodName}}.{{index}}'),
      );
      final objc = renderIosNoiseTemplate(
        language: IosLanguage.objectiveC,
        templateId: 'oc_numeric_fold',
        fileName: 'AppDelegate.m',
        methodName: 'applicationDidFinishLaunching',
        index: 1,
        seed: 23,
        stringTemplate: IosStringTemplate(id: 'trace', value: 'trace.{{fileName}}.{{methodName}}.{{index}}'),
      );

      expect(swift, contains('// obfuscateflutter: ios-noise start swift_string_table'));
      expect(swift, contains('let obfIosText2'));
      expect(swift, contains('trace.Scene.swift.viewDidLoad.2'));
      expect(objc, contains('// obfuscateflutter: ios-noise start oc_numeric_fold'));
      expect(objc, contains('NSInteger obfIosSeed1'));
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
dart test test/ios_noise_obfuscator_test.dart
```

Expected: FAIL because `discoverIosSourceFiles`, `IosLanguage`, and `renderIosNoiseTemplate` are not defined.

- [ ] **Step 3: Implement discovery and renderer**

Add to `lib/ios_noise_obfuscator.dart`:

```dart
enum IosLanguage { objectiveC, objectiveCpp, swift }

class IosSourceFile {
  IosSourceFile({
    required this.file,
    required this.relativePath,
    required this.language,
    required this.injectable,
  });

  final File file;
  final String relativePath;
  final IosLanguage language;
  final bool injectable;
}

List<IosSourceFile> discoverIosSourceFiles(String projectPath, IosNoiseConfig config) {
  final iosDir = Directory(p.join(projectPath, 'ios'));
  if (!iosDir.existsSync()) {
    throw StateError('ios directory not found in $projectPath');
  }
  final files = iosDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) {
        final relative = p.relative(file.path, from: projectPath).replaceAll(p.separator, '/');
        final extension = p.extension(file.path);
        final language = switch (extension) {
          '.m' => IosLanguage.objectiveC,
          '.mm' => IosLanguage.objectiveCpp,
          '.h' => IosLanguage.objectiveC,
          '.swift' => IosLanguage.swift,
          _ => null,
        };
        if (language == null || config.shouldSkip(relative)) return null;
        return IosSourceFile(
          file: file,
          relativePath: relative,
          language: language,
          injectable: extension != '.h',
        );
      })
      .whereType<IosSourceFile>()
      .toList()
    ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return files;
}

String renderIosNoiseTemplate({
  required IosLanguage language,
  required String templateId,
  required String fileName,
  required String methodName,
  required int index,
  required int seed,
  required IosStringTemplate stringTemplate,
}) {
  final text = _renderStringTemplate(
    stringTemplate.value,
    fileName: fileName,
    methodName: methodName,
    index: index,
    seed: seed,
  );
  return switch (templateId) {
    'oc_string_table' => _marked(templateId, '''
      NSString *obfIosText$index = @"$text";
      NSArray *obfIosList$index = @[obfIosText$index, @"${stringTemplate.id}"];
      NSDictionary *obfIosMap$index = @{@\"k\": obfIosText$index, @\"m\": [obfIosList$index firstObject] ?: @\"\"};
      if ([obfIosMap$index count] == 912347) { NSLog(@\"%@\", obfIosMap$index); }
'''),
    'oc_numeric_fold' => _marked(templateId, '''
      NSInteger obfIosSeed$index = $seed;
      obfIosSeed$index = ((obfIosSeed$index << 2) ^ ${seed + index}) & 0x7fffffff;
      if (obfIosSeed$index == -1) { NSLog(@\"%ld\", (long)obfIosSeed$index); }
'''),
    'oc_guarded_branch' => _marked(templateId, '''
      NSInteger obfIosGuard$index = $seed + $index;
      if (obfIosGuard$index >= 0) {
        obfIosGuard$index = (obfIosGuard$index * 31) % 9973;
      } else {
        obfIosGuard$index = 0;
      }
'''),
    'swift_string_table' => _marked(templateId, '''
      let obfIosText$index = "$text"
      let obfIosList$index = [obfIosText$index, "${stringTemplate.id}"]
      let obfIosMap$index = ["k": obfIosText$index, "m": obfIosList$index.first ?? ""]
      if obfIosMap$index.count == 912347 { print(obfIosMap$index) }
'''),
    'swift_numeric_fold' => _marked(templateId, '''
      var obfIosSeed$index = $seed
      obfIosSeed$index = ((obfIosSeed$index << 2) ^ ${seed + index}) & 0x7fffffff
      if obfIosSeed$index == -1 { print(obfIosSeed$index) }
'''),
    'swift_guarded_branch' => _marked(templateId, '''
      var obfIosGuard$index = $seed + $index
      if obfIosGuard$index >= 0 {
        obfIosGuard$index = (obfIosGuard$index * 31) % 9973
      } else {
        obfIosGuard$index = 0
      }
'''),
    _ => throw StateError('Unsupported iOS template: $templateId'),
  };
}

String _marked(String templateId, String body) {
  final normalized = body.trimRight();
  return '''
    // $_marker start $templateId
$normalized
    // $_marker end $templateId
''';
}

String _renderStringTemplate(
  String template, {
  required String fileName,
  required String methodName,
  required int index,
  required int seed,
}) {
  const words = ['signal', 'session', 'profile', 'route', 'cache'];
  return template
      .replaceAll('{{fileName}}', fileName)
      .replaceAll('{{methodName}}', methodName)
      .replaceAll('{{index}}', '$index')
      .replaceAll('{{seed}}', '$seed')
      .replaceAll('{{word}}', words[index % words.length]);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
dart test test/ios_noise_obfuscator_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ios_noise_obfuscator.dart test/ios_noise_obfuscator_test.dart
git commit -m "feat: discover ios sources and render templates"
```

---

### Task 3: AST Invocation And Insertion Targets

**Files:**
- Modify: `test/ios_noise_obfuscator_test.dart`
- Modify: `lib/ios_noise_obfuscator.dart`

- [ ] **Step 1: Write failing AST tests**

Append:

```dart
  group('iOS AST targets', () {
    test('finds Objective-C method body targets through clang AST preflight', () async {
      if (!await iosAstToolsAvailable()) return markTestSkipped('xcrun AST tools are unavailable');
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_ast_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });
      Directory(p.join(projectDir.path, 'ios', 'Runner')).createSync(recursive: true);
      final file = File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.m'));
      file.writeAsStringSync('''
#import <Foundation/Foundation.h>
@interface Worker : NSObject
- (NSInteger)sum:(NSInteger)value;
@end
@implementation Worker
- (NSInteger)sum:(NSInteger)value {
  NSInteger base = value + 1;
  return base;
}
@end
''');

      final result = await readIosAstTargets(IosSourceFile(
        file: file,
        relativePath: 'ios/Runner/Worker.m',
        language: IosLanguage.objectiveC,
        injectable: true,
      ));

      expect(result.command, contains('clang'));
      expect(result.exitCode, 0);
      expect(result.targets, isNotEmpty);
      expect(result.targets.single.methodName, contains('sum'));
      expect(result.targets.single.insertionOffset, greaterThan(0));
    });

    test('finds Swift function body targets through swiftc AST preflight', () async {
      if (!await iosAstToolsAvailable()) return markTestSkipped('xcrun AST tools are unavailable');
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_ast_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });
      Directory(p.join(projectDir.path, 'ios', 'Runner')).createSync(recursive: true);
      final file = File(p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift'));
      file.writeAsStringSync('''
final class SceneWorker {
  func sum(_ value: Int) -> Int {
    let base = value + 1
    return base
  }
}
''');

      final result = await readIosAstTargets(IosSourceFile(
        file: file,
        relativePath: 'ios/Runner/Scene.swift',
        language: IosLanguage.swift,
        injectable: true,
      ));

      expect(result.command, contains('swiftc'));
      expect(result.exitCode, 0);
      expect(result.targets, isNotEmpty);
      expect(result.targets.single.methodName, 'sum');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
dart test test/ios_noise_obfuscator_test.dart
```

Expected: FAIL because AST APIs are not implemented.

- [ ] **Step 3: Implement AST command execution and conservative range finder**

Add:

```dart
class IosAstResult {
  IosAstResult({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.targets,
    required this.warnings,
  });

  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;
  final List<IosInsertionTarget> targets;
  final List<String> warnings;
}

class IosInsertionTarget {
  IosInsertionTarget({
    required this.containerName,
    required this.methodName,
    required this.bodyStartOffset,
    required this.bodyEndOffset,
    required this.insertionOffset,
    required this.isStaticLike,
  });

  final String containerName;
  final String methodName;
  final int bodyStartOffset;
  final int bodyEndOffset;
  final int insertionOffset;
  final bool isStaticLike;
}

Future<bool> iosAstToolsAvailable() async {
  final result = await Process.run('xcrun', ['--find', 'clang']);
  final swift = await Process.run('xcrun', ['--find', 'swiftc']);
  return result.exitCode == 0 && swift.exitCode == 0;
}

Future<IosAstResult> readIosAstTargets(IosSourceFile sourceFile) async {
  final args = switch (sourceFile.language) {
    IosLanguage.objectiveC => ['clang', '-x', 'objective-c', '-fsyntax-only', '-Xclang', '-ast-dump=json', sourceFile.file.path],
    IosLanguage.objectiveCpp => ['clang', '-x', 'objective-c++', '-fsyntax-only', '-Xclang', '-ast-dump=json', sourceFile.file.path],
    IosLanguage.swift => ['swiftc', '-dump-ast', '-parse', sourceFile.file.path],
  };
  final command = 'xcrun ${args.join(' ')}';
  final result = await Process.run('xcrun', args);
  final stdout = result.stdout.toString();
  final stderr = result.stderr.toString();
  final source = sourceFile.file.readAsStringSync();
  final targets = result.exitCode == 0 && !source.contains(_marker)
      ? _findInsertionTargetsFromSource(source, sourceFile.language)
      : <IosInsertionTarget>[];
  return IosAstResult(
    command: command,
    exitCode: result.exitCode,
    stdout: stdout,
    stderr: stderr,
    targets: targets,
    warnings: result.exitCode == 0 ? const [] : [stderr.trim()],
  );
}

List<IosInsertionTarget> _findInsertionTargetsFromSource(String source, IosLanguage language) {
  return switch (language) {
    IosLanguage.objectiveC || IosLanguage.objectiveCpp => _findObjectiveCTargets(source),
    IosLanguage.swift => _findSwiftTargets(source),
  };
}

List<IosInsertionTarget> _findObjectiveCTargets(String source) {
  final targets = <IosInsertionTarget>[];
  final pattern = RegExp(r'^[ \t]*[-+]\s*\([^)]*\)\s*([A-Za-z_][A-Za-z0-9_:]*)[^{;]*\{', multiLine: true);
  for (final match in pattern.allMatches(source)) {
    final openBrace = source.indexOf('{', match.start);
    final closeBrace = _findMatchingBrace(source, openBrace);
    if (closeBrace == -1) continue;
    final name = match.group(1) ?? 'objc_method';
    targets.add(IosInsertionTarget(
      containerName: 'implementation',
      methodName: name.replaceAll(':', ''),
      bodyStartOffset: openBrace,
      bodyEndOffset: closeBrace,
      insertionOffset: openBrace + 1,
      isStaticLike: source.substring(match.start, match.start + 1) == '+',
    ));
  }
  return targets;
}

List<IosInsertionTarget> _findSwiftTargets(String source) {
  final targets = <IosInsertionTarget>[];
  final pattern = RegExp(r'\b(?:func|init)\s+([A-Za-z_][A-Za-z0-9_]*)?[^{=]*\{', multiLine: true);
  for (final match in pattern.allMatches(source)) {
    final openBrace = source.indexOf('{', match.start);
    final closeBrace = _findMatchingBrace(source, openBrace);
    if (closeBrace == -1) continue;
    final name = match.group(1) ?? 'init';
    targets.add(IosInsertionTarget(
      containerName: 'swift',
      methodName: name,
      bodyStartOffset: openBrace,
      bodyEndOffset: closeBrace,
      insertionOffset: openBrace + 1,
      isStaticLike: false,
    ));
  }
  return targets;
}

int _findMatchingBrace(String source, int openOffset) {
  if (openOffset < 0 || openOffset >= source.length || source.codeUnitAt(openOffset) != 123) return -1;
  var depth = 0;
  var inSingleLineComment = false;
  var inBlockComment = false;
  String? quote;
  for (var i = openOffset; i < source.length; i++) {
    final ch = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (inSingleLineComment) {
      if (ch == '\n') inSingleLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (ch == '*' && next == '/') {
        inBlockComment = false;
        i++;
      }
      continue;
    }
    if (quote != null) {
      if (ch == r'\\') {
        i++;
      } else if (ch == quote) {
        quote = null;
      }
      continue;
    }
    if (ch == '/' && next == '/') {
      inSingleLineComment = true;
      i++;
      continue;
    }
    if (ch == '/' && next == '*') {
      inBlockComment = true;
      i++;
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      continue;
    }
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
dart test test/ios_noise_obfuscator_test.dart
```

Expected: PASS or SKIP for AST tests if Xcode tools are unavailable.

- [ ] **Step 5: Commit**

```bash
git add lib/ios_noise_obfuscator.dart test/ios_noise_obfuscator_test.dart
git commit -m "feat: read ios ast targets"
```

---

### Task 4: End-To-End Obfuscation And Mapping

**Files:**
- Modify: `test/ios_noise_obfuscator_test.dart`
- Modify: `lib/ios_noise_obfuscator.dart`

- [ ] **Step 1: Write failing end-to-end tests**

Append:

```dart
  group('runIosNoiseObfuscation', () {
    test('injects Objective-C and Swift code and writes mapping', () async {
      if (!await iosAstToolsAvailable()) return markTestSkipped('xcrun AST tools are unavailable');
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_run_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });
      Directory(p.join(projectDir.path, 'ios', 'Runner')).createSync(recursive: true);
      File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.m')).writeAsStringSync('''
#import <Foundation/Foundation.h>
@interface Worker : NSObject
- (NSInteger)sum:(NSInteger)value;
@end
@implementation Worker
- (NSInteger)sum:(NSInteger)value {
  NSInteger base = value + 1;
  return base;
}
@end
''');
      File(p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift')).writeAsStringSync('''
final class SceneWorker {
  func sum(_ value: Int) -> Int {
    let base = value + 1
    return base
  }
}
''');
      File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.h')).writeAsStringSync('@interface Worker\n@end\n');

      await runIosNoiseObfuscation(projectDir.path);

      final objc = File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.m')).readAsStringSync();
      final swift = File(p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift')).readAsStringSync();
      final header = File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.h')).readAsStringSync();
      expect(objc, contains('obfuscateflutter: ios-noise start oc_'));
      expect(swift, contains('obfuscateflutter: ios-noise start swift_'));
      expect(header, '@interface Worker\n@end\n');

      final mappingFile = projectDir.listSync().whereType<File>().singleWhere(
            (file) => p.basename(file.path).startsWith('ios_noise_mapping_'),
          );
      final mapping = jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
      expect(mapping['files_touched'], contains('ios/Runner/Worker.m'));
      expect(mapping['files_touched'], contains('ios/Runner/Scene.swift'));
      expect(mapping['insertions'], hasLength(greaterThanOrEqualTo(2)));

      await runIosNoiseObfuscation(projectDir.path);
      final secondObjc = File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.m')).readAsStringSync();
      expect(RegExp('obfuscateflutter: ios-noise start').allMatches(secondObjc).length, 1);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
dart test test/ios_noise_obfuscator_test.dart
```

Expected: FAIL because `runIosNoiseObfuscation` is still unimplemented.

- [ ] **Step 3: Implement the runner and mapping**

Replace `runIosNoiseObfuscation` and add helpers:

```dart
Future<void> runIosNoiseObfuscation(String projectPath) async {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) throw StateError('Project directory not found: $projectPath');
  final iosDir = Directory(p.join(projectPath, 'ios'));
  if (!iosDir.existsSync()) throw StateError('ios directory not found in $projectPath');
  final config = IosNoiseConfig.load(projectPath);
  if (!config.enabled) {
    Log.log('iOS noise obfuscation is disabled by config.');
    return;
  }

  final files = discoverIosSourceFiles(projectPath, config);
  final insertions = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  final touched = <String>{};
  final commands = <Map<String, dynamic>>[];
  var addedLines = 0;
  final targetLines = min(
    config.maxTargetLines,
    max(1, (_countProcessableLines(files) * config.targetRatio).round()),
  );

  for (final file in files) {
    if (!file.injectable) {
      skipped.add({'file': file.relativePath, 'reason': 'read_only_header'});
      continue;
    }
    final ast = await readIosAstTargets(file);
    commands.add({
      'file': file.relativePath,
      'command': ast.command,
      'exit_code': ast.exitCode,
      'stderr': ast.stderr.trim(),
    });
    if (ast.exitCode != 0) {
      skipped.add({'file': file.relativePath, 'reason': 'ast_failed', 'stderr': ast.stderr.trim()});
      continue;
    }
    if (ast.targets.isEmpty) {
      skipped.add({'file': file.relativePath, 'reason': 'no_safe_targets'});
      continue;
    }

    final source = file.file.readAsStringSync();
    final replacements = <_Replacement>[];
    var perFile = 0;
    for (final target in ast.targets) {
      if (perFile >= config.maxInsertionsPerFile || addedLines >= targetLines) break;
      if (source.substring(target.bodyStartOffset, target.bodyEndOffset).contains(_marker)) continue;
      final templateIds = file.language == IosLanguage.swift ? config.swiftTemplates : config.objectiveCTemplates;
      final templateId = templateIds[(insertions.length + perFile) % templateIds.length];
      final stringTemplate = config.stringTemplates[insertions.length % config.stringTemplates.length];
      final block = renderIosNoiseTemplate(
        language: file.language,
        templateId: templateId,
        fileName: p.basename(file.relativePath),
        methodName: target.methodName,
        index: insertions.length,
        seed: 1009 + insertions.length * 37,
        stringTemplate: stringTemplate,
      );
      replacements.add(_Replacement(target.insertionOffset, '\n$block'));
      final blockLines = block.split('\n').where((line) => line.trim().isNotEmpty).length;
      addedLines += blockLines;
      perFile++;
      touched.add(file.relativePath);
      insertions.add({
        'file': file.relativePath,
        'language': file.language.name,
        'container': target.containerName,
        'method': target.methodName,
        'template_id': templateId,
        'offset': target.insertionOffset,
        'added_lines': blockLines,
      });
    }
    if (replacements.isNotEmpty) {
      var modified = source;
      replacements.sort((a, b) => b.offset.compareTo(a.offset));
      for (final replacement in replacements) {
        modified = modified.replaceRange(replacement.offset, replacement.offset, replacement.text);
      }
      file.file.writeAsStringSync(modified);
    }
  }

  final mappingPath = p.join(projectPath, 'ios_noise_mapping_${_timestamp()}.json');
  File(mappingPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'generated_at': DateTime.now().toIso8601String(),
    'config': config.toJson(),
    'config_file': config.configSource,
    'ast_commands': commands,
    'files_scanned': files.map((file) => file.relativePath).toList(),
    'files_touched': touched.toList()..sort(),
    'insertions': insertions,
    'skipped': skipped,
    'summary': {
      'files_scanned': files.length,
      'files_touched': touched.length,
      'insertions': insertions.length,
      'added_lines': addedLines,
    },
  }));

  Log.log('iOS noise obfuscation complete.');
  Log.log('Mapping document: $mappingPath');
}

class _Replacement {
  _Replacement(this.offset, this.text);

  final int offset;
  final String text;
}

int _countProcessableLines(List<IosSourceFile> files) {
  var count = 0;
  for (final file in files.where((file) => file.injectable)) {
    count += file.file
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .length;
  }
  return count;
}

String _timestamp() {
  final now = DateTime.now();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${pad(now.month)}${pad(now.day)}_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
dart test test/ios_noise_obfuscator_test.dart
```

Expected: PASS or SKIP for toolchain-dependent tests.

- [ ] **Step 5: Commit**

```bash
git add lib/ios_noise_obfuscator.dart test/ios_noise_obfuscator_test.dart
git commit -m "feat: run ios ast noise obfuscation"
```

---

### Task 5: CLI, Default Config, And README

**Files:**
- Modify: `bin/obfuscateflutter.dart`
- Modify: `obfuscate_dart_noise.json`
- Modify: `README.md`
- Modify: `test/ios_noise_obfuscator_test.dart`

- [ ] **Step 1: Write failing default-config test**

Append:

```dart
  group('default tool config', () {
    test('tool default config exposes iosNoise defaults', () {
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_default_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });

      final config = IosNoiseConfig.load(projectDir.path);

      expect(config.configSource, 'tool_default');
      expect(config.enabled, isTrue);
      expect(config.objectiveCTemplates, contains('oc_string_table'));
      expect(config.swiftTemplates, contains('swift_string_table'));
    });
  });
```

- [ ] **Step 2: Run test to verify current code**

Run:

```bash
dart test test/ios_noise_obfuscator_test.dart
```

Expected: PASS because config already has built-in defaults. Keep the test as regression coverage.

- [ ] **Step 3: Wire CLI menu**

Modify `bin/obfuscateflutter.dart`:

```dart
import 'package:obfuscateflutter/ios_noise_obfuscator.dart';
```

Add menu line:

```text
  10.iOS Object-C/Swift AST 混淆
```

Add switch case:

```dart
    case "10":
      {
        await _runIosNoiseObfuscation(projectPath);
        break;
      }
```

Add helper:

```dart
Future<void> _runIosNoiseObfuscation(String projectPath) async {
  print('do ios ast noise obfuscation');
  await runIosNoiseObfuscation(projectPath);
  print('do ios ast noise obfuscation finished');
}
```

- [ ] **Step 4: Add default config**

Add this top-level JSON section to `obfuscate_dart_noise.json`:

```json
"iosNoise": {
  "enabled": true,
  "targetRatio": 0.4,
  "maxTargetLines": 20000,
  "maxInsertionsPerFile": 20,
  "astFallback": "skip",
  "skipFiles": [
    "**/Pods/**",
    "**/.symlinks/**",
    "**/Flutter/**",
    "**/GeneratedPluginRegistrant.*",
    "**/build/**",
    "**/*.pbobjc.*"
  ],
  "templateGroups": {
    "objectiveC": [
      "oc_string_table",
      "oc_numeric_fold",
      "oc_guarded_branch"
    ],
    "swift": [
      "swift_string_table",
      "swift_numeric_fold",
      "swift_guarded_branch"
    ]
  },
  "stringTemplates": [
    {
      "id": "session_word_seed",
      "value": "session.{{word}}.{{seed}}"
    },
    {
      "id": "trace_context",
      "value": "trace.{{fileName}}.{{methodName}}.{{index}}"
    }
  ]
}
```

- [ ] **Step 5: Update README**

Update the feature list with menu item 10 and add a short iOS section:

```markdown
### 10. iOS Object-C/Swift AST 混淆

该功能使用 `obfuscate_dart_noise.json` 中的 `iosNoise` 配置，扫描 `ios` 目录下的 `.m`、`.mm` 和 `.swift` 文件。Objective-C 通过 `xcrun clang -Xclang -ast-dump=json` 读取 AST，Swift 通过 `xcrun swiftc -dump-ast -parse` 读取 AST。

结果：

- 只在可安全定位的方法或函数体内插入带 marker 的无用代码。
- Objective-C 和 Swift 使用不同模板组。
- 默认跳过 `Pods`、`.symlinks`、`Flutter`、`GeneratedPluginRegistrant.*` 和构建目录。
- 不改类名、方法签名、文件名、公开 API 或业务语句顺序。
- 输出 `ios_noise_mapping_<timestamp>.json`，记录 AST 命令、处理文件、注入点、模板和跳过原因。
```

- [ ] **Step 6: Run formatting and tests**

Run:

```bash
dart format bin/obfuscateflutter.dart lib/ios_noise_obfuscator.dart test/ios_noise_obfuscator_test.dart
dart test test/ios_noise_obfuscator_test.dart
dart test
```

Expected: formatting succeeds and tests pass.

- [ ] **Step 7: Commit**

```bash
git add bin/obfuscateflutter.dart obfuscate_dart_noise.json README.md test/ios_noise_obfuscator_test.dart
git commit -m "feat: wire ios ast obfuscation"
```

---

### Task 6: Final Verification

**Files:**
- No planned edits unless verification reveals a defect.

- [ ] **Step 1: Run static analysis**

Run:

```bash
dart analyze
```

Expected: no new errors.

- [ ] **Step 2: Run full test suite**

Run:

```bash
dart test
```

Expected: all tests pass. Toolchain-dependent iOS AST tests may skip only when `xcrun clang` or `xcrun swiftc` is unavailable.

- [ ] **Step 3: Inspect git status**

Run:

```bash
git status --short
```

Expected: clean worktree.

---

## Self-Review

Spec coverage:

- Menu item 10: Task 5.
- Objective-C and Swift AST command usage: Task 3 and Task 4.
- Safe language-specific template injection: Task 2 and Task 4.
- Headers read-only and generated paths skipped: Task 2 and Task 4.
- Idempotence through markers: Task 4.
- Mapping document: Task 4.
- Tests and docs: Task 5 and Task 6.

Placeholder scan:

- No placeholder markers or undefined later-only APIs remain in the plan.

Type consistency:

- Public APIs introduced in earlier tasks are reused consistently: `IosNoiseConfig`, `IosStringTemplate`, `IosSourceFile`, `IosLanguage`, `IosInsertionTarget`, `IosAstResult`, `discoverIosSourceFiles`, `renderIosNoiseTemplate`, `readIosAstTargets`, `iosAstToolsAvailable`, and `runIosNoiseObfuscation`.
