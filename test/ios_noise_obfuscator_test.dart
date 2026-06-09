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
}
