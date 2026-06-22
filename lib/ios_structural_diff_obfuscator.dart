import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/log.dart';
import 'package:path/path.dart' as p;

const _configFileName = 'obfuscate_dart_noise.json';
const _defaultSkipFiles = [
  '**/Pods/**',
  '**/.symlinks/**',
  '**/Flutter/**',
  '**/GeneratedPluginRegistrant.*',
  '**/build/**',
  '**/*.pbobjc.*',
];
const _defaultTransforms = [
  'wrapDispatch',
  'extractBlock',
  'splitControlFlow',
];
const _defaultHelperNameTemplates = [
  'obfIos{Index}{Kind}',
  'syncIos{Index}{Kind}',
  'bridgeIos{Index}{Kind}',
];
const _supportedTransforms = {
  'wrapDispatch',
  'extractBlock',
  'splitControlFlow',
};

typedef IosStructuralDiffProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

enum _IosLanguage { objectiveC, objectiveCpp, swift }

class IosStructuralDiffConfig {
  IosStructuralDiffConfig({
    required this.enabled,
    required this.skipFiles,
    required this.maxTransformsPerFile,
    required this.transforms,
    required this.helperNameTemplates,
    required this.validation,
    required this.configSource,
  });

  final bool enabled;
  final List<String> skipFiles;
  final int maxTransformsPerFile;
  final List<String> transforms;
  final List<String> helperNameTemplates;
  final String validation;
  final String configSource;

  static IosStructuralDiffConfig load(String projectPath) {
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

    final value = decoded['iosStructuralDiff'];
    if (value == null) return _defaults(source);
    if (value is! Map<String, dynamic>) {
      throw StateError('iosStructuralDiff must be a JSON object.');
    }

    final enabled = value['enabled'];
    if (enabled != null && enabled is! bool) {
      throw StateError('iosStructuralDiff.enabled must be a boolean.');
    }
    final validation = value['validation'] ?? 'static_xcode_list';
    if (validation is! String || validation != 'static_xcode_list') {
      throw StateError(
        'iosStructuralDiff.validation only supports static_xcode_list.',
      );
    }

    return IosStructuralDiffConfig(
      enabled: enabled ?? true,
      skipFiles: _readStringList(
        value,
        'skipFiles',
        _defaultSkipFiles,
        allowEmpty: false,
      ),
      maxTransformsPerFile: _readOptionalBoundedInt(
        value,
        'maxTransformsPerFile',
        1,
        100,
        10,
      ),
      transforms: _readTransforms(value),
      helperNameTemplates: _readHelperNameTemplates(value),
      validation: validation,
      configSource: source,
    );
  }

  static IosStructuralDiffConfig _defaults(String source) {
    return IosStructuralDiffConfig(
      enabled: true,
      skipFiles: List<String>.from(_defaultSkipFiles),
      maxTransformsPerFile: 10,
      transforms: List<String>.from(_defaultTransforms),
      helperNameTemplates: List<String>.from(_defaultHelperNameTemplates),
      validation: 'static_xcode_list',
      configSource: source,
    );
  }

  bool shouldSkip(String relativePath) {
    final normalized = relativePath.replaceAll(r'\', '/');
    return skipFiles.any((pattern) => _globMatches(pattern, normalized));
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'skipFiles': skipFiles,
        'maxTransformsPerFile': maxTransformsPerFile,
        'transforms': transforms,
        'helperNameTemplates': helperNameTemplates,
        'validation': validation,
        'configSource': configSource,
      };
}

class _IosSourceFile {
  _IosSourceFile({
    required this.file,
    required this.relativePath,
    required this.language,
  });

  final File file;
  final String relativePath;
  final _IosLanguage language;
}

class _ObjcMethod {
  _ObjcMethod({
    required this.matchStart,
    required this.matchEnd,
    required this.bodyStart,
    required this.bodyEnd,
    required this.kind,
    required this.returnType,
    required this.signatureRest,
    required this.selector,
    required this.params,
  });

  final int matchStart;
  final int matchEnd;
  final int bodyStart;
  final int bodyEnd;
  final String kind;
  final String returnType;
  final String signatureRest;
  final String selector;
  final List<_Param> params;

  bool get isVoid => returnType.trim() == 'void' || returnType.trim() == 'Void';
}

class _SwiftFunction {
  _SwiftFunction({
    required this.matchStart,
    required this.matchEnd,
    required this.bodyStart,
    required this.bodyEnd,
    required this.name,
    required this.paramsSource,
    required this.arguments,
    required this.returnClause,
    required this.modifier,
    required this.staticPrefix,
    required this.exposed,
  });

  final int matchStart;
  final int matchEnd;
  final int bodyStart;
  final int bodyEnd;
  final String name;
  final String paramsSource;
  final List<String> arguments;
  final String returnClause;
  final String modifier;
  final String staticPrefix;
  final bool exposed;

  bool get returnsValue => returnClause.trim().isNotEmpty;
}

class _Param {
  _Param(this.label, this.type, this.name);

  final String label;
  final String type;
  final String name;
}

class _TransformEdit {
  _TransformEdit({
    required this.source,
    required this.helperName,
    required this.transform,
    required this.methodName,
    required this.isStaticLike,
  });

  final String source;
  final String helperName;
  final String transform;
  final String methodName;
  final bool isStaticLike;
}

Future<void> runIosStructuralDiffObfuscation(
  String projectPath, {
  IosStructuralDiffProcessRunner processRunner = Process.run,
}) async {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    throw StateError('Project directory not found: $projectPath');
  }
  final iosDir = Directory(p.join(projectPath, 'ios'));
  if (!iosDir.existsSync()) {
    throw StateError('ios directory not found in $projectPath');
  }

  final config = IosStructuralDiffConfig.load(projectPath);
  if (!config.enabled) {
    Log.log('iOS structural diff obfuscation is disabled by config.');
    return;
  }

  final files = _discoverIosSourceFiles(projectPath, config);
  final publicObjcSelectors = _collectPublicObjcSelectors(projectPath, config);
  final touched = <String>{};
  final applied = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  var globalIndex = 0;

  for (final sourceFile in files) {
    final source = _readUtf8TextOrNull(sourceFile.file);
    if (source == null) {
      skipped.add({'file': sourceFile.relativePath, 'reason': 'not_utf8'});
      continue;
    }
    if (_containsGeneratedHelper(source, config)) {
      skipped.add({
        'file': sourceFile.relativePath,
        'reason': 'already_structured',
      });
      continue;
    }

    final result = sourceFile.language == _IosLanguage.swift
        ? _rewriteSwiftFile(
            source,
            config,
            sourceFile.relativePath,
            skipped,
            globalIndex,
          )
        : _rewriteObjcFile(
            source,
            config,
            sourceFile.relativePath,
            publicObjcSelectors,
            skipped,
            globalIndex,
          );
    globalIndex = result.nextIndex;
    if (result.source != source) {
      sourceFile.file.writeAsStringSync(result.source);
      touched.add(sourceFile.relativePath);
      applied.addAll(result.applied.map((entry) => {
            'file': sourceFile.relativePath,
            ...entry,
          }));
    }
  }

  final validation = await _validateStructuralDiff(
    projectPath: projectPath,
    touched: touched,
    applied: applied,
    processRunner: processRunner,
  );
  final mappingPath =
      p.join(projectPath, 'ios_structural_diff_mapping_${_timestamp()}.json');
  File(mappingPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'generated_at': DateTime.now().toIso8601String(),
      'config': config.toJson(),
      'config_file': config.configSource,
      'files_scanned': files.map((file) => file.relativePath).toList(),
      'files_touched': touched.toList()..sort(),
      'transforms_applied': applied,
      'skipped': skipped,
      'validation': validation,
      'summary': {
        'files_scanned': files.length,
        'files_touched': touched.length,
        'transforms': applied.length,
        'skipped': skipped.length,
      },
    }),
  );

  final staticPassed =
      ((validation['static'] as Map<String, dynamic>)['passed']) == true;
  final xcodebuild = validation['xcodebuild'];
  final xcodePassed = xcodebuild == null ||
      ((xcodebuild as Map<String, dynamic>)['exit_code']) == 0;
  if (!staticPassed || !xcodePassed) {
    throw StateError('iOS structural diff validation failed: $mappingPath');
  }
  Log.log('iOS structural diff obfuscation complete.');
  Log.log('Mapping document: $mappingPath');
}

_RewriteResult _rewriteObjcFile(
  String source,
  IosStructuralDiffConfig config,
  String relativePath,
  Set<String> publicSelectors,
  List<Map<String, dynamic>> skipped,
  int globalIndex,
) {
  var updated = source;
  var nextIndex = globalIndex;
  var perFile = 0;
  final applied = <Map<String, dynamic>>[];
  final allMethods = _findObjcMethods(source);
  final transformOrdinalByStart = <int, int>{};
  for (final method in allMethods) {
    if (!publicSelectors.contains(method.selector)) {
      transformOrdinalByStart[method.matchStart] =
          transformOrdinalByStart.length;
    }
  }
  final methods = allMethods.reversed.toList();

  for (final method in methods) {
    if (perFile >= config.maxTransformsPerFile) break;
    if (publicSelectors.contains(method.selector)) {
      skipped.add({
        'file': relativePath,
        'method': method.selector,
        'reason': 'public_objc_selector',
      });
      continue;
    }
    final ordinal = transformOrdinalByStart[method.matchStart] ?? perFile;
    final transform = config.transforms[ordinal % config.transforms.length];
    final helperName = _renderHelperName(config, nextIndex, 'Bridge');
    final edit = switch (transform) {
      'wrapDispatch' => _wrapObjcMethod(updated, method, helperName),
      'extractBlock' => _extractObjcBlock(updated, method, helperName),
      'splitControlFlow' => _splitObjcControlFlow(updated, method, helperName),
      _ => null,
    };
    if (edit == null) {
      skipped.add({
        'file': relativePath,
        'method': method.selector,
        'reason': 'unsafe_control_flow',
      });
      continue;
    }
    updated = edit.source;
    applied.add({
      'language': 'objectiveC',
      'container': '<implementation>',
      'method': edit.methodName,
      'transform': edit.transform,
      'helper_name': edit.helperName,
      'is_static_like': edit.isStaticLike,
    });
    nextIndex++;
    perFile++;
  }

  return _RewriteResult(updated, nextIndex, applied);
}

_RewriteResult _rewriteSwiftFile(
  String source,
  IosStructuralDiffConfig config,
  String relativePath,
  List<Map<String, dynamic>> skipped,
  int globalIndex,
) {
  var updated = source;
  var nextIndex = globalIndex;
  var perFile = 0;
  final applied = <Map<String, dynamic>>[];
  final allFunctions = _findSwiftFunctions(source);
  final transformOrdinalByStart = <int, int>{};
  for (final function in allFunctions) {
    if (!function.exposed && function.modifier != 'public') {
      transformOrdinalByStart[function.matchStart] =
          transformOrdinalByStart.length;
    }
  }
  final functions = allFunctions.reversed.toList();

  for (final function in functions) {
    if (perFile >= config.maxTransformsPerFile) break;
    if (function.exposed || function.modifier == 'public') {
      skipped.add({
        'file': relativePath,
        'method': function.name,
        'reason': 'public_or_exposed_swift',
      });
      continue;
    }
    final ordinal = transformOrdinalByStart[function.matchStart] ?? perFile;
    final transform = config.transforms[ordinal % config.transforms.length];
    final helperName = _renderHelperName(config, nextIndex, 'Bridge');
    final edit = switch (transform) {
      'wrapDispatch' => _wrapSwiftFunction(updated, function, helperName),
      'extractBlock' => _extractSwiftBlock(updated, function, helperName),
      'splitControlFlow' =>
        _splitSwiftControlFlow(updated, function, helperName),
      _ => null,
    };
    if (edit == null) {
      skipped.add({
        'file': relativePath,
        'method': function.name,
        'reason': 'unsafe_control_flow',
      });
      continue;
    }
    updated = edit.source;
    applied.add({
      'language': 'swift',
      'container': '<type>',
      'method': edit.methodName,
      'transform': edit.transform,
      'helper_name': edit.helperName,
      'is_static_like': edit.isStaticLike,
    });
    nextIndex++;
    perFile++;
  }

  return _RewriteResult(updated, nextIndex, applied);
}

class _RewriteResult {
  _RewriteResult(this.source, this.nextIndex, this.applied);

  final String source;
  final int nextIndex;
  final List<Map<String, dynamic>> applied;
}

_TransformEdit? _wrapObjcMethod(
  String source,
  _ObjcMethod method,
  String helperName,
) {
  final body = _bodyText(source, method.bodyStart, method.bodyEnd);
  if (_containsUnsafeObjcBody(body, allowReturn: true)) return null;
  final call = _objcCall(method, helperName);
  final replacement =
      '${source.substring(method.matchStart, method.bodyStart)}{\n'
      '  $call\n'
      '}\n\n${_objcMethodDeclaration(method, helperName)} {\n$body\n}';
  return _TransformEdit(
    source:
        source.replaceRange(method.matchStart, method.bodyEnd + 1, replacement),
    helperName: helperName,
    transform: 'wrapDispatch',
    methodName: method.selector,
    isStaticLike: method.kind == '+',
  );
}

_TransformEdit? _extractObjcBlock(
  String source,
  _ObjcMethod method,
  String helperName,
) {
  final body = _bodyText(source, method.bodyStart, method.bodyEnd);
  if (method.isVoid == false || _containsUnsafeObjcBody(body)) return null;
  final call = '${method.kind == '+' ? '[self' : '[self'} $helperName];';
  final replacement =
      '${source.substring(method.matchStart, method.bodyStart)}{\n'
      '  $call\n'
      '}\n\n${method.kind} (void)$helperName {\n$body\n}';
  return _TransformEdit(
    source:
        source.replaceRange(method.matchStart, method.bodyEnd + 1, replacement),
    helperName: helperName,
    transform: 'extractBlock',
    methodName: method.selector,
    isStaticLike: method.kind == '+',
  );
}

_TransformEdit? _splitObjcControlFlow(
  String source,
  _ObjcMethod method,
  String helperName,
) {
  final body = _bodyText(source, method.bodyStart, method.bodyEnd);
  if (_containsUnsafeObjcBody(body)) return null;
  final indented = _indentBody(body, '    ');
  final replacementBody = '\n  NSInteger ${helperName}Guard = 0;\n'
      '  if (${helperName}Guard >= 0) {\n'
      '$indented\n'
      '  }\n';
  return _TransformEdit(
    source: source.replaceRange(
      method.bodyStart + 1,
      method.bodyEnd,
      replacementBody,
    ),
    helperName: helperName,
    transform: 'splitControlFlow',
    methodName: method.selector,
    isStaticLike: method.kind == '+',
  );
}

_TransformEdit? _wrapSwiftFunction(
  String source,
  _SwiftFunction function,
  String helperName,
) {
  final body = _bodyText(source, function.bodyStart, function.bodyEnd);
  if (_containsUnsafeSwiftBody(body, allowReturn: true)) return null;
  final args = function.arguments.join(', ');
  final call = function.returnsValue
      ? 'return $helperName($args)'
      : '$helperName($args)';
  final helper = _swiftHelper(function, helperName, body);
  final replacement =
      '${source.substring(function.matchStart, function.bodyStart)}{\n'
      '    $call\n'
      '  }\n\n$helper';
  return _TransformEdit(
    source: source.replaceRange(
      function.matchStart,
      function.bodyEnd + 1,
      replacement,
    ),
    helperName: helperName,
    transform: 'wrapDispatch',
    methodName: function.name,
    isStaticLike: function.staticPrefix.trim().isNotEmpty,
  );
}

_TransformEdit? _extractSwiftBlock(
  String source,
  _SwiftFunction function,
  String helperName,
) {
  final body = _bodyText(source, function.bodyStart, function.bodyEnd);
  if (function.returnsValue || _containsUnsafeSwiftBody(body)) return null;
  final args = function.arguments.join(', ');
  final helper = _swiftHelper(function, helperName, body, forceVoid: true);
  final replacement =
      '${source.substring(function.matchStart, function.bodyStart)}{\n'
      '    $helperName($args)\n'
      '  }\n\n$helper';
  return _TransformEdit(
    source: source.replaceRange(
      function.matchStart,
      function.bodyEnd + 1,
      replacement,
    ),
    helperName: helperName,
    transform: 'extractBlock',
    methodName: function.name,
    isStaticLike: function.staticPrefix.trim().isNotEmpty,
  );
}

_TransformEdit? _splitSwiftControlFlow(
  String source,
  _SwiftFunction function,
  String helperName,
) {
  final body = _bodyText(source, function.bodyStart, function.bodyEnd);
  if (_containsUnsafeSwiftBody(body)) return null;
  final indented = _indentBody(body, '      ');
  final replacementBody = '\n    let ${helperName}Guard = 0\n'
      '    if ${helperName}Guard >= 0 {\n'
      '$indented\n'
      '    }\n'
      '  ';
  return _TransformEdit(
    source: source.replaceRange(
      function.bodyStart + 1,
      function.bodyEnd,
      replacementBody,
    ),
    helperName: helperName,
    transform: 'splitControlFlow',
    methodName: function.name,
    isStaticLike: function.staticPrefix.trim().isNotEmpty,
  );
}

String _objcCall(_ObjcMethod method, String helperName) {
  final args = method.params.map((param) => param.name).toList();
  final call = method.params.isEmpty
      ? '[self $helperName];'
      : '[self $helperName:${args.first}${_objcExtraArgs(method.params)}];';
  return method.isVoid ? call : 'return ${call.substring(0, call.length - 1)};';
}

String _objcExtraArgs(List<_Param> params) {
  if (params.length < 2) return '';
  return params.skip(1).map((param) => ' ${param.label}:${param.name}').join();
}

String _objcMethodDeclaration(_ObjcMethod method, String helperName) {
  if (method.params.isEmpty) {
    return '${method.kind} (${method.returnType})$helperName';
  }
  final first = method.params.first;
  final rest = method.params
      .skip(1)
      .map((param) => ' ${param.label}:(${param.type})${param.name}')
      .join();
  return '${method.kind} (${method.returnType})$helperName:'
      '(${first.type})${first.name}$rest';
}

String _swiftHelper(
  _SwiftFunction function,
  String helperName,
  String body, {
  bool forceVoid = false,
}) {
  final returnClause = forceVoid ? '' : function.returnClause;
  final staticPrefix = function.staticPrefix.trim().isEmpty
      ? ''
      : '${function.staticPrefix.trim()} ';
  return '  private ${staticPrefix}func $helperName'
      '(${function.paramsSource})$returnClause {\n$body\n  }';
}

List<_ObjcMethod> _findObjcMethods(String source) {
  final result = <_ObjcMethod>[];
  final pattern = RegExp(
    r'^[ \t]*([+-])\s*\(([^)]*)\)\s*([^{;]+)\{',
    multiLine: true,
  );
  for (final match in pattern.allMatches(source)) {
    if (_isInsideIgnoredSource(source, match.start)) continue;
    final bodyStart = source.indexOf('{', match.start);
    final bodyEnd = _findMatchingBrace(source, bodyStart);
    if (bodyStart == -1 || bodyEnd == -1) continue;
    final signatureRest = match.group(3)!.trim();
    result.add(_ObjcMethod(
      matchStart: match.start,
      matchEnd: match.end,
      bodyStart: bodyStart,
      bodyEnd: bodyEnd,
      kind: match.group(1)!,
      returnType: match.group(2)!.trim(),
      signatureRest: signatureRest,
      selector: _objcSelector(signatureRest),
      params: _objcParams(signatureRest),
    ));
  }
  return result;
}

List<_SwiftFunction> _findSwiftFunctions(String source) {
  final result = <_SwiftFunction>[];
  final pattern = RegExp(
    r'^([ \t]*(?:(public|private|fileprivate|internal)\s+)?((?:static|class)\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*([^{\n]*?)\{)',
    multiLine: true,
  );
  for (final match in pattern.allMatches(source)) {
    if (_isInsideIgnoredSource(source, match.start)) continue;
    final bodyStart = source.indexOf('{', match.start);
    final bodyEnd = _findMatchingBrace(source, bodyStart);
    if (bodyStart == -1 || bodyEnd == -1) continue;
    result.add(_SwiftFunction(
      matchStart: match.start,
      matchEnd: match.end,
      bodyStart: bodyStart,
      bodyEnd: bodyEnd,
      name: match.group(4)!,
      paramsSource: match.group(5)!.trim(),
      arguments: _swiftArguments(match.group(5)!.trim()),
      returnClause: match.group(6) ?? '',
      modifier: match.group(2) ?? 'internal',
      staticPrefix: match.group(3) ?? '',
      exposed: _hasUnsafeSwiftAttribute(source, match.start),
    ));
  }
  return result;
}

Set<String> _collectPublicObjcSelectors(
  String projectPath,
  IosStructuralDiffConfig config,
) {
  final iosDir = Directory(p.join(projectPath, 'ios'));
  final selectors = <String>{};
  for (final file in iosDir.listSync(recursive: true).whereType<File>()) {
    final relative = _relative(projectPath, file.path);
    if (p.extension(file.path) != '.h' || config.shouldSkip(relative)) {
      continue;
    }
    final source = _readUtf8TextOrNull(file);
    if (source == null) continue;
    for (final method in _findObjcMethods(source)) {
      selectors.add(method.selector);
    }
    final declarationPattern =
        RegExp(r'^[ \t]*[-+]\s*\([^)]*\)\s*([^;{]+);', multiLine: true);
    for (final match in declarationPattern.allMatches(source)) {
      if (_isInsideIgnoredSource(source, match.start)) continue;
      selectors.add(_objcSelector(match.group(1)!.trim()));
    }
  }
  return selectors;
}

List<_IosSourceFile> _discoverIosSourceFiles(
  String projectPath,
  IosStructuralDiffConfig config,
) {
  final iosDir = Directory(p.join(projectPath, 'ios'));
  final files = <_IosSourceFile>[];
  for (final file in iosDir.listSync(recursive: true).whereType<File>()) {
    final relative = _relative(projectPath, file.path);
    if (config.shouldSkip(relative)) continue;
    final language = switch (p.extension(file.path)) {
      '.m' => _IosLanguage.objectiveC,
      '.mm' => _IosLanguage.objectiveCpp,
      '.swift' => _IosLanguage.swift,
      _ => null,
    };
    if (language == null) continue;
    files.add(_IosSourceFile(
      file: file,
      relativePath: relative,
      language: language,
    ));
  }
  files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return files;
}

Future<Map<String, dynamic>> _validateStructuralDiff({
  required String projectPath,
  required Set<String> touched,
  required List<Map<String, dynamic>> applied,
  required IosStructuralDiffProcessRunner processRunner,
}) async {
  final issues = <String>[];
  for (final transform in applied) {
    final file = File(p.joinAll([
      projectPath,
      ...(transform['file'] as String).split('/'),
    ]));
    final source = _readUtf8TextOrNull(file) ?? '';
    final helperName = transform['helper_name'] as String;
    if (!source.contains(helperName)) {
      issues.add('${transform['file']} missing $helperName');
    }
  }
  final validation = <String, dynamic>{
    'static': {
      'passed': issues.isEmpty,
      'issues': issues,
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

String _objcSelector(String signatureRest) {
  final labels = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*:').allMatches(
    signatureRest,
  );
  final parts = labels.map((match) => '${match.group(1)!}:').toList();
  if (parts.isNotEmpty) return parts.join();
  return RegExp(r'([A-Za-z_][A-Za-z0-9_]*)')
          .firstMatch(signatureRest)
          ?.group(1) ??
      '<unknown>';
}

List<_Param> _objcParams(String signatureRest) {
  final params = <_Param>[];
  final pattern = RegExp(
    r'([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\(([^)]*)\)\s*([A-Za-z_][A-Za-z0-9_]*)',
  );
  for (final match in pattern.allMatches(signatureRest)) {
    params.add(_Param(
      match.group(1)!,
      match.group(2)!.trim(),
      match.group(3)!,
    ));
  }
  return params;
}

List<String> _swiftArguments(String paramsSource) {
  if (paramsSource.trim().isEmpty) return const [];
  return paramsSource
      .split(',')
      .map((param) {
        final left = param.split(':').first.trim();
        final pieces =
            left.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        if (pieces.isEmpty) return '';
        if (pieces.length == 1) return pieces.first;
        return pieces.last;
      })
      .where((arg) => arg.isNotEmpty && arg != '_')
      .toList();
}

bool _hasUnsafeSwiftAttribute(String source, int functionStart) {
  final before = source.substring(0, functionStart).split('\n');
  for (var index = before.length - 1; index >= 0; index--) {
    final line = before[index].trim();
    if (line.isEmpty) continue;
    if (!line.startsWith('@')) return false;
    if (line.startsWith('@objc') || line.startsWith('@IBAction')) return true;
  }
  return false;
}

bool _isInsideIgnoredSource(String source, int offset) {
  var inLineComment = false;
  var inBlockComment = false;
  String? quote;
  var escaped = false;

  for (var index = 0; index < offset && index < source.length; index++) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';

    if (inLineComment) {
      if (char == '\n') inLineComment = false;
      continue;
    }

    if (inBlockComment) {
      if (char == '*' && next == '/') {
        inBlockComment = false;
        index++;
      }
      continue;
    }

    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }

    if (char == '/' && next == '/') {
      inLineComment = true;
      index++;
      continue;
    }
    if (char == '/' && next == '*') {
      inBlockComment = true;
      index++;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
    }
  }

  return inLineComment || inBlockComment || quote != null;
}

bool _containsUnsafeObjcBody(String body, {bool allowReturn = false}) {
  final unsafe = ['throw', 'break', 'continue', 'goto'];
  if (!allowReturn) unsafe.add('return');
  return unsafe.any((word) => RegExp('\\b$word\\b').hasMatch(body));
}

bool _containsUnsafeSwiftBody(String body, {bool allowReturn = false}) {
  final unsafe = ['throw', 'break', 'continue', 'defer', 'await'];
  if (!allowReturn) unsafe.add('return');
  return unsafe.any((word) => RegExp('\\b$word\\b').hasMatch(body));
}

String _bodyText(String source, int bodyStart, int bodyEnd) {
  return source.substring(bodyStart + 1, bodyEnd).trimRight();
}

String _indentBody(String body, String indent) {
  final trimmed = body.trimRight();
  if (trimmed.isEmpty) return '';
  return trimmed
      .split('\n')
      .map((line) => line.trim().isEmpty ? '' : '$indent${line.trimLeft()}')
      .join('\n');
}

String _renderHelperName(
  IosStructuralDiffConfig config,
  int index,
  String kind,
) {
  final template =
      config.helperNameTemplates[index % config.helperNameTemplates.length];
  return template.replaceAll('{Index}', '$index').replaceAll('{Kind}', kind);
}

bool _containsGeneratedHelper(
  String source,
  IosStructuralDiffConfig config,
) {
  for (final template in config.helperNameTemplates) {
    for (var index = 0; index < 10000; index++) {
      final helperName = template
          .replaceAll('{Index}', '$index')
          .replaceAll('{Kind}', 'Bridge');
      if (source.contains(helperName)) return true;
    }
  }
  return false;
}

int _findMatchingBrace(String source, int openOffset) {
  if (openOffset < 0 ||
      openOffset >= source.length ||
      source.codeUnitAt(openOffset) != 123) {
    return -1;
  }
  var depth = 0;
  var inLineComment = false;
  var inBlockComment = false;
  String? quote;
  var escaped = false;

  for (var index = openOffset; index < source.length; index++) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';
    if (inLineComment) {
      if (char == '\n') inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (char == '*' && next == '/') {
        inBlockComment = false;
        index++;
      }
      continue;
    }
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == quote) {
        quote = null;
      }
      continue;
    }
    if (char == '/' && next == '/') {
      inLineComment = true;
      index++;
      continue;
    }
    if (char == '/' && next == '*') {
      inBlockComment = true;
      index++;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) return index;
    }
  }
  return -1;
}

File _resolveConfigFile(String projectPath) {
  final projectConfig = File(p.join(projectPath, _configFileName));
  if (projectConfig.existsSync()) return projectConfig;
  return File(p.join(Directory.current.path, _configFileName));
}

int _readOptionalBoundedInt(
  Map<String, dynamic> json,
  String key,
  int min,
  int max,
  int defaultValue,
) {
  final value = json[key];
  if (value == null) return defaultValue;
  if (value is! int || value < min || value > max) {
    throw StateError('iosStructuralDiff.$key must be from $min to $max.');
  }
  return value;
}

List<String> _readStringList(
  Map<String, dynamic> json,
  String key,
  List<String> defaults, {
  required bool allowEmpty,
}) {
  final value = json[key];
  if (value == null) return List<String>.from(defaults);
  if (value is! List ||
      value.any((item) => item is! String || item.trim().isEmpty) ||
      (!allowEmpty && value.isEmpty)) {
    throw StateError('iosStructuralDiff.$key must be a string array.');
  }
  return value.cast<String>();
}

List<String> _readTransforms(Map<String, dynamic> json) {
  final transforms = _readStringList(
    json,
    'transforms',
    _defaultTransforms,
    allowEmpty: false,
  );
  for (final transform in transforms) {
    if (!_supportedTransforms.contains(transform)) {
      throw StateError(
        'iosStructuralDiff.transforms contains unsupported transform: '
        '$transform.',
      );
    }
  }
  return transforms;
}

List<String> _readHelperNameTemplates(Map<String, dynamic> json) {
  final templates = _readStringList(
    json,
    'helperNameTemplates',
    _defaultHelperNameTemplates,
    allowEmpty: false,
  );
  final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  for (final template in templates) {
    final sample = template.replaceAll('{Index}', '0').replaceAll(
          '{Kind}',
          'Bridge',
        );
    if (!identifier.hasMatch(sample)) {
      throw StateError(
        'iosStructuralDiff.helperNameTemplates must render identifiers.',
      );
    }
  }
  return templates;
}

bool _globMatches(String pattern, String path) {
  var source = RegExp.escape(pattern.replaceAll(r'\', '/'));
  source = source.replaceAll(r'\*\*/', '(?:.*/)?');
  source = source.replaceAll(r'\*\*', '.*');
  source = source.replaceAll(r'\*', '[^/]*');
  return RegExp('^$source\$').hasMatch(path);
}

String? _readUtf8TextOrNull(File file) {
  try {
    return file.readAsStringSync();
  } on FormatException {
    return null;
  }
}

String _relative(String projectPath, String filePath) {
  return p.relative(filePath, from: projectPath).replaceAll(p.separator, '/');
}

String _timestamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}
