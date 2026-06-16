import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/ios_file_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mapping_test_utils.dart';

void main() {
  test('renames iOS source files and rewrites project references', () async {
    final projectDir = _createIosProject();

    await runIosFileRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    final mapping = readHtmlFeatureMapping(projectDir, 'ios_file_rename');
    final fileRenames = (mapping['file_renames'] as Map<String, dynamic>)
        .cast<String, String>();

    expect(fileRenames['ios/Runner/LegacyView.h'],
        'ios/Runner/SessionRouteView.h');
    expect(fileRenames['ios/Runner/LegacyView.m'],
        'ios/Runner/SessionRouteView.m');
    expect(fileRenames['ios/Runner/LegacyView.mm'],
        'ios/Runner/SessionRouteView.mm');
    expect(fileRenames['ios/Runner/LegacyScene.swift'],
        'ios/Runner/ProfileSceneBridge.swift');
    expect(
        mapping['skipped'].toString(), contains('GeneratedPluginRegistrant.m'));
    expect(mapping['validation']['static']['passed'], isTrue);
    expect(mapping['validation']['xcodebuild']['exit_code'], 0);

    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'LegacyView.h'))
            .existsSync(),
        isFalse);
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'LegacyView.m'))
            .existsSync(),
        isFalse);
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'LegacyView.mm'))
            .existsSync(),
        isFalse);
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'LegacyScene.swift'))
            .existsSync(),
        isFalse);
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'SessionRouteView.h'))
            .existsSync(),
        isTrue);
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'SessionRouteView.m'))
            .existsSync(),
        isTrue);
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'SessionRouteView.mm'))
            .existsSync(),
        isTrue);
    expect(
        File(p.join(
                projectDir.path, 'ios', 'Runner', 'ProfileSceneBridge.swift'))
            .existsSync(),
        isTrue);

    final objc =
        File(p.join(projectDir.path, 'ios', 'Runner', 'SessionRouteView.m'))
            .readAsStringSync();
    expect(objc, contains('#import "SessionRouteView.h"'));
    expect(objc, contains('@implementation LegacyView'));
    expect(objc, matches(RegExp(r'LegacyView\s*\*\)\s*view')));
    expect(objc, isNot(contains('LegacyView.h')));

    final swift = File(p.join(
            projectDir.path, 'ios', 'Runner', 'ProfileSceneBridge.swift'))
        .readAsStringSync();
    expect(swift, contains('class LegacyScene'));
    final objcxx =
        File(p.join(projectDir.path, 'ios', 'Runner', 'SessionRouteView.mm'))
            .readAsStringSync();
    expect(objcxx, contains('#include "SessionRouteView.h"'));

    final pbxproj = File(p.join(
      projectDir.path,
      'ios',
      'Runner.xcodeproj',
      'project.pbxproj',
    )).readAsStringSync();
    expect(pbxproj, contains('SessionRouteView.h'));
    expect(pbxproj, contains('SessionRouteView.m'));
    expect(pbxproj, contains('SessionRouteView.mm'));
    expect(pbxproj, contains('ProfileSceneBridge.swift'));
    expect(pbxproj, isNot(contains('LegacyView.h')));
    expect(pbxproj, isNot(contains('LegacyView.m')));
    expect(pbxproj, isNot(contains('LegacyView.mm')));
    expect(pbxproj, isNot(contains('LegacyScene.swift')));

    expect(
      File(p.join(
              projectDir.path, 'ios', 'Runner', 'GeneratedPluginRegistrant.m'))
          .existsSync(),
      isTrue,
    );
    expect(
      File(p.join(projectDir.path, 'ios', 'Runner',
              'GeneratedPluginRegistrant.swift'))
          .existsSync(),
      isTrue,
    );

    await runIosFileRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );
    final secondMapping = readHtmlFeatureMapping(projectDir, 'ios_file_rename');
    expect(secondMapping['file_renames'],
        isNot(contains('ios/Runner/LegacyView.m')));
  });

  test('does nothing when iosFileRename is disabled', () async {
    final projectDir = _createIosProject();
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'iosFileRename': {'enabled': false}
    }));

    await runIosFileRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'LegacyView.m'))
            .existsSync(),
        isTrue);
    expect(
      File(p.join(projectDir.path, 'obfuscation_mapping.html')).existsSync(),
      isFalse,
    );
  });

  test('keeps generating meaningful names after semantic pool is exhausted',
      () async {
    final projectDir = _createMinimalIosProject({
      'iosFileRename': {
        'enabled': true,
        'includeExtensions': ['.m'],
        'nameTemplates': ['{Word}{Kind}'],
        'semanticWords': ['Session'],
        'kinds': ['RouteView'],
      }
    });
    final runnerDir = Directory(p.join(projectDir.path, 'ios', 'Runner'));
    File(p.join(runnerDir.path, 'SessionRouteView.m'))
        .writeAsStringSync('@implementation SessionRouteView\n@end\n');
    File(p.join(runnerDir.path, 'LegacyOnly.m'))
        .writeAsStringSync('@implementation LegacyOnly\n@end\n');
    File(p.join(
      projectDir.path,
      'ios',
      'Runner.xcodeproj',
      'project.pbxproj',
    )).writeAsStringSync(r'''
// !$*UTF8*$!
{
  objects = {
    C1 /* LegacyOnly.m */ = {isa = PBXFileReference; path = LegacyOnly.m; };
    C2 /* SessionRouteView.m */ = {isa = PBXFileReference; path = SessionRouteView.m; };
    D1 /* LegacyOnly.m in Sources */ = {isa = PBXBuildFile; fileRef = C1 /* LegacyOnly.m */; };
  };
}
''');

    await runIosFileRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    final mapping = readHtmlFeatureMapping(projectDir, 'ios_file_rename');
    final fileRenames = (mapping['file_renames'] as Map<String, dynamic>)
        .cast<String, String>();
    final newPath = fileRenames['ios/Runner/LegacyOnly.m']!;

    expect(newPath, isNot('ios/Runner/SessionRouteView.m'));
    expect(
        newPath, matches(RegExp(r'^ios/Runner/SessionRouteView[A-Z].*\.m$')));
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'LegacyOnly.m'))
            .existsSync(),
        isFalse);
    expect(File(p.join(projectDir.path, newPath)).existsSync(), isTrue);
    expect(File(p.join(runnerDir.path, 'SessionRouteView.m')).existsSync(),
        isTrue);
  });

  test('skips third party pods while rewriting and validating references',
      () async {
    final projectDir = _createIosProject();
    final binaryPlist = File(p.join(
      projectDir.path,
      'ios',
      'Pods',
      'AgoraRtcEngine_Special_iOS',
      'AgoraCore.xcframework',
      'ios-arm64_x86_64-simulator',
      'AgoraCore.framework',
      'Info.plist',
    ))
      ..createSync(recursive: true);
    binaryPlist.writeAsBytesSync([0xff, 0xfe, 0x00, 0x01]);

    await runIosFileRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    final mapping = readHtmlFeatureMapping(projectDir, 'ios_file_rename');
    final rewrittenFiles =
        (mapping['rewritten_files'] as List<dynamic>).cast<String>();

    expect(rewrittenFiles, isNot(contains(startsWith('ios/Pods/'))));
    expect(binaryPlist.readAsBytesSync(), [0xff, 0xfe, 0x00, 0x01]);
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'SessionRouteView.m'))
            .existsSync(),
        isTrue);
  });

  test('allows own source files that are not referenced by the xcode project',
      () async {
    final projectDir = _createMinimalIosProject({
      'iosFileRename': {
        'enabled': true,
        'includeExtensions': ['.m'],
        'nameTemplates': ['{Word}{Kind}'],
        'semanticWords': ['Session'],
        'kinds': ['RouteView'],
      }
    });
    final runnerDir = Directory(p.join(projectDir.path, 'ios', 'Runner'));
    File(p.join(runnerDir.path, 'LooseHelper.m'))
        .writeAsStringSync('@implementation LooseHelper\n@end\n');
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

    await runIosFileRename(
      projectDir.path,
      processRunner: _successfulXcodebuild,
    );

    final mapping = readHtmlFeatureMapping(projectDir, 'ios_file_rename');

    expect(mapping['validation']['static']['passed'], isTrue);
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'LooseHelper.m'))
            .existsSync(),
        isFalse);
    expect(
        File(p.join(projectDir.path, 'ios', 'Runner', 'SessionRouteView.m'))
            .existsSync(),
        isTrue);
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

Directory _createIosProject({Map<String, dynamic>? config}) {
  final projectDir = Directory.systemTemp.createTempSync('ios_file_rename_');
  addTearDown(() {
    if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
  });

  File(p.join(projectDir.path, 'obfuscate_dart_noise.json')).writeAsStringSync(
    jsonEncode(config ??
        {
          'iosFileRename': {
            'enabled': true,
            'includeExtensions': ['.m', '.h', '.mm', '.swift'],
            'nameTemplates': ['{Word}{Kind}'],
            'semanticWords': ['Session', 'Profile'],
            'kinds': ['RouteView', 'SceneBridge'],
          }
        }),
  );

  final runnerDir = Directory(p.join(projectDir.path, 'ios', 'Runner'))
    ..createSync(recursive: true);
  Directory(p.join(projectDir.path, 'ios', 'Runner.xcodeproj'))
      .createSync(recursive: true);

  File(p.join(runnerDir.path, 'LegacyView.h')).writeAsStringSync('''
@interface LegacyView : NSObject
@end
''');
  File(p.join(runnerDir.path, 'LegacyView.m')).writeAsStringSync('''
#import "LegacyView.h"

@implementation LegacyView
- (void)bind:(LegacyView *)view {
  NSString *file = @"LegacyView.h";
}
@end
''');
  File(p.join(runnerDir.path, 'LegacyView.mm')).writeAsStringSync('''
#include "LegacyView.h"

void bindLegacyView(LegacyView *view) {}
''');
  File(p.join(runnerDir.path, 'LegacyScene.swift')).writeAsStringSync('''
class LegacyScene {
  let fileName = "LegacyScene.swift"
}
''');
  File(p.join(runnerDir.path, 'GeneratedPluginRegistrant.m'))
      .writeAsStringSync('@implementation GeneratedPluginRegistrant\n@end\n');
  File(p.join(runnerDir.path, 'GeneratedPluginRegistrant.h'))
      .writeAsStringSync('@interface GeneratedPluginRegistrant\n@end\n');
  File(p.join(runnerDir.path, 'GeneratedPluginRegistrant.swift'))
      .writeAsStringSync('final class GeneratedPluginRegistrant {}\n');

  File(p.join(
    projectDir.path,
    'ios',
    'Runner.xcodeproj',
    'project.pbxproj',
  )).writeAsStringSync(r'''
// !$*UTF8*$!
{
  objects = {
    A1 /* LegacyView.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = LegacyView.h; };
    A2 /* LegacyView.m */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; name = LegacyView.m; path = LegacyView.m; };
    A3 /* LegacyView.mm */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.cpp.objcpp; path = LegacyView.mm; };
    A4 /* LegacyScene.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LegacyScene.swift; };
    A5 /* GeneratedPluginRegistrant.m */ = {isa = PBXFileReference; path = GeneratedPluginRegistrant.m; };
    B1 /* LegacyView.m in Sources */ = {isa = PBXBuildFile; fileRef = A2 /* LegacyView.m */; };
    B2 /* LegacyView.mm in Sources */ = {isa = PBXBuildFile; fileRef = A3 /* LegacyView.mm */; };
    B3 /* LegacyScene.swift in Sources */ = {isa = PBXBuildFile; fileRef = A4 /* LegacyScene.swift */; };
  };
}
''');

  return projectDir;
}

Directory _createMinimalIosProject(Map<String, dynamic> config) {
  final projectDir = Directory.systemTemp.createTempSync('ios_file_rename_');
  addTearDown(() {
    if (projectDir.existsSync()) projectDir.deleteSync(recursive: true);
  });

  File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
      .writeAsStringSync(jsonEncode(config));
  Directory(p.join(projectDir.path, 'ios', 'Runner'))
      .createSync(recursive: true);
  Directory(p.join(projectDir.path, 'ios', 'Runner.xcodeproj'))
      .createSync(recursive: true);
  return projectDir;
}
