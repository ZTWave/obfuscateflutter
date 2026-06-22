import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/ios_function_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mapping_test_utils.dart';

void main() {
  test('renames safe ObjC static functions and private selectors', () async {
    final projectDir = _createIosProject();
    final sourceFile = File(p.join(
      projectDir.path,
      'ios',
      'Runner',
      'LegacyHelper.m',
    ))
      ..writeAsStringSync('''
static int legacyAdd(int left, int right) {
  return left + right;
}

static NSString *legacyTitle(void) {
  return @"title";
}

void exposedGlobal(void) {
  legacyAdd(1, 2);
}

@implementation LegacyHelper
- (void)legacyAdd {
  legacyTitle();
}
@end
''');

    await runIosFunctionRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    final mapping = _readOnlyMapping(projectDir);
    final renames = (mapping['function_renames'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      renames.map((entry) => entry['old_name']),
      containsAll(['legacyAdd', 'legacyTitle']),
    );

    final updated = sourceFile.readAsStringSync();
    expect(updated, isNot(matches(RegExp(r'\blegacyAdd\s*\('))));
    expect(updated, isNot(matches(RegExp(r'\blegacyTitle\s*\('))));
    expect(updated, isNot(contains('- (void)legacyAdd')));
    expect(updated, contains('void exposedGlobal(void)'));
    expect(mapping['validation']['static']['passed'], isTrue);
  });

  test('renames Swift private functions and skips objc exposed functions',
      () async {
    final projectDir = _createIosProject();
    final sourceFile = File(p.join(
      projectDir.path,
      'ios',
      'Runner',
      'LegacyScene.swift',
    ))
      ..writeAsStringSync('''
final class LegacyScene {
  private func buildPayload(_ count: Int) -> Int {
    return count + 1
  }

  fileprivate static func syncCache() {
    _ = buildPayload(3)
  }

  @objc private func exposedToObjc() {
  }

  func publicApi() {
    _ = buildPayload(1)
    Self.syncCache()
    exposedToObjc()
  }
}
''');

    await runIosFunctionRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    final mapping = _readOnlyMapping(projectDir);
    final renames = (mapping['function_renames'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      renames.map((entry) => entry['old_name']),
      containsAll(['buildPayload', 'syncCache']),
    );

    final updated = sourceFile.readAsStringSync();
    expect(updated, isNot(matches(RegExp(r'\bbuildPayload\s*\('))));
    expect(updated, isNot(matches(RegExp(r'\bsyncCache\s*\('))));
    expect(updated, contains('@objc private func exposedToObjc()'));
    expect(updated, contains('func publicApi()'));
    expect(mapping['validation']['static']['passed'], isTrue);
  });

  test('skips third party pods while renaming functions', () async {
    final projectDir = _createIosProject();
    File(p.join(projectDir.path, 'ios', 'Runner', 'LegacyHelper.m'))
        .writeAsStringSync('''
static void legacyRun(void) {
}

void caller(void) {
  legacyRun();
}
''');
    final binaryPlist = File(p.join(
      projectDir.path,
      'ios',
      'Pods',
      'ThirdParty',
      'Binary.framework',
      'Info.plist',
    ))
      ..createSync(recursive: true);
    binaryPlist.writeAsBytesSync([0xff, 0xfe, 0x00, 0x01]);

    await runIosFunctionRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    final mapping = _readOnlyMapping(projectDir);
    final rewrittenFiles =
        (mapping['rewritten_files'] as List<dynamic>).cast<String>();
    expect(rewrittenFiles, isNot(contains(startsWith('ios/Pods/'))));
    expect(binaryPlist.readAsBytesSync(), [0xff, 0xfe, 0x00, 0x01]);
  });

  test('renames private ObjC selectors and updates internal calls', () async {
    final projectDir = _createIosProject();
    final headerFile = File(p.join(
      projectDir.path,
      'ios',
      'Runner',
      'LegacyController.h',
    ))
      ..writeAsStringSync('''
@interface LegacyController : NSObject
- (void)publicAction;
@end
''');
    final sourceFile = File(p.join(
      projectDir.path,
      'ios',
      'Runner',
      'LegacyController.m',
    ))
      ..writeAsStringSync('''
#import "LegacyController.h"

@interface LegacyController ()
- (void)privateAction;
- (NSInteger)privateValue:(NSInteger)value context:(NSString *)context;
@end

@implementation LegacyController
- (void)viewDidLoad {
  [self privateAction];
  [self privateValue:1 context:@"x"];
}

- (void)publicAction {
  [self privateAction];
}

- (void)privateAction {
}

- (NSInteger)privateValue:(NSInteger)value context:(NSString *)context {
  return value;
}
@end
''');

    await runIosFunctionRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    final mapping = _readOnlyMapping(projectDir);
    final renames = (mapping['function_renames'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final renamedSelectors = renames
        .where((entry) => entry['kind'] == 'objc_private_method')
        .map((entry) => entry['old_name'])
        .toSet();

    expect(renamedSelectors,
        containsAll(['privateAction', 'privateValue:context:']));
    expect(renamedSelectors, isNot(contains('publicAction')));
    expect(renamedSelectors, isNot(contains('viewDidLoad')));

    final updatedHeader = headerFile.readAsStringSync();
    expect(updatedHeader, contains('- (void)publicAction;'));

    final updatedSource = sourceFile.readAsStringSync();
    expect(updatedSource, isNot(contains('privateAction')));
    expect(updatedSource, isNot(contains('privateValue:')));
    expect(updatedSource, contains('- (void)viewDidLoad'));
    expect(updatedSource, contains('- (void)publicAction'));
    expect(mapping['validation']['static']['passed'], isTrue);
  });

  test('does nothing when iosFunctionRename is disabled', () async {
    final projectDir = _createIosProject(config: {
      'iosFunctionRename': {'enabled': false}
    });
    final sourceFile = File(p.join(
      projectDir.path,
      'ios',
      'Runner',
      'LegacyHelper.m',
    ))
      ..writeAsStringSync('''
static void legacyRun(void) {
}
''');

    await runIosFunctionRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    expect(sourceFile.readAsStringSync(), contains('legacyRun'));
    expect(
      File(p.join(projectDir.path, 'obfuscation_mapping.html')).existsSync(),
      isFalse,
    );
  });

  test('generates unique names when template word pools are exhausted',
      () async {
    final projectDir = _createIosProject(config: {
      'iosFunctionRename': {
        'enabled': true,
        'includeExtensions': ['.m'],
        'nameTemplates': ['handle{Word}{Kind}'],
        'semanticWords': ['Session'],
        'kinds': ['State'],
      }
    });
    final sourceFile = File(p.join(
      projectDir.path,
      'ios',
      'Runner',
      'ManyHelpers.m',
    ));
    final buffer = StringBuffer();
    for (var i = 0; i < 12; i++) {
      buffer
        ..writeln('static int legacyHelper$i(int value) {')
        ..writeln('  return value + $i;')
        ..writeln('}')
        ..writeln();
    }
    buffer.writeln('int callAllHelpers(void) {');
    for (var i = 0; i < 12; i++) {
      buffer.writeln('  legacyHelper$i($i);');
    }
    buffer
      ..writeln('  return 0;')
      ..writeln('}');
    sourceFile.writeAsStringSync(buffer.toString());

    await runIosFunctionRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    final mapping = _readOnlyMapping(projectDir);
    final renames = (mapping['function_renames'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final newNames = renames.map((entry) => entry['new_name']).toSet();

    expect(renames, hasLength(12));
    expect(newNames, hasLength(12));
    expect(newNames, contains('handleSessionState'));
    expect(newNames, contains('handleSessionState1'));
    expect(sourceFile.readAsStringSync(), isNot(contains('legacyHelper')));
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
  return readHtmlFeatureMapping(projectDir, 'ios_function_rename');
}

Directory _createIosProject({Map<String, dynamic>? config}) {
  final projectDir =
      Directory.systemTemp.createTempSync('ios_function_rename_');
  addTearDown(() {
    if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
  });

  File(p.join(projectDir.path, 'obfuscate_dart_noise.json')).writeAsStringSync(
    jsonEncode(config ??
        {
          'iosFunctionRename': {
            'enabled': true,
            'includeExtensions': ['.m', '.mm', '.swift'],
            'nameTemplates': [
              'handle{Word}{Kind}',
              'sync{Word}{Kind}',
              'prepare{Word}{Kind}',
            ],
            'semanticWords': ['Session', 'Profile', 'Route'],
            'kinds': ['State', 'Payload', 'Context'],
          }
        }),
  );

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
