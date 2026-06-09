import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/log.dart';
import 'package:path/path.dart' as p;

const _configFileName = 'obfuscate_dart_noise.json';
const _marker = 'obfuscateflutter: ios-noise';
const _defaultObjectiveCTemplates = [
  'oc_string_table',
  'oc_numeric_fold',
  'oc_guarded_branch',
];
const _defaultSwiftTemplates = [
  'swift_string_table',
  'swift_numeric_fold',
  'swift_guarded_branch',
];
const _defaultSkipFiles = [
  '**/Pods/**',
  '**/.symlinks/**',
  '**/Flutter/**',
  '**/GeneratedPluginRegistrant.*',
  '**/build/**',
  '**/*.pbobjc.*',
];
const _defaultStringTemplates = [
  {'id': 'session_word_seed', 'value': 'session.{{word}}.{{seed}}'},
  {
    'id': 'trace_context',
    'value': 'trace.{{fileName}}.{{methodName}}.{{index}}',
  },
];
final _identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

enum IosLanguage { objectiveC, objectiveCpp, swift }

typedef IosProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

class IosSourceFile {
  IosSourceFile({
    required this.file,
    required this.relativePath,
    required this.language,
    required this.injectable,
  });

  final File file;
  final String relativePath;
  final IosLanguage language;
  final bool injectable;
}

class IosAstResult {
  IosAstResult({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.targets,
    required this.warnings,
  });

  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;
  final List<IosInsertionTarget> targets;
  final List<String> warnings;
}

class IosInsertionTarget {
  IosInsertionTarget({
    required this.containerName,
    required this.methodName,
    required this.bodyStartOffset,
    required this.bodyEndOffset,
    required this.insertionOffset,
    required this.isStaticLike,
  });

  final String containerName;
  final String methodName;
  final int bodyStartOffset;
  final int bodyEndOffset;
  final int insertionOffset;
  final bool isStaticLike;
}

class IosNoiseConfig {
  IosNoiseConfig({
    required this.enabled,
    required this.targetRatio,
    required this.maxTargetLines,
    required this.maxInsertionsPerFile,
    required this.astFallback,
    required this.skipFiles,
    required this.objectiveCTemplates,
    required this.swiftTemplates,
    required this.stringTemplates,
    required this.configSource,
  });

  final bool enabled;
  final double targetRatio;
  final int maxTargetLines;
  final int maxInsertionsPerFile;
  final String astFallback;
  final List<String> skipFiles;
  final List<String> objectiveCTemplates;
  final List<String> swiftTemplates;
  final List<IosStringTemplate> stringTemplates;
  final String configSource;

  static IosNoiseConfig load(String projectPath) {
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

    final value = decoded['iosNoise'];
    if (value == null) return _defaults(source);
    if (value is! Map<String, dynamic>) {
      throw StateError('iosNoise must be a JSON object.');
    }

    final enabled = value['enabled'];
    if (enabled != null && enabled is! bool) {
      throw StateError('iosNoise.enabled must be a boolean.');
    }

    final ratio = value['targetRatio'] ?? 0.4;
    if (ratio is! num || ratio <= 0 || ratio > 3) {
      throw StateError('iosNoise.targetRatio must be from 0 to 3.');
    }

    final fallback = value['astFallback'] ?? 'skip';
    if (fallback is! String || fallback != 'skip') {
      throw StateError('iosNoise.astFallback only supports skip.');
    }

    final groups = value['templateGroups'];
    if (groups != null && groups is! Map<String, dynamic>) {
      throw StateError('iosNoise.templateGroups must be a JSON object.');
    }
    final groupJson = groups ?? <String, dynamic>{};

    return IosNoiseConfig(
      enabled: enabled ?? true,
      targetRatio: ratio.toDouble(),
      maxTargetLines:
          _readOptionalBoundedInt(value, 'maxTargetLines', 20, 500000, 20000),
      maxInsertionsPerFile:
          _readOptionalBoundedInt(value, 'maxInsertionsPerFile', 1, 200, 20),
      astFallback: fallback,
      skipFiles: _readStringList(value, 'skipFiles', _defaultSkipFiles),
      objectiveCTemplates: _readTemplateIds(
          groupJson, 'objectiveC', _defaultObjectiveCTemplates),
      swiftTemplates:
          _readTemplateIds(groupJson, 'swift', _defaultSwiftTemplates),
      stringTemplates: _readStringTemplates(value),
      configSource: source,
    );
  }

  static IosNoiseConfig _defaults(String source) {
    return IosNoiseConfig(
      enabled: true,
      targetRatio: 0.4,
      maxTargetLines: 20000,
      maxInsertionsPerFile: 20,
      astFallback: 'skip',
      skipFiles: List<String>.from(_defaultSkipFiles),
      objectiveCTemplates: List<String>.from(_defaultObjectiveCTemplates),
      swiftTemplates: List<String>.from(_defaultSwiftTemplates),
      stringTemplates: _defaultStringTemplates
          .map((item) =>
              IosStringTemplate(id: item['id']!, value: item['value']!))
          .toList(),
      configSource: source,
    );
  }

  bool shouldSkip(String relativePath) {
    final normalized = relativePath.replaceAll(r'\', '/');
    return skipFiles.any((pattern) => _globMatches(pattern, normalized));
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'targetRatio': targetRatio,
        'maxTargetLines': maxTargetLines,
        'maxInsertionsPerFile': maxInsertionsPerFile,
        'astFallback': astFallback,
        'skipFiles': skipFiles,
        'templateGroups': {
          'objectiveC': objectiveCTemplates,
          'swift': swiftTemplates,
        },
        'stringTemplates':
            stringTemplates.map((template) => template.toJson()).toList(),
        'configSource': configSource,
      };
}

class IosStringTemplate {
  IosStringTemplate({required this.id, required this.value});

  final String id;
  final String value;

  Map<String, dynamic> toJson() => {'id': id, 'value': value};
}

void runIosNoiseObfuscation(String projectPath) {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    throw StateError('Project directory not found: $projectPath');
  }

  final config = IosNoiseConfig.load(projectPath);
  if (!config.enabled) {
    Log.log('iOS noise obfuscation is disabled by config.');
    return;
  }

  throw UnimplementedError('iOS noise obfuscation is not implemented yet.');
}

List<IosSourceFile> discoverIosSourceFiles(
  String projectPath,
  IosNoiseConfig config,
) {
  final iosDir = Directory(p.join(projectPath, 'ios'));
  if (!iosDir.existsSync()) {
    throw StateError('ios directory not found in $projectPath');
  }

  final files = iosDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) {
        final relative = p
            .relative(file.path, from: projectPath)
            .replaceAll(p.separator, '/');
        final extension = p.extension(file.path);
        final language = switch (extension) {
          '.m' => IosLanguage.objectiveC,
          '.mm' => IosLanguage.objectiveCpp,
          '.h' => IosLanguage.objectiveC,
          '.swift' => IosLanguage.swift,
          _ => null,
        };
        if (language == null || config.shouldSkip(relative)) return null;
        return IosSourceFile(
          file: file,
          relativePath: relative,
          language: language,
          injectable: extension != '.h',
        );
      })
      .whereType<IosSourceFile>()
      .toList()
    ..sort((a, b) => a.relativePath.compareTo(b.relativePath));

  return files;
}

String renderIosNoiseTemplate({
  required IosLanguage language,
  required String templateId,
  required String fileName,
  required String methodName,
  required int index,
  required int seed,
  required IosStringTemplate stringTemplate,
}) {
  final supported = switch (language) {
    IosLanguage.swift => templateId.startsWith('swift_'),
    IosLanguage.objectiveC ||
    IosLanguage.objectiveCpp =>
      templateId.startsWith('oc_'),
  };
  if (!supported) {
    throw StateError('Unsupported iOS template: $templateId');
  }

  final text = _renderStringTemplate(
    stringTemplate.value,
    fileName: fileName,
    methodName: methodName,
    index: index,
    seed: seed,
  );
  final literalText = _escapeIosStringLiteral(text);
  final literalId = _escapeIosStringLiteral(stringTemplate.id);

  return switch (templateId) {
    'oc_string_table' => _marked(templateId, '''
NSString *obfIosText$index = @"$literalText";
NSArray *obfIosList$index = @[obfIosText$index, @"$literalId"];
NSDictionary *obfIosMap$index = @{@"k": obfIosText$index, @"m": [obfIosList$index firstObject] ?: @""};
if ([obfIosMap$index count] == 912347) { NSLog(@"%@", obfIosMap$index); }
'''),
    'oc_numeric_fold' => _marked(templateId, '''
NSInteger obfIosSeed$index = $seed;
obfIosSeed$index = ((obfIosSeed$index << 2) ^ ${seed + index}) & 0x7fffffff;
if (obfIosSeed$index == -1) { NSLog(@"%ld", (long)obfIosSeed$index); }
'''),
    'oc_guarded_branch' => _marked(templateId, '''
NSInteger obfIosGuard$index = $seed + $index;
if (obfIosGuard$index >= 0) {
  obfIosGuard$index = (obfIosGuard$index * 31) % 9973;
} else {
  obfIosGuard$index = 0;
}
'''),
    'swift_string_table' => _marked(templateId, '''
let obfIosText$index = "$literalText"
let obfIosList$index = [obfIosText$index, "$literalId"]
let obfIosMap$index = ["k": obfIosText$index, "m": obfIosList$index.first ?? ""]
if obfIosMap$index.count == 912347 { print(obfIosMap$index) }
'''),
    'swift_numeric_fold' => _marked(templateId, '''
var obfIosSeed$index = $seed
obfIosSeed$index = ((obfIosSeed$index << 2) ^ ${seed + index}) & 0x7fffffff
if obfIosSeed$index == -1 { print(obfIosSeed$index) }
'''),
    'swift_guarded_branch' => _marked(templateId, '''
var obfIosGuard$index = $seed + $index
if obfIosGuard$index >= 0 {
  obfIosGuard$index = (obfIosGuard$index * 31) % 9973
} else {
  obfIosGuard$index = 0
}
'''),
    _ => throw StateError('Unsupported iOS template: $templateId'),
  };
}

Future<bool> iosAstToolsAvailable() {
  return iosAstToolsAvailableWithRunner(Process.run);
}

Future<bool> iosAstToolsAvailableWithRunner(IosProcessRunner runner) async {
  try {
    final clang = await runner('xcrun', ['--find', 'clang']);
    if (clang.exitCode != 0) return false;

    final swiftc = await runner('xcrun', ['--find', 'swiftc']);
    return swiftc.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<IosAstResult> readIosAstTargets(IosSourceFile sourceFile) async {
  final args = switch (sourceFile.language) {
    IosLanguage.objectiveC => [
        'clang',
        '-x',
        'objective-c',
        '-fsyntax-only',
        ...await _clangSdkArgs(),
        '-Xclang',
        '-ast-dump=json',
        sourceFile.file.path,
      ],
    IosLanguage.objectiveCpp => [
        'clang',
        '-x',
        'objective-c++',
        '-fsyntax-only',
        ...await _clangSdkArgs(),
        '-Xclang',
        '-ast-dump=json',
        sourceFile.file.path,
      ],
    IosLanguage.swift => [
        'swiftc',
        '-dump-ast',
        '-parse',
        sourceFile.file.path,
      ],
  };

  final result = await Process.run('xcrun', args);
  final stdout = '${result.stdout}';
  final stderr = '${result.stderr}';
  final source = sourceFile.file.readAsStringSync();
  final warnings = <String>[];
  final targets = <IosInsertionTarget>[];

  if (!sourceFile.injectable) {
    warnings.add('Source file is not injectable.');
  } else if (source.contains(_marker)) {
    warnings.add('Source file already contains iOS noise markers.');
  } else if (result.exitCode == 0) {
    targets.addAll(switch (sourceFile.language) {
      IosLanguage.objectiveC ||
      IosLanguage.objectiveCpp =>
        _findObjectiveCInsertionTargets(source),
      IosLanguage.swift => _findSwiftInsertionTargets(source),
    });
  }

  return IosAstResult(
    command: _shellCommand(['xcrun', ...args]),
    exitCode: result.exitCode,
    stdout: stdout,
    stderr: stderr,
    targets: targets,
    warnings: warnings,
  );
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
    throw StateError('iosNoise.$key must be from $min to $max.');
  }
  return value;
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
    throw StateError('iosNoise.$key must be a non-empty string array.');
  }
  return value.cast<String>();
}

List<String> _readTemplateIds(
  Map<String, dynamic> json,
  String key,
  List<String> defaults,
) {
  final values = _readStringList(json, key, defaults);
  if (values.isEmpty) {
    throw StateError('iosNoise.templateGroups.$key must not be empty.');
  }
  final known = key == 'objectiveC'
      ? _defaultObjectiveCTemplates
      : _defaultSwiftTemplates;
  for (final value in values) {
    if (!known.contains(value)) {
      throw StateError(
        'iosNoise.templateGroups.$key contains unsupported template: $value.',
      );
    }
  }
  return values;
}

List<IosStringTemplate> _readStringTemplates(Map<String, dynamic> json) {
  final value = json['stringTemplates'];
  final defaults = _defaultStringTemplates
      .map((item) => IosStringTemplate(id: item['id']!, value: item['value']!))
      .toList();
  if (value == null) return defaults;
  if (value is! List) {
    throw StateError('iosNoise.stringTemplates must be an array.');
  }
  if (value.isEmpty) {
    throw StateError('iosNoise.stringTemplates must not be empty.');
  }

  return value.map((item) {
    if (item is! Map<String, dynamic>) {
      throw StateError('iosNoise.stringTemplates entries must be objects.');
    }
    final id = item['id'];
    final template = item['value'];
    if (id is! String || !_identifierPattern.hasMatch(id)) {
      throw StateError('iosNoise.stringTemplates.id must be an identifier.');
    }
    if (template is! String ||
        template.trim().isEmpty ||
        template.contains('\n')) {
      throw StateError(
        'iosNoise.stringTemplates.value must be a single-line string.',
      );
    }
    return IosStringTemplate(id: id, value: template);
  }).toList();
}

bool _globMatches(String pattern, String path) {
  var source = RegExp.escape(pattern.replaceAll(r'\', '/'));
  source = source.replaceAll(r'\*\*/', '(?:.*/)?');
  source = source.replaceAll(r'\*\*', '.*');
  source = source.replaceAll(r'\*', '[^/]*');
  return RegExp('^$source\$').hasMatch(path);
}

String _marked(String templateId, String body) {
  final normalized = body.trimRight();
  return '''
// $_marker start $templateId
$normalized
// $_marker end $templateId
''';
}

String _renderStringTemplate(
  String template, {
  required String fileName,
  required String methodName,
  required int index,
  required int seed,
}) {
  const words = ['signal', 'session', 'profile', 'route', 'cache'];
  return template
      .replaceAll('{{fileName}}', fileName)
      .replaceAll('{{methodName}}', methodName)
      .replaceAll('{{index}}', '$index')
      .replaceAll('{{seed}}', '$seed')
      .replaceAll('{{word}}', words[index % words.length]);
}

String _escapeIosStringLiteral(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
}

Future<List<String>> _clangSdkArgs() async {
  for (final sdk in ['macosx', 'iphoneos']) {
    final result = await Process.run('xcrun', [
      '--sdk',
      sdk,
      '--show-sdk-path',
    ]);
    if (result.exitCode == 0) {
      final sdkPath = '${result.stdout}'.trim();
      if (sdkPath.isNotEmpty) return ['-isysroot', sdkPath];
    }
  }
  return const [];
}

String _shellCommand(List<String> parts) {
  return parts.map((part) {
    if (RegExp(r'^[A-Za-z0-9_./:=+-]+$').hasMatch(part)) return part;
    return "'${part.replaceAll("'", r"'\''")}'";
  }).join(' ');
}

List<IosInsertionTarget> _findObjectiveCInsertionTargets(String source) {
  final targets = <IosInsertionTarget>[];
  final implementationPattern = RegExp(
    r'@implementation\s+([A-Za-z_][A-Za-z0-9_]*)',
    multiLine: true,
  );
  final methodPattern = RegExp(
    r'^[ \t]*([+-])\s*\([^)]*\)\s*([^{;]+)\{',
    multiLine: true,
  );

  for (final implementation in implementationPattern.allMatches(source)) {
    final containerName = implementation.group(1)!;
    final implementationEnd = source.indexOf('@end', implementation.end);
    final searchEnd =
        implementationEnd == -1 ? source.length : implementationEnd;
    for (final method in methodPattern.allMatches(
      source.substring(implementation.end, searchEnd),
    )) {
      final methodStart = implementation.end + method.start;
      final bodyStart = source.indexOf('{', methodStart);
      if (bodyStart == -1 || bodyStart >= searchEnd) continue;
      final bodyEnd = _findMatchingBrace(source, bodyStart);
      if (bodyEnd == -1 || bodyEnd > searchEnd) continue;
      targets.add(IosInsertionTarget(
        containerName: containerName,
        methodName: _objectiveCMethodName(method.group(2) ?? ''),
        bodyStartOffset: bodyStart,
        bodyEndOffset: bodyEnd,
        insertionOffset: bodyStart + 1,
        isStaticLike: method.group(1) == '+',
      ));
    }
  }

  return targets;
}

String _objectiveCMethodName(String signatureRest) {
  final selectorParts = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*:')
      .allMatches(signatureRest)
      .map((match) => match.group(1)!)
      .toList();
  if (selectorParts.isNotEmpty) return '${selectorParts.join(':')}:';

  final name = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)')
      .firstMatch(signatureRest.trim())
      ?.group(1);
  return name ?? '<unknown>';
}

List<IosInsertionTarget> _findSwiftInsertionTargets(String source) {
  final targets = <IosInsertionTarget>[];
  final typePattern = RegExp(
    r'\b(?:class|struct|enum|actor|extension)\s+([A-Za-z_][A-Za-z0-9_]*)',
  );
  final functionPattern = RegExp(
    r'\b(static\s+|class\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)[^{]*\{',
  );

  for (final function in functionPattern.allMatches(source)) {
    final bodyStart = source.indexOf('{', function.start);
    if (bodyStart == -1) continue;
    final bodyEnd = _findMatchingBrace(source, bodyStart);
    if (bodyEnd == -1) continue;
    targets.add(IosInsertionTarget(
      containerName: _swiftContainerName(source, function.start, typePattern),
      methodName: function.group(2)!,
      bodyStartOffset: bodyStart,
      bodyEndOffset: bodyEnd,
      insertionOffset: bodyStart + 1,
      isStaticLike: function.group(1) != null,
    ));
  }

  return targets;
}

String _swiftContainerName(String source, int offset, RegExp typePattern) {
  var containerName = '<global>';
  for (final match in typePattern.allMatches(source.substring(0, offset))) {
    containerName = match.group(1)!;
  }
  return containerName;
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
    if (char == '{') {
      depth++;
      continue;
    }
    if (char == '}') {
      depth--;
      if (depth == 0) return index;
    }
  }

  return -1;
}
