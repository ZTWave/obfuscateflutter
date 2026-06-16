import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/html_mapping_writer.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:path/path.dart' as p;

const _configFileName = 'obfuscate_dart_noise.json';
const _defaultIncludeExtensions = ['.m', '.mm', '.swift'];
const _defaultSkipFiles = [
  '**/Pods/**',
  '**/.symlinks/**',
  '**/Flutter/**',
  '**/GeneratedPluginRegistrant.*',
  '**/build/**',
  '**/*.pbobjc.*',
];
const _defaultNameTemplates = [
  'handle{Word}{Kind}',
  'sync{Word}{Kind}',
  'prepare{Word}{Kind}',
];
const _defaultSemanticWords = [
  'Session',
  'Profile',
  'Route',
  'Cache',
  'Message',
  'State',
];
const _defaultKinds = [
  'State',
  'Payload',
  'Context',
  'Result',
  'Bridge',
  'Store',
];
const _reservedFunctionNames = {
  'main',
  'init',
  'dealloc',
  'viewDidLoad',
  'viewWillAppear',
  'viewDidAppear',
  'viewWillDisappear',
  'viewDidDisappear',
  'application',
  'drawRect',
  'didReceiveMemoryWarning',
  'prepareForSegue',
  'getObjectName',
  'persistentFlag',
  'messageWithContent',
  'registerWithRegistry',
};
const _reservedSelectorPrefixes = [
  'init',
  'set',
  'view',
  'application:',
  'applicationDid',
  'applicationWill',
  'userNotificationCenter:',
  'tableView:',
  'collectionView:',
  'scrollView',
  'navigationController:',
  'observeValueForKeyPath:',
];

typedef IosFunctionRenameProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class IosFunctionRenameConfig {
  IosFunctionRenameConfig({
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

  static IosFunctionRenameConfig load(String projectPath) {
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

    final value = decoded['iosFunctionRename'];
    if (value == null) return _defaults(source);
    if (value is! Map<String, dynamic>) {
      throw StateError('iosFunctionRename must be a JSON object.');
    }
    final enabled = value['enabled'];
    if (enabled != null && enabled is! bool) {
      throw StateError('iosFunctionRename.enabled must be a boolean.');
    }

    return IosFunctionRenameConfig(
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

  static IosFunctionRenameConfig _defaults(String source) {
    return IosFunctionRenameConfig(
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

class _FunctionRename {
  _FunctionRename({
    required this.file,
    required this.oldName,
    required this.newName,
    required this.language,
    required this.kind,
  });

  final String file;
  final String oldName;
  final String newName;
  final String language;
  final String kind;

  Map<String, dynamic> toJson() => {
        'file': file,
        'old_name': oldName,
        'new_name': newName,
        'language': language,
        'kind': kind,
      };
}

class _ObjcMethod {
  _ObjcMethod({required this.selector});

  final String selector;

  String get firstPart {
    final colon = selector.indexOf(':');
    return colon == -1 ? selector : selector.substring(0, colon);
  }
}

Future<void> runIosFunctionRename(
  String projectPath, {
  IosFunctionRenameProcessRunner processRunner = Process.run,
}) async {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    throw StateError('Project directory not found: $projectPath');
  }
  final iosDir = Directory(p.join(projectPath, 'ios'));
  if (!iosDir.existsSync()) {
    throw StateError('ios directory not found in $projectPath');
  }

  final config = IosFunctionRenameConfig.load(projectPath);
  if (!config.enabled) {
    Log.log('iOS function rename is disabled by config.');
    return;
  }

  final skipped = <Map<String, dynamic>>[];
  final planned = _buildFunctionRenames(projectPath, config, skipped);
  final rewrittenFiles = _rewriteFunctionReferences(projectPath, planned);
  final validation = await _validateRename(
    projectPath: projectPath,
    config: config,
    functionRenames: planned,
    processRunner: processRunner,
  );

  final mapping = {
    'generated_at': DateTime.now().toIso8601String(),
    'config': config.toJson(),
    'config_file': config.configSource,
    'function_renames': planned.map((rename) => rename.toJson()).toList(),
    'skipped': skipped,
    'rewritten_files': rewrittenFiles,
    'validation': validation,
    'summary': {
      'functions_renamed': planned.length,
      'files_rewritten': rewrittenFiles.length,
      'skipped': skipped.length,
    },
  };
  final mappingPath = writeHtmlFeatureMapping(
    projectPath: projectPath,
    featureId: 'ios_function_rename',
    featureTitle: 'iOS 内部函数换名',
    mapping: mapping,
  );

  final staticPassed =
      ((validation['static'] as Map<String, dynamic>)['passed']) == true;
  final xcodebuild = validation['xcodebuild'];
  final xcodePassed = xcodebuild == null ||
      ((xcodebuild as Map<String, dynamic>)['exit_code']) == 0;
  if (!staticPassed || !xcodePassed) {
    final issues = (validation['static'] as Map<String, dynamic>)['issues'];
    throw StateError(
      'iOS function rename validation failed: $mappingPath\n'
      'issues: $issues',
    );
  }

  Log.log('iOS function rename complete.');
  Log.log('Mapping document: $mappingPath');
}

List<_FunctionRename> _buildFunctionRenames(
  String projectPath,
  IosFunctionRenameConfig config,
  List<Map<String, dynamic>> skipped,
) {
  final iosDir = Directory(p.join(projectPath, 'ios'));
  final result = <_FunctionRename>[];
  final usedNamesByFile = <String, Set<String>>{};
  final publicObjcSelectors = _collectPublicObjcSelectors(projectPath, config);
  var index = 0;

  final files = iosDir
      .listSync(recursive: true)
      .whereType<File>()
      .where(
          (file) => config.includeExtensions.contains(p.extension(file.path)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final relative = _relative(projectPath, file.path);
    if (config.shouldSkip(relative)) {
      skipped.add({'file': relative, 'reason': 'skip_rule'});
      continue;
    }
    final source = _readUtf8TextOrNull(file);
    if (source == null) {
      skipped.add({'file': relative, 'reason': 'not_utf8'});
      continue;
    }
    final namesInFile = usedNamesByFile.putIfAbsent(
      relative,
      () => _collectIdentifiers(source),
    );
    final candidates = p.extension(file.path) == '.swift'
        ? _discoverSwiftFunctions(relative, source)
        : [
            ..._discoverObjcStaticFunctions(relative, source),
            ..._discoverObjcPrivateMethods(
              relative,
              source,
              publicObjcSelectors,
            ),
          ];
    for (final candidate in candidates) {
      if (_isReservedRename(candidate.oldName)) {
        skipped.add({
          'file': relative,
          'symbol': candidate.oldName,
          'reason': 'reserved_name',
        });
        continue;
      }
      final generatedName = _nextUniqueFunctionName(
        config,
        namesInFile,
        index++,
      );
      final newName = candidate.kind == 'objc_private_method'
          ? _renameObjcSelectorFirstPart(candidate.oldName, generatedName)
          : generatedName;
      result.add(_FunctionRename(
        file: relative,
        oldName: candidate.oldName,
        newName: newName,
        language: candidate.language,
        kind: candidate.kind,
      ));
      namesInFile.add(newName);
    }
  }

  return result;
}

Set<String> _collectPublicObjcSelectors(
  String projectPath,
  IosFunctionRenameConfig config,
) {
  final iosDir = Directory(p.join(projectPath, 'ios'));
  final selectors = <String>{};
  final files = iosDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => p.extension(file.path) == '.h')
      .toList();
  for (final file in files) {
    final relative = _relative(projectPath, file.path);
    if (config.shouldSkip(relative)) continue;
    final source = _readUtf8TextOrNull(file);
    if (source == null) continue;
    for (final method in _parseObjcMethods(relative, source)) {
      selectors.add(method.selector);
    }
  }
  return selectors;
}

List<_FunctionRename> _discoverObjcStaticFunctions(
  String relative,
  String source,
) {
  final result = <_FunctionRename>[];
  final pattern = RegExp(
    r'^\s*static\s+[^;={}\n]*?[*\s]+([A-Za-z_][A-Za-z0-9_]*)\s*\([^;{}]*\)\s*\{',
    multiLine: true,
  );
  for (final match in pattern.allMatches(source)) {
    result.add(_FunctionRename(
      file: relative,
      oldName: match.group(1)!,
      newName: '',
      language: 'objc',
      kind: 'static_function',
    ));
  }
  return result;
}

List<_FunctionRename> _discoverObjcPrivateMethods(
  String relative,
  String source,
  Set<String> publicSelectors,
) {
  final result = <_FunctionRename>[];
  final seenSelectors = <String>{};
  for (final method in _parseObjcMethods(relative, source)) {
    if (!seenSelectors.add(method.selector)) continue;
    if (publicSelectors.contains(method.selector)) continue;
    if (_isReservedRename(method.selector) ||
        _isReservedRename(method.firstPart)) {
      continue;
    }
    result.add(_FunctionRename(
      file: relative,
      oldName: method.selector,
      newName: '',
      language: 'objc',
      kind: 'objc_private_method',
    ));
  }
  return result;
}

List<_ObjcMethod> _parseObjcMethods(String relative, String source) {
  final result = <_ObjcMethod>[];
  final pattern =
      RegExp(r'^\s*[-+]\s*\([^)]*\)\s*(.+?)(?:\{|;)\s*$', multiLine: true);
  for (final match in pattern.allMatches(source)) {
    final signature = match.group(1)!.trim();
    final selector = _selectorFromObjcSignature(signature);
    if (selector == null) continue;
    result.add(_ObjcMethod(selector: selector));
  }
  return result;
}

String? _selectorFromObjcSignature(String signature) {
  final parts = <String>[];
  final labelPattern = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*:');
  for (final match in labelPattern.allMatches(signature)) {
    parts.add('${match.group(1)!}:');
  }
  if (parts.isNotEmpty) return parts.join();

  final noArgMatch =
      RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\b').firstMatch(signature);
  return noArgMatch?.group(1);
}

List<_FunctionRename> _discoverSwiftFunctions(
  String relative,
  String source,
) {
  final result = <_FunctionRename>[];
  final lines = source.split('\n');
  final pattern = RegExp(
    r'^\s*(private|fileprivate)\s+(?:(?:static|class)\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
  );
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final match = pattern.firstMatch(line);
    if (match == null) continue;
    if (_hasUnsafeSwiftAttribute(lines, index)) {
      result.add(_FunctionRename(
        file: relative,
        oldName: match.group(2)!,
        newName: '',
        language: 'swift',
        kind: 'skipped_attribute',
      ));
      continue;
    }
    result.add(_FunctionRename(
      file: relative,
      oldName: match.group(2)!,
      newName: '',
      language: 'swift',
      kind: '${match.group(1)!}_function',
    ));
  }
  return result.where((rename) => rename.kind != 'skipped_attribute').toList();
}

bool _hasUnsafeSwiftAttribute(List<String> lines, int functionLineIndex) {
  for (var index = functionLineIndex - 1; index >= 0; index--) {
    final line = lines[index].trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('@')) return false;
    if (line.startsWith('@objc') || line.startsWith('@IBAction')) return true;
  }
  return false;
}

List<String> _rewriteFunctionReferences(
  String projectPath,
  List<_FunctionRename> functionRenames,
) {
  if (functionRenames.isEmpty) return const [];
  final byFile = <String, List<_FunctionRename>>{};
  for (final rename in functionRenames) {
    byFile.putIfAbsent(rename.file, () => <_FunctionRename>[]).add(rename);
  }
  final rewritten = <String>[];
  for (final entry in byFile.entries) {
    final file = File(p.joinAll([projectPath, ...entry.key.split('/')]));
    final source = file.readAsStringSync();
    final updated = entry.key.endsWith('.swift')
        ? _rewriteSwiftSource(source, entry.value)
        : _rewriteObjcSource(source, entry.value);
    if (updated != source) {
      file.writeAsStringSync(updated);
      rewritten.add(entry.key);
    }
  }
  rewritten.sort();
  return rewritten;
}

String _rewriteSwiftSource(String source, List<_FunctionRename> renames) {
  var updated = source;
  for (final rename in renames) {
    updated = _replaceIdentifier(updated, rename.oldName, rename.newName);
  }
  return updated;
}

String _rewriteObjcSource(String source, List<_FunctionRename> renames) {
  final staticRenames =
      renames.where((rename) => rename.kind == 'static_function').toList();
  final selectorRenames =
      renames.where((rename) => rename.kind == 'objc_private_method').toList();
  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    var line = lines[index];
    if (!_isObjcMethodLine(line)) {
      for (final rename in staticRenames) {
        line = _replaceIdentifier(line, rename.oldName, rename.newName);
      }
    }
    for (final rename in selectorRenames) {
      line = _replaceObjcSelector(line, rename);
    }
    lines[index] = line;
  }
  return lines.join('\n');
}

Future<Map<String, dynamic>> _validateRename({
  required String projectPath,
  required IosFunctionRenameConfig config,
  required List<_FunctionRename> functionRenames,
  required IosFunctionRenameProcessRunner processRunner,
}) async {
  final staticIssues = <String>[];
  final byFile = <String, List<_FunctionRename>>{};
  for (final rename in functionRenames) {
    byFile.putIfAbsent(rename.file, () => <_FunctionRename>[]).add(rename);
  }

  for (final entry in byFile.entries) {
    if (config.shouldSkip(entry.key)) continue;
    final file = File(p.joinAll([projectPath, ...entry.key.split('/')]));
    final content = _readUtf8TextOrNull(file);
    if (content == null) continue;
    for (final rename in entry.value) {
      final oldStillExists = entry.key.endsWith('.swift')
          ? _containsIdentifier(content, rename.oldName)
          : rename.kind == 'objc_private_method'
              ? _containsObjcSelector(content, rename.oldName)
              : _containsIdentifierOutsideObjcMethodLines(
                  content,
                  rename.oldName,
                );
      if (oldStillExists) {
        staticIssues.add('${entry.key} still contains ${rename.oldName}');
      }
      final newExists = rename.kind == 'objc_private_method'
          ? _containsIdentifier(content, _objcSelectorFirstPart(rename.newName))
          : _containsIdentifier(content, rename.newName);
      if (!newExists) {
        staticIssues.add('${entry.key} missing ${rename.newName}');
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

String _nextUniqueFunctionName(
  IosFunctionRenameConfig config,
  Set<String> usedNames,
  int startIndex,
) {
  var attempt = 0;
  while (attempt < 10000) {
    final value = _renderFunctionName(config, startIndex + attempt);
    if (!usedNames.contains(value) &&
        !_reservedFunctionNames.contains(value) &&
        !_startsWithUnsafePrefix(value)) {
      return value;
    }
    attempt++;
  }
  throw StateError('Unable to create unique iOS function name.');
}

String _renderFunctionName(IosFunctionRenameConfig config, int index) {
  final wordCount = config.semanticWords.length;
  final kindCount = config.kinds.length;
  final templateCount = config.nameTemplates.length;
  final comboCount = wordCount * kindCount * templateCount;
  final comboIndex = index % comboCount;
  final overflow = index ~/ comboCount;
  final templateIndex = comboIndex ~/ (wordCount * kindCount);
  final remainder = comboIndex % (wordCount * kindCount);
  final wordIndex = remainder ~/ kindCount;
  final kindIndex = remainder % kindCount;
  final template = config.nameTemplates[templateIndex];
  final word = config.semanticWords[wordIndex];
  final kind = config.kinds[kindIndex];
  final suffix = overflow == 0 ? '' : overflow.toString();
  return _camelCase(
    template.replaceAll('{Word}', word).replaceAll('{Kind}', kind) + suffix,
  );
}

String _renameObjcSelectorFirstPart(String selector, String newFirstPart) {
  final colon = selector.indexOf(':');
  if (colon == -1) return newFirstPart;
  return '$newFirstPart${selector.substring(colon)}';
}

String _replaceObjcSelector(String line, _FunctionRename rename) {
  final oldFirst = _objcSelectorFirstPart(rename.oldName);
  final newFirst = _objcSelectorFirstPart(rename.newName);
  return _replaceIdentifier(line, oldFirst, newFirst);
}

String _objcSelectorFirstPart(String selector) {
  final colon = selector.indexOf(':');
  return colon == -1 ? selector : selector.substring(0, colon);
}

bool _containsObjcSelector(String source, String selector) {
  final firstPart = _objcSelectorFirstPart(selector);
  return _containsIdentifier(source, firstPart);
}

bool _isReservedRename(String value) {
  final firstPart = _objcSelectorFirstPart(value);
  if (_reservedFunctionNames.contains(value) ||
      _reservedFunctionNames.contains(firstPart)) {
    return true;
  }
  return _reservedSelectorPrefixes.any(
    (prefix) => value.startsWith(prefix) || firstPart.startsWith(prefix),
  );
}

bool _startsWithUnsafePrefix(String value) {
  return value.startsWith('init') || value.startsWith('set');
}

Set<String> _collectIdentifiers(String source) {
  return RegExp(r'\b[A-Za-z_][A-Za-z0-9_]*\b')
      .allMatches(source)
      .map((match) => match.group(0)!)
      .toSet();
}

String _replaceIdentifier(String source, String oldName, String newName) {
  return source.replaceAllMapped(
    RegExp('(?<![A-Za-z0-9_])${RegExp.escape(oldName)}(?![A-Za-z0-9_])'),
    (_) => newName,
  );
}

bool _containsIdentifier(String source, String name) {
  return RegExp('(?<![A-Za-z0-9_])${RegExp.escape(name)}(?![A-Za-z0-9_])')
      .hasMatch(source);
}

bool _containsIdentifierOutsideObjcMethodLines(String source, String name) {
  return source
      .split('\n')
      .where((line) => !_isObjcMethodLine(line))
      .any((line) => _containsIdentifier(line, name));
}

bool _isObjcMethodLine(String line) {
  return RegExp(r'^\s*[-+]\s*\(').hasMatch(line);
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

File _resolveConfigFile(String projectPath) {
  final projectConfig = File(p.join(projectPath, _configFileName));
  if (projectConfig.existsSync()) return projectConfig;
  return File(p.join(Directory.current.path, _configFileName));
}

String _relative(String root, String path) {
  return p.relative(path, from: root).replaceAll(r'\', '/');
}

String _camelCase(String value) {
  final words = RegExp(r'[A-Za-z0-9]+')
      .allMatches(value)
      .map((match) => match.group(0)!)
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return value;
  final first =
      words.first.substring(0, 1).toLowerCase() + words.first.substring(1);
  final rest = words.skip(1).map((word) {
    return word.substring(0, 1).toUpperCase() + word.substring(1);
  }).join();
  return '$first$rest';
}

List<String> _readStringList(
  Map<String, dynamic> json,
  String key,
  List<String> defaults,
) {
  final value = json[key];
  if (value == null) return List<String>.from(defaults);
  if (value is! List || value.any((item) => item is! String || item.isEmpty)) {
    throw StateError(
        'iosFunctionRename.$key must be a non-empty string array.');
  }
  if (value.isEmpty) {
    throw StateError('iosFunctionRename.$key must not be empty.');
  }
  return value.cast<String>();
}

bool _globMatches(String pattern, String value) {
  final regex = StringBuffer('^');
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == '*') {
      final isDoubleStar = i + 1 < pattern.length && pattern[i + 1] == '*';
      if (isDoubleStar) {
        regex.write('.*');
        i++;
      } else {
        regex.write('[^/]*');
      }
    } else if (char == '?') {
      regex.write('[^/]');
    } else {
      regex.write(RegExp.escape(char));
    }
  }
  regex.write(r'$');
  return RegExp(regex.toString()).hasMatch(value);
}
