import 'dart:io';

import 'package:obfuscateflutter/preflight_checker.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PreflightChecker', () {
    test('passes a complete Flutter project with clean git status', () async {
      final projectDir = _createProject();
      addTearDown(() => _delete(projectDir));
      _writeCompleteFlutterProject(
        projectDir,
        assets: '''
flutter:
  uses-material-design: true
  assets:
    - assets/logo.png
''',
      );
      Directory(p.join(projectDir.path, 'assets')).createSync();
      File(p.join(projectDir.path, 'assets', 'logo.png')).writeAsBytesSync([]);

      final result = await PreflightChecker(
        gitStatusRunner: (_) async => GitStatusResult.clean,
      ).check(projectDir.path);

      expect(result.canContinue, isTrue);
      expect(result.fatalIssues, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('blocks non Flutter projects and dirty git status', () async {
      final projectDir = _createProject();
      addTearDown(() => _delete(projectDir));
      File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
''');
      Directory(p.join(projectDir.path, 'lib')).createSync();

      final result = await PreflightChecker(
        gitStatusRunner: (_) async => GitStatusResult.dirty,
      ).check(projectDir.path);

      expect(result.canContinue, isFalse);
      expect(
        result.fatalIssues,
        containsAll([
          contains('不是 Flutter 项目'),
          contains('git status 不干净'),
          contains('Android 目录不完整'),
          contains('iOS 目录不完整'),
        ]),
      );
    });

    test('warns for missing assets and stale generated files', () async {
      final projectDir = _createProject();
      addTearDown(() => _delete(projectDir));
      _writeCompleteFlutterProject(
        projectDir,
        pubspecExtra: '''
dev_dependencies:
  build_runner: ^2.4.0
''',
      );
      File(p.join(projectDir.path, 'lib', 'model.dart')).writeAsStringSync('''
part 'model.g.dart';

class Model {}
''');

      final result = await PreflightChecker(
        gitStatusRunner: (_) async => GitStatusResult.clean,
      ).check(projectDir.path);

      expect(result.canContinue, isTrue);
      expect(
        result.warnings,
        containsAll([
          contains('pubspec.yaml 未配置 flutter assets'),
          contains('需要先运行 build_runner'),
        ]),
      );
    });

    test('warns when declared assets do not exist', () async {
      final projectDir = _createProject();
      addTearDown(() => _delete(projectDir));
      _writeCompleteFlutterProject(
        projectDir,
        assets: '''
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/logo.png
''',
      );
      Directory(p.join(projectDir.path, 'assets', 'images'))
          .createSync(recursive: true);

      final result = await PreflightChecker(
        gitStatusRunner: (_) async => GitStatusResult.clean,
      ).check(projectDir.path);

      expect(result.canContinue, isTrue);
      expect(
        result.warnings,
        contains(contains('assets/logo.png 不存在')),
      );
    });

    test('warns and continues when git status is unavailable', () async {
      final projectDir = _createProject();
      addTearDown(() => _delete(projectDir));
      _writeCompleteFlutterProject(
        projectDir,
        assets: '''
flutter:
  uses-material-design: true
  assets:
    - assets/logo.png
''',
      );
      Directory(p.join(projectDir.path, 'assets')).createSync();
      File(p.join(projectDir.path, 'assets', 'logo.png')).writeAsBytesSync([]);

      final result = await PreflightChecker(
        gitStatusRunner: (_) async => GitStatusResult.unavailable,
      ).check(projectDir.path);

      expect(result.canContinue, isTrue);
      expect(result.fatalIssues, isEmpty);
      expect(
        result.warnings,
        contains(contains('无法确认 git status')),
      );
    });
  });
}

Directory _createProject() =>
    Directory.systemTemp.createTempSync('obf_preflight_test_');

void _delete(Directory directory) {
  if (directory.existsSync()) {
    directory.deleteSync(recursive: true);
  }
}

void _writeCompleteFlutterProject(
  Directory projectDir, {
  String? assets,
  String pubspecExtra = '',
}) {
  File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
${assets ?? '''
flutter:
  uses-material-design: true
'''}$pubspecExtra
''');
  Directory(p.join(projectDir.path, 'lib')).createSync();
  File(p.join(projectDir.path, 'lib', 'main.dart')).writeAsStringSync('''
void main() {}
''');
  Directory(p.join(projectDir.path, 'android', 'app', 'src', 'main'))
      .createSync(recursive: true);
  File(p.join(projectDir.path, 'android', 'app', 'build.gradle'))
      .writeAsStringSync('');
  File(p.join(
    projectDir.path,
    'android',
    'app',
    'src',
    'main',
    'AndroidManifest.xml',
  )).writeAsStringSync('<manifest />');
  Directory(p.join(projectDir.path, 'ios', 'Runner'))
      .createSync(recursive: true);
  Directory(p.join(projectDir.path, 'ios', 'Runner.xcodeproj')).createSync();
  File(p.join(projectDir.path, 'ios', 'Runner', 'Info.plist'))
      .writeAsStringSync('');
}
