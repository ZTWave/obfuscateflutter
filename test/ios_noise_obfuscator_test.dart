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

    test('rejects empty Objective-C template group', () {
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_cfg_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });

      File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
          .writeAsStringSync(jsonEncode({
        'iosNoise': {
          'templateGroups': {'objectiveC': <String>[]}
        }
      }));

      expect(
        () => IosNoiseConfig.load(projectDir.path),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('iosNoise.templateGroups.objectiveC'),
        )),
      );
    });

    test('rejects empty Swift template group', () {
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_cfg_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });

      File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
          .writeAsStringSync(jsonEncode({
        'iosNoise': {
          'templateGroups': {'swift': <String>[]}
        }
      }));

      expect(
        () => IosNoiseConfig.load(projectDir.path),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('iosNoise.templateGroups.swift'),
        )),
      );
    });

    test('rejects empty string templates', () {
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_cfg_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });

      File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
          .writeAsStringSync(jsonEncode({
        'iosNoise': {'stringTemplates': <String>[]}
      }));

      expect(
        () => IosNoiseConfig.load(projectDir.path),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('iosNoise.stringTemplates'),
        )),
      );
    });
  });

  group('iOS source planning', () {
    test(
        'discovers Objective-C and Swift sources while skipping generated paths',
        () {
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_scan_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });
      Directory(p.join(projectDir.path, 'ios', 'Runner'))
          .createSync(recursive: true);
      Directory(p.join(projectDir.path, 'ios', 'Pods'))
          .createSync(recursive: true);
      Directory(p.join(projectDir.path, 'ios', '.symlinks'))
          .createSync(recursive: true);
      Directory(p.join(projectDir.path, 'ios', 'Flutter'))
          .createSync(recursive: true);
      Directory(p.join(projectDir.path, 'ios', 'build'))
          .createSync(recursive: true);
      File(p.join(projectDir.path, 'ios', 'Runner', 'AppDelegate.m'))
          .writeAsStringSync('@implementation AppDelegate\n@end\n');
      File(p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift'))
          .writeAsStringSync('final class Scene {}\n');
      File(p.join(projectDir.path, 'ios', 'Runner', 'AppDelegate.h'))
          .writeAsStringSync('@interface AppDelegate\n@end\n');
      File(p.join(projectDir.path, 'ios', 'Pods', 'Ignored.m'))
          .writeAsStringSync('@implementation Ignored\n@end\n');
      File(p.join(projectDir.path, 'ios', '.symlinks', 'Ignored.m'))
          .writeAsStringSync('@implementation Ignored\n@end\n');
      File(p.join(projectDir.path, 'ios', 'Flutter', 'Ignored.swift'))
          .writeAsStringSync('final class Ignored {}\n');
      File(p.join(projectDir.path, 'ios', 'build', 'Ignored.mm'))
          .writeAsStringSync('@implementation Ignored\n@end\n');
      File(p.join(
        projectDir.path,
        'ios',
        'Runner',
        'GeneratedPluginRegistrant.m',
      )).writeAsStringSync('@implementation GeneratedPluginRegistrant\n@end\n');
      File(p.join(projectDir.path, 'ios', 'Runner', 'Message.pbobjc.m'))
          .writeAsStringSync('@implementation Message\n@end\n');

      final config = IosNoiseConfig.load(projectDir.path);
      final files = discoverIosSourceFiles(projectDir.path, config);

      expect(files.map((file) => file.relativePath), [
        'ios/Runner/AppDelegate.h',
        'ios/Runner/AppDelegate.m',
        'ios/Runner/Scene.swift',
      ]);
      expect(
          files
              .singleWhere((file) => file.relativePath.endsWith('.h'))
              .injectable,
          isFalse);
      expect(
          files
              .singleWhere((file) => file.relativePath.endsWith('.m'))
              .language,
          IosLanguage.objectiveC);
      expect(
          files
              .singleWhere((file) => file.relativePath.endsWith('.swift'))
              .language,
          IosLanguage.swift);
    });

    test('renders language-specific marked templates', () {
      final swift = renderIosNoiseTemplate(
        language: IosLanguage.swift,
        templateId: 'swift_string_table',
        fileName: 'Scene.swift',
        methodName: 'viewDidLoad',
        index: 2,
        seed: 17,
        stringTemplate: IosStringTemplate(
            id: 'trace', value: 'trace.{{fileName}}.{{methodName}}.{{index}}'),
      );
      final objc = renderIosNoiseTemplate(
        language: IosLanguage.objectiveC,
        templateId: 'oc_numeric_fold',
        fileName: 'AppDelegate.m',
        methodName: 'applicationDidFinishLaunching',
        index: 1,
        seed: 23,
        stringTemplate: IosStringTemplate(
            id: 'trace', value: 'trace.{{fileName}}.{{methodName}}.{{index}}'),
      );

      expect(swift,
          contains('// obfuscateflutter: ios-noise start swift_string_table'));
      expect(swift, contains('let obfIosText2'));
      expect(swift, contains('trace.Scene.swift.viewDidLoad.2'));
      expect(objc,
          contains('// obfuscateflutter: ios-noise start oc_numeric_fold'));
      expect(objc, contains('NSInteger obfIosSeed1'));
    });

    test('escapes Swift string literals in rendered templates', () {
      final swift = renderIosNoiseTemplate(
        language: IosLanguage.swift,
        templateId: 'swift_string_table',
        fileName: r'Scene\"Name.swift',
        methodName: 'view"Did\\Load\tCarriage\r',
        index: 4,
        seed: 41,
        stringTemplate: IosStringTemplate(
          id: r'trace\"id',
          value: r'trace "{{fileName}}" \ {{methodName}}',
        ),
      );

      expect(
        swift,
        contains(
          r'let obfIosText4 = "trace \"Scene\\\"Name.swift\" \\ view\"Did\\Load\tCarriage\r"',
        ),
      );
      expect(
          swift, contains(r'let obfIosList4 = [obfIosText4, "trace\\\"id"]'));
    });

    test('escapes Objective-C string literals in rendered templates', () {
      final objc = renderIosNoiseTemplate(
        language: IosLanguage.objectiveC,
        templateId: 'oc_string_table',
        fileName: r'App\"Delegate.m',
        methodName: 'application"Did\\Launch\tCarriage\r',
        index: 5,
        seed: 43,
        stringTemplate: IosStringTemplate(
          id: r'trace\"id',
          value: r'trace "{{fileName}}" \ {{methodName}}',
        ),
      );

      expect(
        objc,
        contains(
          r'NSString *obfIosText5 = @"trace \"App\\\"Delegate.m\" \\ application\"Did\\Launch\tCarriage\r";',
        ),
      );
      expect(objc,
          contains(r'NSArray *obfIosList5 = @[obfIosText5, @"trace\\\"id"];'));
    });

    test('rejects unsupported and language-mismatched templates', () {
      final stringTemplate = IosStringTemplate(
        id: 'trace',
        value: 'trace.{{fileName}}.{{methodName}}.{{index}}',
      );

      expect(
        () => renderIosNoiseTemplate(
          language: IosLanguage.swift,
          templateId: 'oc_numeric_fold',
          fileName: 'Scene.swift',
          methodName: 'viewDidLoad',
          index: 2,
          seed: 17,
          stringTemplate: stringTemplate,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          'Unsupported iOS template: oc_numeric_fold',
        )),
      );
      expect(
        () => renderIosNoiseTemplate(
          language: IosLanguage.objectiveC,
          templateId: 'swift_numeric_fold',
          fileName: 'AppDelegate.m',
          methodName: 'applicationDidFinishLaunching',
          index: 1,
          seed: 23,
          stringTemplate: stringTemplate,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          'Unsupported iOS template: swift_numeric_fold',
        )),
      );
      expect(
        () => renderIosNoiseTemplate(
          language: IosLanguage.swift,
          templateId: 'swift_unknown',
          fileName: 'Scene.swift',
          methodName: 'viewDidLoad',
          index: 3,
          seed: 31,
          stringTemplate: stringTemplate,
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          'Unsupported iOS template: swift_unknown',
        )),
      );
    });
  });

  group('iOS AST targets', () {
    test('reports AST tools unavailable when xcrun cannot be launched',
        () async {
      final available =
          await iosAstToolsAvailableWithRunner((executable, arguments) {
        throw const ProcessException('xcrun', ['--find', 'clang']);
      });

      expect(available, isFalse);
    });

    test('finds Objective-C method body targets through clang AST preflight',
        () async {
      if (!await iosAstToolsAvailable()) {
        return markTestSkipped('xcrun AST tools are unavailable');
      }
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_ast_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });
      Directory(p.join(projectDir.path, 'ios', 'Runner'))
          .createSync(recursive: true);
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

    test('finds Swift function body targets through swiftc AST preflight',
        () async {
      if (!await iosAstToolsAvailable()) {
        return markTestSkipped('xcrun AST tools are unavailable');
      }
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_ast_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });
      Directory(p.join(projectDir.path, 'ios', 'Runner'))
          .createSync(recursive: true);
      final file =
          File(p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift'));
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

    test('finds Swift initializer body targets through swiftc AST preflight',
        () async {
      if (!await iosAstToolsAvailable()) {
        return markTestSkipped('xcrun AST tools are unavailable');
      }
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_ast_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });
      Directory(p.join(projectDir.path, 'ios', 'Runner'))
          .createSync(recursive: true);
      final file =
          File(p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift'));
      file.writeAsStringSync('''
final class SceneWorker {
  let value: Int

  init(value: Int) {
    self.value = value
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
      expect(result.targets.single.methodName, 'init');
    });
  });

  group('runIosNoiseObfuscation', () {
    test('injects Objective-C and Swift code and writes mapping', () async {
      if (!await iosAstToolsAvailable()) {
        return markTestSkipped('xcrun AST tools are unavailable');
      }
      final projectDir = Directory.systemTemp.createTempSync('ios_noise_run_');
      addTearDown(() {
        if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
      });
      Directory(p.join(projectDir.path, 'ios', 'Runner'))
          .createSync(recursive: true);
      File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.m'))
          .writeAsStringSync('''
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
      File(p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift'))
          .writeAsStringSync('''
final class SceneWorker {
  func sum(_ value: Int) -> Int {
    let base = value + 1
    return base
  }
}
''');
      File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.h'))
          .writeAsStringSync('@interface Worker\n@end\n');

      await runIosNoiseObfuscation(projectDir.path);

      final objc = File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.m'))
          .readAsStringSync();
      final swift =
          File(p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift'))
              .readAsStringSync();
      final header = File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.h'))
          .readAsStringSync();
      expect(objc, contains('obfuscateflutter: ios-noise start oc_'));
      expect(swift, contains('obfuscateflutter: ios-noise start swift_'));
      expect(header, '@interface Worker\n@end\n');

      final mappingFile = projectDir.listSync().whereType<File>().singleWhere(
            (file) => p.basename(file.path).startsWith('ios_noise_mapping_'),
          );
      final mapping =
          jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
      expect(mapping['files_touched'], contains('ios/Runner/Worker.m'));
      expect(mapping['files_touched'], contains('ios/Runner/Scene.swift'));
      expect(mapping['insertions'], hasLength(greaterThanOrEqualTo(2)));

      await runIosNoiseObfuscation(projectDir.path);
      final secondObjc =
          File(p.join(projectDir.path, 'ios', 'Runner', 'Worker.m'))
              .readAsStringSync();
      expect(
        RegExp('obfuscateflutter: ios-noise start')
            .allMatches(secondObjc)
            .length,
        1,
      );
    });
  });
}
