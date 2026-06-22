import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/ios_structural_diff_obfuscator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('IosStructuralDiffConfig', () {
    test('loads project config with transforms and skip rules', () {
      final projectDir = _createIosProject(config: {
        'iosStructuralDiff': {
          'enabled': true,
          'maxTransformsPerFile': 3,
          'validation': 'static_xcode_list',
          'transforms': ['wrapDispatch', 'extractBlock'],
          'helperNameTemplates': ['obf{Index}{Kind}'],
          'skipFiles': ['**/Pods/**', '**/GeneratedPluginRegistrant.*'],
        }
      });

      final config = IosStructuralDiffConfig.load(projectDir.path);

      expect(config.enabled, isTrue);
      expect(config.maxTransformsPerFile, 3);
      expect(config.validation, 'static_xcode_list');
      expect(config.transforms, ['wrapDispatch', 'extractBlock']);
      expect(config.helperNameTemplates, ['obf{Index}{Kind}']);
      expect(config.configSource, 'project');
      expect(config.shouldSkip('ios/Pods/A.m'), isTrue);
      expect(config.shouldSkip('ios/Runner/AppDelegate.m'), isFalse);
    });

    test('rejects invalid transforms and helper templates', () {
      final invalidTransform = _createIosProject(config: {
        'iosStructuralDiff': {
          'transforms': ['renameEverything'],
        }
      });
      expect(
        () => IosStructuralDiffConfig.load(invalidTransform.path),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('iosStructuralDiff.transforms'),
        )),
      );

      final invalidTemplate = _createIosProject(config: {
        'iosStructuralDiff': {
          'helperNameTemplates': ['123 bad name'],
        }
      });
      expect(
        () => IosStructuralDiffConfig.load(invalidTemplate.path),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('iosStructuralDiff.helperNameTemplates'),
        )),
      );
    });
  });

  group('runIosStructuralDiffObfuscation', () {
    test('rewrites Objective-C and Swift business methods and writes mapping',
        () async {
      final projectDir = _createIosProject(config: {
        'iosStructuralDiff': {
          'enabled': true,
          'maxTransformsPerFile': 3,
          'transforms': ['wrapDispatch', 'extractBlock', 'splitControlFlow'],
          'helperNameTemplates': ['zz{Index}{Kind}'],
        }
      });
      final objcHeader = File(
        p.join(projectDir.path, 'ios', 'Runner', 'Worker.h'),
      )..writeAsStringSync('''
@interface Worker : NSObject
- (NSInteger)publicAction:(NSInteger)value;
@end
''');
      final objcFile = File(
        p.join(projectDir.path, 'ios', 'Runner', 'Worker.m'),
      )..writeAsStringSync('''
#import "Worker.h"

@implementation Worker
- (NSInteger)publicAction:(NSInteger)value {
  NSInteger base = value + 1;
  return base;
}

- (void)privateAction {
  NSInteger first = 1;
  NSInteger second = first + 2;
  NSLog(@"%ld", (long)second);
}

- (void)secondPrivateAction {
  NSInteger count = 4;
  count += 3;
  NSLog(@"%ld", (long)count);
}

- (void)thirdPrivateAction {
  NSInteger total = 7;
  total += 5;
  NSLog(@"%ld", (long)total);
}
@end
''');
      final swiftFile = File(
        p.join(projectDir.path, 'ios', 'Runner', 'Scene.swift'),
      )..writeAsStringSync('''
final class SceneWorker {
  func publicApi(_ value: Int) -> Int {
    let base = value + 1
    return base
  }

  private func buildPayload() {
    let first = 1
    let second = first + 2
    print(second)
  }

  @objc private func exposedToObjc() {
    print("skip")
  }
}
''');

      await runIosStructuralDiffObfuscation(
        projectDir.path,
        processRunner: _successfulXcodebuild,
      );

      final updatedObjc = objcFile.readAsStringSync();
      final updatedSwift = swiftFile.readAsStringSync();
      final mapping = _readOnlyMapping(projectDir);
      final transforms =
          (mapping['transforms_applied'] as List<dynamic>).cast<Map>();

      expect(objcHeader.readAsStringSync(),
          contains('- (NSInteger)publicAction:(NSInteger)value;'));
      expect(updatedObjc, isNot(contains('obfuscateflutter:')));
      expect(updatedObjc, matches(RegExp(r'zz\d+Bridge')));
      expect(updatedObjc, matches(RegExp(r'if \(zz\d+BridgeGuard >= 0\)')));
      expect(updatedSwift, isNot(contains('obfuscateflutter:')));
      expect(updatedSwift, matches(RegExp(r'private func zz\d+Bridge')));
      expect(updatedSwift, contains('@objc private func exposedToObjc()'));
      expect(
        transforms.map((entry) => entry['transform']).toSet(),
        containsAll(['wrapDispatch', 'extractBlock', 'splitControlFlow']),
      );
      expect(mapping['files_touched'], contains('ios/Runner/Worker.m'));
      expect(mapping['files_touched'], contains('ios/Runner/Scene.swift'));
      expect(mapping['validation']['static']['passed'], isTrue);
      expect(mapping['validation']['xcodebuild']['exit_code'], 0);

      final objcBeforeSecondRun = updatedObjc;
      await runIosStructuralDiffObfuscation(
        projectDir.path,
        processRunner: _successfulXcodebuild,
      );
      expect(objcFile.readAsStringSync(), objcBeforeSecondRun);
    });

    test('skips unsafe methods and third party paths', () async {
      final projectDir = _createIosProject();
      File(p.join(projectDir.path, 'ios', 'Runner', 'Unsafe.swift'))
          .writeAsStringSync('''
final class UnsafeWorker {
  public func publicApi() {
    print("skip")
  }

  private func hasAwait() async {
    await Task.yield()
  }
}
''');
      File(p.join(projectDir.path, 'ios', 'Pods', 'ThirdParty', 'Ignored.m'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
@implementation Ignored
- (void)run {
  NSLog(@"skip");
}
@end
''');

      await runIosStructuralDiffObfuscation(
        projectDir.path,
        processRunner: _successfulXcodebuild,
      );

      final mapping = _readOnlyMapping(projectDir);
      final skipped = (mapping['skipped'] as List<dynamic>).cast<Map>();

      expect(mapping['files_touched'], isEmpty);
      expect(
        skipped.map((entry) => entry['reason']).toSet(),
        containsAll(['public_or_exposed_swift', 'unsafe_control_flow']),
      );
      expect(
        mapping['files_scanned'],
        isNot(contains('ios/Pods/ThirdParty/Ignored.m')),
      );
    });

    test('does not rewrite method-like code inside comments', () async {
      final projectDir = _createIosProject(config: {
        'iosStructuralDiff': {
          'helperNameTemplates': ['zz{Index}{Kind}'],
        }
      });
      final sourceFile = File(
        p.join(projectDir.path, 'ios', 'Runner', 'CommentedMethods.m'),
      )..writeAsStringSync('''
@implementation CommentedMethods
- (void)realAction {
  NSInteger value = 1;
  NSLog(@"%ld", (long)value);
}

/*
#pragma mark - Navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
  // Get the new view controller using [segue destinationViewController].
  // Pass the selected object to the new view controller.
}
*/

// - (void)lineCommentedAction {
//   NSLog(@"skip");
// }
@end
''');

      await runIosStructuralDiffObfuscation(
        projectDir.path,
        processRunner: _successfulXcodebuild,
      );

      final updated = sourceFile.readAsStringSync();
      final mapping = _readOnlyMapping(projectDir);
      final transforms =
          (mapping['transforms_applied'] as List<dynamic>).cast<Map>();
      final commentedBlock = RegExp(r'/\*[\s\S]*?\*/').firstMatch(updated)![0]!;

      expect(updated, contains('prepareForSegue:(UIStoryboardSegue *)segue'));
      expect(commentedBlock, isNot(contains('zz')));
      expect(commentedBlock, contains('// Get the new view controller'));
      expect(transforms.map((entry) => entry['method']), ['realAction']);
    });

    test('does nothing when disabled', () async {
      final projectDir = _createIosProject(config: {
        'iosStructuralDiff': {'enabled': false}
      });
      final sourceFile = File(
        p.join(projectDir.path, 'ios', 'Runner', 'Worker.m'),
      )..writeAsStringSync('''
@implementation Worker
- (void)run {
  NSLog(@"run");
}
@end
''');

      await runIosStructuralDiffObfuscation(
        projectDir.path,
        processRunner: _successfulXcodebuild,
      );

      expect(sourceFile.readAsStringSync(), contains('- (void)run'));
      expect(
        projectDir.listSync().whereType<File>().where((file) =>
            p.basename(file.path).startsWith('ios_structural_diff_mapping_')),
        isEmpty,
      );
    });
  });
}

Future<ProcessResult> _successfulXcodebuild(
  String executable,
  List<String> arguments,
) async {
  expect(executable, 'xcodebuild');
  expect(arguments, contains('-list'));
  return ProcessResult(42, 0, 'Information about project "Runner"', '');
}

Map<String, dynamic> _readOnlyMapping(Directory projectDir) {
  final mappingFile = projectDir.listSync().whereType<File>().singleWhere(
        (file) =>
            p.basename(file.path).startsWith('ios_structural_diff_mapping_'),
      );
  return jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
}

Directory _createIosProject({Map<String, dynamic>? config}) {
  final projectDir =
      Directory.systemTemp.createTempSync('ios_structural_diff_');
  addTearDown(() {
    if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
  });

  if (config != null) {
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode(config));
  }
  Directory(p.join(projectDir.path, 'ios', 'Runner'))
      .createSync(recursive: true);
  Directory(p.join(projectDir.path, 'ios', 'Runner.xcodeproj'))
      .createSync(recursive: true);
  File(p.join(
    projectDir.path,
    'ios',
    'Runner.xcodeproj',
    'project.pbxproj',
  )).writeAsStringSync(r'''
// !$*UTF8*$!
{
  objects = {
  };
}
''');
  return projectDir;
}
