import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

enum GitStatusResult {
  clean,
  dirty,
  unavailable,
}

typedef GitStatusRunner = Future<GitStatusResult> Function(String projectPath);

class PreflightReport {
  PreflightReport({
    required this.fatalIssues,
    required this.warnings,
  });

  final List<String> fatalIssues;
  final List<String> warnings;

  bool get canContinue => fatalIssues.isEmpty;

  void printToConsole() {
    print('\n========== 预检结果 ==========');
    if (fatalIssues.isEmpty && warnings.isEmpty) {
      print('[OK] 预检通过，未发现阻断项或提示项。');
      print('==============================\n');
      return;
    }

    if (fatalIssues.isNotEmpty) {
      print('[阻断] 以下问题需要先处理：');
      for (final issue in fatalIssues) {
        print('  - $issue');
      }
    }

    if (warnings.isNotEmpty) {
      print('[提示] 以下问题可能影响部分功能：');
      for (final warning in warnings) {
        print('  - $warning');
      }
    }

    if (canContinue) {
      print('[OK] 未发现阻断项，将继续进入任务菜单。');
    } else {
      print('[停止] 预检未通过，已停止执行。');
    }
    print('==============================\n');
  }
}

class PreflightChecker {
  PreflightChecker({
    GitStatusRunner? gitStatusRunner,
  }) : _gitStatusRunner = gitStatusRunner ?? _defaultGitStatusRunner;

  final GitStatusRunner _gitStatusRunner;

  Future<PreflightReport> check(String projectPath) async {
    final fatalIssues = <String>[];
    final warnings = <String>[];
    final projectDir = Directory(projectPath);

    if (!projectDir.existsSync()) {
      return PreflightReport(
        fatalIssues: ['项目目录不存在：$projectPath'],
        warnings: const [],
      );
    }

    final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
    final pubspec = _loadPubspec(pubspecFile, fatalIssues);
    if (pubspec != null) {
      _checkFlutterProject(projectPath, pubspec, fatalIssues);
      _checkAssets(projectPath, pubspec, warnings);
      _checkGeneratedFiles(projectPath, pubspec, warnings);
    }

    await _checkGitStatus(projectPath, fatalIssues, warnings);
    _checkAndroidDirectory(projectPath, fatalIssues);
    _checkIosDirectory(projectPath, fatalIssues);

    return PreflightReport(
      fatalIssues: fatalIssues,
      warnings: warnings,
    );
  }

  YamlMap? _loadPubspec(File pubspecFile, List<String> fatalIssues) {
    if (!pubspecFile.existsSync()) {
      fatalIssues.add('缺少 pubspec.yaml。');
      return null;
    }

    try {
      final yaml = loadYaml(pubspecFile.readAsStringSync());
      if (yaml is YamlMap) {
        return yaml;
      }
      fatalIssues.add('pubspec.yaml 内容不是有效的 YAML Map。');
      return null;
    } on Exception catch (e) {
      fatalIssues.add('pubspec.yaml 解析失败：$e');
      return null;
    }
  }

  void _checkFlutterProject(
    String projectPath,
    YamlMap pubspec,
    List<String> fatalIssues,
  ) {
    final flutter = pubspec['flutter'];
    final libDir = Directory(p.join(projectPath, 'lib'));
    if (flutter is! YamlMap || !libDir.existsSync()) {
      fatalIssues.add('不是 Flutter 项目：需要 pubspec.yaml 包含 flutter 配置并存在 lib 目录。');
    }
  }

  void _checkAssets(
    String projectPath,
    YamlMap pubspec,
    List<String> warnings,
  ) {
    final flutter = pubspec['flutter'];
    if (flutter is! YamlMap) {
      return;
    }

    final assets = flutter['assets'];
    if (assets == null) {
      warnings.add('pubspec.yaml 未配置 flutter assets，图片 MD5 和图片名称混淆功能将没有资源可处理。');
      return;
    }
    if (assets is! YamlList || assets.isEmpty) {
      warnings.add('pubspec.yaml 的 flutter assets 为空或格式不正确。');
      return;
    }

    for (final asset in assets) {
      final assetPath = asset.toString();
      final fullPath = p.join(projectPath, p.joinAll(assetPath.split('/')));
      if (FileSystemEntity.typeSync(fullPath) ==
          FileSystemEntityType.notFound) {
        warnings.add('pubspec.yaml assets 声明的 $assetPath 不存在。');
      }
    }
  }

  Future<void> _checkGitStatus(
    String projectPath,
    List<String> fatalIssues,
    List<String> warnings,
  ) async {
    final status = await _gitStatusRunner(projectPath);
    switch (status) {
      case GitStatusResult.clean:
        return;
      case GitStatusResult.dirty:
        fatalIssues.add('git status 不干净，请先提交、暂存或清理目标项目改动。');
      case GitStatusResult.unavailable:
        warnings.add('无法确认 git status，请确认目标项目是 Git 仓库且 git 命令可用。');
    }
  }

  void _checkGeneratedFiles(
    String projectPath,
    YamlMap pubspec,
    List<String> warnings,
  ) {
    if (!_hasBuildRunner(pubspec)) {
      return;
    }

    final libDir = Directory(p.join(projectPath, 'lib'));
    if (!libDir.existsSync()) {
      return;
    }

    final staleOrMissingFiles = <String>[];
    final partPattern = RegExp(
      r'''part\s+['"]([^'"]+\.(?:g|freezed|gr)\.dart)['"]\s*;''',
    );
    final sourceFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !_isGeneratedDartFile(file.path));

    for (final sourceFile in sourceFiles) {
      final source = sourceFile.readAsStringSync();
      for (final match in partPattern.allMatches(source)) {
        final partPath = match.group(1);
        if (partPath == null) {
          continue;
        }
        final generatedFile = File(p.join(sourceFile.parent.path, partPath));
        if (!generatedFile.existsSync()) {
          staleOrMissingFiles.add(p.relative(
            generatedFile.path,
            from: projectPath,
          ));
          continue;
        }
        final sourceModified = sourceFile.statSync().modified;
        final generatedModified = generatedFile.statSync().modified;
        if (sourceModified.isAfter(generatedModified)) {
          staleOrMissingFiles.add(p.relative(
            generatedFile.path,
            from: projectPath,
          ));
        }
      }
    }

    if (staleOrMissingFiles.isNotEmpty) {
      final preview = staleOrMissingFiles.take(5).join(', ');
      final suffix = staleOrMissingFiles.length > 5
          ? ' 等 ${staleOrMissingFiles.length} 个文件'
          : '';
      warnings.add('检测到生成文件缺失或可能过期，需要先运行 build_runner：$preview$suffix。');
    }
  }

  bool _hasBuildRunner(YamlMap pubspec) {
    return _containsDependency(pubspec['dependencies'], 'build_runner') ||
        _containsDependency(pubspec['dev_dependencies'], 'build_runner');
  }

  bool _containsDependency(Object? dependencies, String dependencyName) {
    return dependencies is YamlMap && dependencies.containsKey(dependencyName);
  }

  bool _isGeneratedDartFile(String filePath) {
    return filePath.endsWith('.g.dart') ||
        filePath.endsWith('.freezed.dart') ||
        filePath.endsWith('.gr.dart');
  }

  void _checkAndroidDirectory(String projectPath, List<String> fatalIssues) {
    final androidDir = Directory(p.join(projectPath, 'android'));
    final androidBuildGradle =
        File(p.join(projectPath, 'android', 'app', 'build.gradle'));
    final androidBuildGradleKts =
        File(p.join(projectPath, 'android', 'app', 'build.gradle.kts'));
    final manifest = File(p.join(
      projectPath,
      'android',
      'app',
      'src',
      'main',
      'AndroidManifest.xml',
    ));
    if (!androidDir.existsSync() ||
        (!androidBuildGradle.existsSync() &&
            !androidBuildGradleKts.existsSync()) ||
        !manifest.existsSync()) {
      fatalIssues.add(
        'Android 目录不完整：需要 android/app/build.gradle(.kts) 和 android/app/src/main/AndroidManifest.xml。',
      );
    }
  }

  void _checkIosDirectory(String projectPath, List<String> fatalIssues) {
    final iosDir = Directory(p.join(projectPath, 'ios'));
    final xcodeProject =
        Directory(p.join(projectPath, 'ios', 'Runner.xcodeproj'));
    final infoPlist = File(p.join(projectPath, 'ios', 'Runner', 'Info.plist'));
    if (!iosDir.existsSync() ||
        !xcodeProject.existsSync() ||
        !infoPlist.existsSync()) {
      fatalIssues.add(
        'iOS 目录不完整：需要 ios/Runner.xcodeproj 和 ios/Runner/Info.plist。',
      );
    }
  }

  static Future<GitStatusResult> _defaultGitStatusRunner(
    String projectPath,
  ) async {
    try {
      final result = await Process.run(
        'git',
        ['status', '--porcelain'],
        workingDirectory: projectPath,
        runInShell: true,
      );
      if (result.exitCode != 0) {
        return GitStatusResult.unavailable;
      }
      return result.stdout.toString().trim().isEmpty
          ? GitStatusResult.clean
          : GitStatusResult.dirty;
    } on Exception {
      return GitStatusResult.unavailable;
    }
  }
}
