import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/html_mapping_writer.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:path/path.dart' as p;

const _configFileName = 'obfuscate_dart_noise.json';
const _defaultIncludeExtensions = ['.m', '.h', '.mm', '.swift'];
const _defaultSkipFiles = [
  '**/Pods/**',
  '**/.symlinks/**',
  '**/Flutter/**',
  '**/GeneratedPluginRegistrant.*',
  '**/build/**',
  '**/*.pbobjc.*',
];
const _defaultNameTemplates = ['{Word}{Kind}'];
const _defaultSemanticWords = [
  'Session',
  'Profile',
  'Route',
  'Cache',
  'Account',
  'Message',
  'Media',
  'State',
];
const _defaultKinds = [
  'RouteView',
  'StateBridge',
  'ProfileManager',
  'SessionAdapter',
  'CacheStore',
  'MessageCoordinator',
  'MediaController',
  'AccountPresenter',
];
const _fallbackNameSuffixes = [
  'Module',
  'Bridge',
  'Adapter',
  'Coordinator',
  'Controller',
  'Store',
  'Presenter',
  'Service',
];

typedef IosFileRenameProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class IosFileRenameConfig {
  IosFileRenameConfig({
    required this.enabled,
    required this.includeExtensions,
    required this.skipFiles,
    required this.nameTemplates,
    required this.semanticWords,
    required this.kinds,
    required this.configSource,
  });

  final bool enabled;
  final List<String> includeExtensions;
  final List<String> skipFiles;
  final List<String> nameTemplates;
  final List<String> semanticWords;
  final List<String> kinds;
  final String configSource;

  static IosFileRenameConfig load(String projectPath) {
    final file = _resolveConfigFile(projectPath);
    final source = file.existsSync() &&
            p.equals(p.dirname(file.path), p.normalize(projectPath))
        ? 'project'
        : 'tool_default';
    final decoded = file.existsSync()
        ? jsonDecode(file.readAsStringSync())
        : <String, dynamic>{};
    if (decoded is! Map<String, dynamic>) {
      throw StateError('$_configFileName must contain a JSON object.');
    }

    final value = decoded['iosFileRename'];
    if (value == null) return _defaults(source);
    if (value is! Map<String, dynamic>) {
      throw StateError('iosFileRename must be a JSON object.');
    }
    final enabled = value['enabled'];
    if (enabled != null && enabled is! bool) {
      throw StateError('iosFileRename.enabled must be a boolean.');
    }

    return IosFileRenameConfig(
      enabled: enabled ?? true,
      includeExtensions: _readStringList(
        value,
        'includeExtensions',
        _defaultIncludeExtensions,
      ),
      skipFiles: _readStringList(value, 'skipFiles', _defaultSkipFiles),
      nameTemplates:
          _readStringList(value, 'nameTemplates', _defaultNameTemplates),
      semanticWords:
          _readStringList(value, 'semanticWords', _defaultSemanticWords),
      kinds: _readStringList(value, 'kinds', _defaultKinds),
      configSource: source,
    );
  }

  static IosFileRenameConfig _defaults(String source) {
    return IosFileRenameConfig(
      enabled: true,
      includeExtensions: List<String>.from(_defaultIncludeExtensions),
      skipFiles: List<String>.from(_defaultSkipFiles),
      nameTemplates: List<String>.from(_defaultNameTemplates),
      semanticWords: List<String>.from(_defaultSemanticWords),
      kinds: List<String>.from(_defaultKinds),
      configSource: source,
    );
  }

  bool shouldSkip(String relativePath) {
    final normalized = relativePath.replaceAll(r'\', '/');
    return skipFiles.any((pattern) => _globMatches(pattern, normalized));
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'includeExtensions': includeExtensions,
        'skipFiles': skipFiles,
        'nameTemplates': nameTemplates,
        'semanticWords': semanticWords,
        'kinds': kinds,
        'configSource': configSource,
      };
}

class _RenameGroup {
  _RenameGroup({
    required this.relativeDirectory,
    required this.baseName,
    required this.files,
    required this.isSwift,
  });

  final String relativeDirectory;
  final String baseName;
  final List<File> files;
  final bool isSwift;
}

Future<void> runIosFileRename(
  String projectPath, {
  IosFileRenameProcessRunner processRunner = Process.run,
}) async {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    throw StateError('Project directory not found: $projectPath');
  }
  final iosDir = Directory(p.join(projectPath, 'ios'));
  if (!iosDir.existsSync()) {
    throw StateError('ios directory not found in $projectPath');
  }

  final config = IosFileRenameConfig.load(projectPath);
  if (!config.enabled) {
    Log.log('iOS file rename is disabled by config.');
    return;
  }

  final skipped = <Map<String, dynamic>>[];
  final groups = _discoverRenameGroups(projectPath, config, skipped);
  final fileRenames = _buildFileRenames(projectPath, config, groups, skipped);
  final rewrittenFiles =
      _rewriteIosTextReferences(projectPath, config, fileRenames);
  _moveFiles(projectPath, fileRenames);
  final validation = await _validateRename(
    projectPath: projectPath,
    config: config,
    fileRenames: fileRenames,
    processRunner: processRunner,
  );

  final mapping = {
    'generated_at': DateTime.now().toIso8601String(),
    'config': config.toJson(),
    'config_file': config.configSource,
    'file_renames': fileRenames,
    'skipped': skipped,
    'rewritten_files': rewrittenFiles,
    'validation': validation,
    'summary': {
      'groups_scanned': groups.length,
      'files_renamed': fileRenames.length,
      'files_rewritten': rewrittenFiles.length,
      'skipped': skipped.length,
    },
  };
  final mappingPath = writeHtmlFeatureMapping(
    projectPath: projectPath,
    featureId: 'ios_file_rename',
    featureTitle: 'iOS 项目文件名替换',
    mapping: mapping,
  );

  final staticPassed =
      ((validation['static'] as Map<String, dynamic>)['passed']) == true;
  final xcodebuild = validation['xcodebuild'];
  final xcodePassed = xcodebuild == null ||
      ((xcodebuild as Map<String, dynamic>)['exit_code']) == 0;
  if (!staticPassed || !xcodePassed) {
    throw StateError('iOS file rename validation failed: $mappingPath');
  }

  Log.log('iOS file rename complete.');
  Log.log('Mapping document: $mappingPath');
}

List<_RenameGroup> _discoverRenameGroups(
  String projectPath,
  IosFileRenameConfig config,
  List<Map<String, dynamic>> skipped,
) {
  final iosDir = Directory(p.join(projectPath, 'ios'));
  final objcGroups = <String, List<File>>{};
  final swiftGroups = <_RenameGroup>[];

  final files = iosDir
      .listSync(recursive: true)
      .whereType<File>()
      .where(
          (file) => config.includeExtensions.contains(p.extension(file.path)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final relative = _relative(projectPath, file.path);
    final basename = p.basename(file.path);
    if (config.shouldSkip(relative)) {
      skipped.add({'file': relative, 'reason': 'skip_rule'});
      continue;
    }
    final ext = p.extension(file.path);
    final baseName = p.basenameWithoutExtension(file.path);
    final relativeDir = p.posix.dirname(relative);
    if (_isGeneratedCandidate(config, baseName)) {
      skipped.add({'file': relative, 'reason': 'already_semantic'});
      continue;
    }
    if (basename.startsWith('GeneratedPluginRegistrant.')) {
      skipped.add({'file': relative, 'reason': 'generated_plugin_registrant'});
      continue;
    }
    if (ext == '.swift') {
      swiftGroups.add(_RenameGroup(
        relativeDirectory: relativeDir,
        baseName: baseName,
        files: [file],
        isSwift: true,
      ));
    } else {
      final key = '$relativeDir/$baseName';
      objcGroups.putIfAbsent(key, () => <File>[]).add(file);
    }
  }

  return [
    ...objcGroups.entries.map((entry) {
      final slash = entry.key.lastIndexOf('/');
      return _RenameGroup(
        relativeDirectory: entry.key.substring(0, slash),
        baseName: entry.key.substring(slash + 1),
        files: entry.value,
        isSwift: false,
      );
    }),
    ...swiftGroups,
  ]..sort((a, b) {
      final dir = a.relativeDirectory.compareTo(b.relativeDirectory);
      if (dir != 0) return dir;
      if (a.isSwift != b.isSwift) return a.isSwift ? 1 : -1;
      return a.baseName.compareTo(b.baseName);
    });
}

Map<String, String> _buildFileRenames(
  String projectPath,
  IosFileRenameConfig config,
  List<_RenameGroup> groups,
  List<Map<String, dynamic>> skipped,
) {
  final existingFiles =
      Directory(p.join(projectPath, 'ios')).listSync(recursive: true);
  final usedRelativePaths = existingFiles
      .whereType<File>()
      .map((file) => _relative(projectPath, file.path))
      .toSet();
  final usedBaseNamesByDir = _collectUsedBaseNamesByDir(usedRelativePaths);
  final newBaseNameByOldBaseName = <String, String>{};
  final fileRenames = <String, String>{};
  var index = 0;

  for (final group in groups) {
    final oldRelatives =
        group.files.map((file) => _relative(projectPath, file.path));
    final dirUsed = usedBaseNamesByDir.putIfAbsent(
        group.relativeDirectory, () => <String>{});
    for (final oldRelative in oldRelatives) {
      dirUsed.add(p.basenameWithoutExtension(oldRelative));
    }

    final newBase = newBaseNameByOldBaseName[group.baseName] ??
        _nextUniqueBaseName(
          config,
          group.relativeDirectory,
          dirUsed,
          index++,
        );
    var canRename = true;
    final planned = <String, String>{};
    for (final file in group.files) {
      final oldRelative = _relative(projectPath, file.path);
      final newRelative =
          '${group.relativeDirectory}/$newBase${p.extension(file.path)}';
      if (oldRelative == newRelative) {
        canRename = false;
        break;
      }
      if (usedRelativePaths.contains(newRelative)) {
        canRename = false;
        skipped.add({
          'file': oldRelative,
          'reason': 'target_exists',
          'target': newRelative,
        });
        break;
      }
      planned[oldRelative] = newRelative;
    }
    if (!canRename) continue;
    fileRenames.addAll(planned);
    newBaseNameByOldBaseName[group.baseName] = newBase;
    usedRelativePaths.addAll(planned.values);
    dirUsed.add(newBase);
  }

  return fileRenames;
}

Map<String, Set<String>> _collectUsedBaseNamesByDir(
  Set<String> relativePaths,
) {
  final byDir = <String, Set<String>>{};
  for (final relativePath in relativePaths) {
    final directory = p.posix.dirname(relativePath);
    byDir
        .putIfAbsent(directory, () => <String>{})
        .add(p.posix.basenameWithoutExtension(relativePath));
  }
  return byDir;
}

List<String> _rewriteIosTextReferences(
  String projectPath,
  IosFileRenameConfig config,
  Map<String, String> fileRenames,
) {
  if (fileRenames.isEmpty) return const [];
  final iosDir = Directory(p.join(projectPath, 'ios'));
  final replacementByBasename = {
    for (final entry in fileRenames.entries)
      p.posix.basename(entry.key): p.posix.basename(entry.value),
  };
  final rewritten = <String>[];

  for (final file in iosDir.listSync(recursive: true).whereType<File>()) {
    final relative = _relative(projectPath, file.path);
    if (config.shouldSkip(relative)) continue;
    if (!_isTextFile(file)) continue;
    final source = _readUtf8TextOrNull(file);
    if (source == null) continue;
    var updated = source;
    for (final entry in replacementByBasename.entries) {
      updated = updated.replaceAll(entry.key, entry.value);
    }
    if (updated != source) {
      file.writeAsStringSync(updated);
      rewritten.add(relative);
    }
  }
  rewritten.sort();
  return rewritten;
}

void _moveFiles(String projectPath, Map<String, String> fileRenames) {
  final entries = fileRenames.entries.toList()
    ..sort((a, b) => -a.key.length.compareTo(b.key.length));
  for (final entry in entries) {
    final oldFile = File(p.joinAll([projectPath, ...entry.key.split('/')]));
    final newFile = File(p.joinAll([projectPath, ...entry.value.split('/')]));
    if (!oldFile.existsSync()) continue;
    newFile.parent.createSync(recursive: true);
    oldFile.renameSync(newFile.path);
  }
}

Future<Map<String, dynamic>> _validateRename({
  required String projectPath,
  required IosFileRenameConfig config,
  required Map<String, String> fileRenames,
  required IosFileRenameProcessRunner processRunner,
}) async {
  final staticIssues = <String>[];
  for (final entry in fileRenames.entries) {
    final oldFile = File(p.joinAll([projectPath, ...entry.key.split('/')]));
    final newFile = File(p.joinAll([projectPath, ...entry.value.split('/')]));
    if (oldFile.existsSync()) {
      staticIssues.add('Old file still exists: ${entry.key}');
    }
    if (!newFile.existsSync()) {
      staticIssues.add('New file missing: ${entry.value}');
    }
  }

  final oldBasenames = fileRenames.keys.map(p.posix.basename).toSet();
  final iosDir = Directory(p.join(projectPath, 'ios'));
  for (final file in iosDir.listSync(recursive: true).whereType<File>()) {
    final relative = _relative(projectPath, file.path);
    if (config.shouldSkip(relative)) continue;
    if (!_isTextFile(file)) continue;
    final content = _readUtf8TextOrNull(file);
    if (content == null) continue;
    for (final oldName in oldBasenames) {
      if (content.contains(oldName)) {
        staticIssues.add('$relative still contains $oldName');
      }
    }
  }

  final validation = <String, dynamic>{
    'static': {
      'passed': staticIssues.isEmpty,
      'issues': staticIssues,
    },
  };

  final runnerProject =
      Directory(p.join(projectPath, 'ios', 'Runner.xcodeproj'));
  if (runnerProject.existsSync()) {
    final result = await processRunner('xcodebuild', [
      '-list',
      '-project',
      runnerProject.path,
    ]);
    validation['xcodebuild'] = {
      'command': 'xcodebuild -list -project ${runnerProject.path}',
      'exit_code': result.exitCode,
      'stdout': '${result.stdout}',
      'stderr': '${result.stderr}',
    };
  }
  return validation;
}

String? _readUtf8TextOrNull(File file) {
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

bool _isTextFile(File file) {
  final extension = p.extension(file.path);
  return {
    '.h',
    '.m',
    '.mm',
    '.swift',
    '.pbxproj',
    '.plist',
    '.xcconfig',
  }.contains(extension);
}

String _nextUniqueBaseName(
  IosFileRenameConfig config,
  String relativeDirectory,
  Set<String> usedBaseNames,
  int startIndex,
) {
  var attempt = 0;
  while (attempt < 10000) {
    final value = _renderBaseName(config, startIndex + attempt);
    if (!usedBaseNames.contains(value)) return value;
    attempt++;
  }
  throw StateError(
      'Unable to create unique iOS file name in $relativeDirectory.');
}

String _renderBaseName(IosFileRenameConfig config, int index) {
  final templateCount = config.nameTemplates.length;
  final wordCount = config.semanticWords.length;
  final kindCount = config.kinds.length;
  final directCount =
      [templateCount, wordCount, kindCount].reduce((a, b) => a > b ? a : b);
  if (index < directCount) {
    return _pascalCase(
      config.nameTemplates[index % templateCount]
          .replaceAll('{Word}', config.semanticWords[index % wordCount])
          .replaceAll('{Kind}', config.kinds[index % kindCount]),
    );
  }

  final combinationCount = templateCount * wordCount * kindCount;
  final remainingIndex = index - directCount;
  final combinationIndex = remainingIndex % combinationCount;
  final template = config.nameTemplates[combinationIndex % templateCount];
  final word =
      config.semanticWords[(combinationIndex ~/ templateCount) % wordCount];
  final kind = config
      .kinds[(combinationIndex ~/ (templateCount * wordCount)) % kindCount];
  final baseName = _pascalCase(
    template.replaceAll('{Word}', word).replaceAll('{Kind}', kind),
  );
  final overflowIndex = remainingIndex ~/ combinationCount;
  if (overflowIndex == 0) return baseName;

  final suffix =
      _fallbackNameSuffixes[(overflowIndex - 1) % _fallbackNameSuffixes.length];
  final suffixRound = ((overflowIndex - 1) ~/ _fallbackNameSuffixes.length) + 2;
  return '$baseName$suffix$suffixRound';
}

bool _isGeneratedCandidate(IosFileRenameConfig config, String baseName) {
  if (!_isPascalCase(baseName)) return false;
  return config.semanticWords.any(baseName.startsWith) &&
      config.kinds.any(baseName.contains);
}

bool _isPascalCase(String value) {
  return RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(value);
}

String _pascalCase(String value) {
  final words = RegExp(r'[A-Za-z0-9]+')
      .allMatches(value)
      .map((match) => match.group(0)!)
      .where((word) => word.isNotEmpty)
      .toList();
  return words.map((word) {
    final lower = word.substring(0, 1).toUpperCase() + word.substring(1);
    return lower;
  }).join();
}

List<String> _readStringList(
  Map<String, dynamic> json,
  String key,
  List<String> defaults,
) {
  final value = json[key];
  if (value == null) return List<String>.from(defaults);
  if (value is! List ||
      value.any((item) => item is! String || item.trim().isEmpty)) {
    throw StateError('iosFileRename.$key must be a non-empty string array.');
  }
  if (value.isEmpty) {
    throw StateError('iosFileRename.$key must not be empty.');
  }
  return value.cast<String>();
}

File _resolveConfigFile(String projectPath) {
  final projectConfig = File(p.join(projectPath, _configFileName));
  if (projectConfig.existsSync()) return projectConfig;
  return File(p.join(Directory.current.path, _configFileName));
}

bool _globMatches(String pattern, String path) {
  var source = RegExp.escape(pattern.replaceAll(r'\', '/'));
  source = source.replaceAll(r'\*\*/', '(?:.*/)?');
  source = source.replaceAll(r'\*\*', '.*');
  source = source.replaceAll(r'\*', '[^/]*');
  return RegExp('^$source\$').hasMatch(path);
}

String _relative(String projectPath, String fullPath) {
  return p.relative(fullPath, from: projectPath).replaceAll(p.separator, '/');
}
