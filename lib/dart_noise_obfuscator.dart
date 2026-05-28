import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:path/path.dart' as p;

const _configFileName = 'obfuscate_dart_noise.json';
const _templateName = 'page_sync_class';
const _retainFunctionName = 'obfDartNoiseRetain';
const _importMarker = '// obfuscateflutter: dart-noise import';
const _callMarker = '// obfuscateflutter: dart-noise retain';
const _defaultSnippets = ['widget_empty_page', 'sync_math'];
const _knownSnippets = {
  'widget_empty_page',
  'widget_layout_page',
  'sync_math',
  'sync_string',
  'sync_list',
  'sync_model',
  'sync_enum_switch',
};
const _methodSnippets = {
  'sync_math',
  'sync_string',
  'sync_list',
  'sync_model',
  'sync_enum_switch',
};

void runDartNoiseObfuscation(String projectPath) {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    throw StateError('Project directory not found: $projectPath');
  }

  final config = DartNoiseConfig.load(projectPath);
  final libDir = Directory(p.join(projectPath, 'lib'));
  if (!libDir.existsSync()) {
    throw StateError('lib directory not found in $projectPath');
  }

  final mainFile = File(p.join(libDir.path, 'main.dart'));
  if (!mainFile.existsSync()) {
    throw StateError('lib/main.dart not found in $projectPath');
  }

  final generated = _generateNoiseSource(config, libDir);
  for (final entry in generated.sources.entries) {
    final file = File(p.joinAll([libDir.path, ...entry.key.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }

  final entryRelativePath = generated.entryPath;
  final outputFile =
      File(p.joinAll([libDir.path, ...entryRelativePath.split('/')]));
  final importPath = _posixRelative(outputFile.path, from: libDir.path);
  final generatedFiles =
      generated.sources.keys.map((name) => p.posix.join('lib', name)).toList();
  _injectRetainHook(mainFile, importPath);

  final mappingPath =
      p.join(projectPath, 'dart_noise_mapping_${_timestamp()}.json');
  final mapping = {
    'generated_at': DateTime.now().toIso8601String(),
    'config': config.toJson(),
    'config_file': config.configSource,
    'generated_file': p.posix.join('lib', importPath),
    'generated_files': generatedFiles,
    'main_file': 'lib/main.dart',
    'retain_function': _retainFunctionName,
    'page_classes': generated.pageClasses,
    'dart_classes': generated.dartClasses,
    'methods': generated.methods,
    'snippet_usage': generated.snippetUsage,
  };
  File(mappingPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(mapping),
  );

  Log.log('Dart noise obfuscation complete.');
  Log.log('Generated file: $importPath');
  Log.log('Mapping document: $mappingPath');
}

class DartNoiseConfig {
  DartNoiseConfig({
    required this.pageCount,
    required this.classCount,
    required this.methodCountPerClass,
    required this.template,
    required this.outputDirectory,
    required this.outputDirInConfig,
    required this.snippets,
    required this.snippetWeights,
    required this.customPageTemplates,
    required this.customMethodTemplates,
    required this.configSource,
    required this.garbageFileCountMin,
    required this.garbageFileCountMax,
  });

  final int pageCount;
  final int classCount;
  final int methodCountPerClass;
  final String template;
  final Directory outputDirectory;
  final String outputDirInConfig;
  final List<String> snippets;
  final Map<String, int> snippetWeights;
  final List<NoiseTemplate> customPageTemplates;
  final List<NoiseTemplate> customMethodTemplates;
  final String configSource;
  final int garbageFileCountMin;
  final int garbageFileCountMax;

  static DartNoiseConfig load(String projectPath) {
    final file = _resolveConfigFile(projectPath);
    if (!file.existsSync()) {
      throw StateError('Missing $_configFileName in $projectPath and '
          '${Directory.current.path}.\n'
          'Example: {"pageCount":2,"classCount":2,'
          '"methodCountPerClass":3,"template":"$_templateName",'
          '"outputDir":"lib/dart_noise"}');
    }

    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw StateError('$_configFileName must contain a JSON object.');
    }

    final pageCount = _readBoundedInt(decoded, 'pageCount', 1, 50);
    final classCount = _readBoundedInt(decoded, 'classCount', 1, 100);
    final methodCount = _readBoundedInt(decoded, 'methodCountPerClass', 1, 200);
    final garbageFileCountMin =
        _readOptionalBoundedInt(decoded, 'garbageFileCountMin', 3, 100, 3);
    final garbageFileCountMax = _readOptionalBoundedInt(
      decoded,
      'garbageFileCountMax',
      garbageFileCountMin,
      500,
      garbageFileCountMin,
    );
    final template = decoded['template'];
    if (template != _templateName) {
      throw StateError('Unsupported template: $template. '
          'Only $_templateName is supported.');
    }

    final outputDirValue = decoded['outputDir'] ?? 'lib/dart_noise';
    if (outputDirValue is! String || outputDirValue.trim().isEmpty) {
      throw StateError('outputDir must be a non-empty string.');
    }
    if (p.isAbsolute(outputDirValue)) {
      throw StateError('outputDir must be relative and inside lib.');
    }

    final normalizedOutputDir =
        p.normalize(outputDirValue).replaceAll('\\', p.separator);
    final projectLib = p.normalize(p.join(projectPath, 'lib'));
    final outputPath = normalizedOutputDir == 'lib' ||
            normalizedOutputDir.startsWith('lib${p.separator}')
        ? p.normalize(p.join(projectPath, normalizedOutputDir))
        : p.normalize(p.join(projectLib, normalizedOutputDir));
    if (outputPath == projectLib || !p.isWithin(projectLib, outputPath)) {
      throw StateError('outputDir must be inside lib: $outputDirValue');
    }
    final customTemplates = _readCustomTemplates(decoded);
    final snippets = _readSnippets(decoded, customTemplates);
    final snippetWeights = _readSnippetWeights(
      decoded,
      snippets,
      customTemplates.allIds,
    );

    return DartNoiseConfig(
      pageCount: pageCount,
      classCount: classCount,
      methodCountPerClass: methodCount,
      template: template,
      outputDirectory: Directory(outputPath),
      outputDirInConfig: normalizedOutputDir.replaceAll(p.separator, '/'),
      snippets: snippets,
      snippetWeights: snippetWeights,
      customPageTemplates: customTemplates.pageBodies,
      customMethodTemplates: customTemplates.methodBodies,
      configSource: p.equals(p.dirname(file.path), p.normalize(projectPath))
          ? 'project'
          : 'tool_default',
      garbageFileCountMin: garbageFileCountMin,
      garbageFileCountMax: garbageFileCountMax,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pageCount': pageCount,
      'classCount': classCount,
      'methodCountPerClass': methodCountPerClass,
      'template': template,
      'outputDir': outputDirInConfig,
      'snippets': snippets,
      'snippetWeights': snippetWeights,
      'customTemplates': {
        'pageBodies':
            customPageTemplates.map((template) => template.toJson()).toList(),
        'methodBodies':
            customMethodTemplates.map((template) => template.toJson()).toList(),
      },
      'configSource': configSource,
      'garbageFileCountMin': garbageFileCountMin,
      'garbageFileCountMax': garbageFileCountMax,
    };
  }
}

class NoiseTemplate {
  NoiseTemplate({
    required this.id,
    required this.body,
  });

  final String id;
  final String body;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'body': body,
    };
  }
}

class _CustomTemplates {
  _CustomTemplates({
    required this.pageBodies,
    required this.methodBodies,
  });

  final List<NoiseTemplate> pageBodies;
  final List<NoiseTemplate> methodBodies;

  Set<String> get allIds => {
        ...pageBodies.map((template) => template.id),
        ...methodBodies.map((template) => template.id),
      };
}

File _resolveConfigFile(String projectPath) {
  final projectConfig = File(p.join(projectPath, _configFileName));
  if (projectConfig.existsSync()) return projectConfig;
  return File(p.join(Directory.current.path, _configFileName));
}

String _libRelativeOutputDir(DartNoiseConfig config) {
  final outputDir = config.outputDirInConfig;
  if (outputDir == 'lib') return '';
  if (outputDir.startsWith('lib/')) {
    return outputDir.substring('lib/'.length);
  }
  return outputDir;
}

class _GeneratedNoise {
  _GeneratedNoise({
    required this.entryPath,
    required this.source,
    required this.sources,
    required this.pageClasses,
    required this.dartClasses,
    required this.methods,
    required this.snippetUsage,
  });

  final String entryPath;
  final String source;
  final Map<String, String> sources;
  final List<String> pageClasses;
  final List<String> dartClasses;
  final List<String> methods;
  final Map<String, int> snippetUsage;
}

enum _ExtraFileKind {
  page,
  worker,
  shard,
}

class _ContentFile {
  _ContentFile({
    required this.path,
    required this.isPageFile,
    required this.isWorkerFile,
  });

  final String path;
  final bool isPageFile;
  final bool isWorkerFile;
  StringBuffer? _buffer;
  StringBuffer get buffer => _buffer ??= StringBuffer()
    ..writeln('// Generated by obfuscateflutter. Do not edit by hand.');
  int weight = 0;
}

_GeneratedNoise _generateNoiseSource(DartNoiseConfig config, Directory libDir) {
  final pageClasses = <String>[];
  final dartClasses = <String>[];
  final methods = <String>[];
  final snippetUsage = <String, int>{};
  final usedClassNames = <String>{};
  final random = Random();
  final modelClassName = config.snippets.contains('sync_model')
      ? _uniqueClassName('NoiseModel', usedClassNames)
      : null;
  final enumName = config.snippets.contains('sync_enum_switch')
      ? _uniqueClassName('NoiseMode', usedClassNames)
      : null;
  final totalFileCount = _randomInRange(
    random,
    config.garbageFileCountMin,
    config.garbageFileCountMax,
  );
  final directories = _candidateNoiseDirs(config, libDir, totalFileCount);
  final entryPath = _coreFilePath(directories[0], 'entry');

  // ── Plan: distribute pages, workers, and bridge across content files ──
  // Reserve: entry (1) + at least 1 content file. Extra files become shards.
  final pageFileCount = config.pageCount;        // 1 page per file
  final workerFileCount = config.classCount;     // 1 worker per file
  final classFileCount = pageFileCount + workerFileCount;
  final shardFileCount = (totalFileCount - 1 - classFileCount).clamp(0, 999999);
  final allContentFileCount = classFileCount + shardFileCount;
  final bridgePath = allContentFileCount > 0
      ? _coreFilePath(directories[0], 'bridge')
      : _coreFilePath(directories[0], 'worker');

  // Build content file descriptors
  final contentFiles = <_ContentFile>[];
  final dirCycle = directories.length > 1 ? directories.sublist(1) : directories;
  var dirIdx = 0;
  for (var i = 0; i < pageFileCount; i++) {
    contentFiles.add(_ContentFile(
      path: _typedFilePath(dirCycle[dirIdx % dirCycle.length], _ExtraFileKind.page),
      isPageFile: true,
      isWorkerFile: false,
    ));
    dirIdx++;
  }
  for (var i = 0; i < workerFileCount; i++) {
    contentFiles.add(_ContentFile(
      path: _typedFilePath(dirCycle[dirIdx % dirCycle.length], _ExtraFileKind.worker),
      isPageFile: false,
      isWorkerFile: true,
    ));
    dirIdx++;
  }
  for (var i = 0; i < shardFileCount; i++) {
    contentFiles.add(_ContentFile(
      path: _typedFilePath(dirCycle[dirIdx % dirCycle.length], _ExtraFileKind.shard),
      isPageFile: false,
      isWorkerFile: false,
    ));
    dirIdx++;
  }

  // ── 1. Generate page classes, distribute round-robin across page files ──
  final methodSnippetPlan = _methodSnippetPlan(config);
  var methodIndex = 0;
  var pageFileIdx = 0;
  for (var i = 0; i < config.pageCount; i++) {
    final className = _uniqueClassName('NoisePage', usedClassNames);
    final pageSnippet = _pickPageSnippet(config, random);
    _countSnippet(snippetUsage, pageSnippet);
    pageClasses.add(className);
    final targetFile = contentFiles[pageFileIdx % pageFileCount];
    pageFileIdx++;

    targetFile.buffer
      ..writeln("import 'package:flutter/widgets.dart';")
      ..writeln("import '${_relativeImport(targetFile.path, bridgePath)}';")
      ..writeln();
    _writePageClass(targetFile.buffer, className, pageSnippet, random, config);
    targetFile.weight += 2;
  }

  // ── 2. Model + enum go into first worker file ──
  final firstWorkerFile = contentFiles.firstWhere(
    (f) => f.isWorkerFile,
    orElse: () => contentFiles.first,
  );
  if (modelClassName != null) {
    firstWorkerFile.buffer.write(_modelClass(modelClassName));
  }
  if (enumName != null) {
    firstWorkerFile.buffer.write(_enumDeclaration(enumName));
  }

  // Other worker files import the first worker file to access model/enum types
  if ((modelClassName != null || enumName != null) && workerFileCount > 1) {
    for (final f in contentFiles.where((f) => f.isWorkerFile)) {
      if (f != firstWorkerFile) {
        f.buffer
          ..writeln("import '${_relativeImport(f.path, firstWorkerFile.path)}';")
          ..writeln();
      }
    }
  }

  // ── 3. Generate worker classes, distribute round-robin across worker files ──
  final classMethodNames = <String, List<String>>{};
  final pageFileCountVal = pageFileCount;
  for (var i = 0; i < config.classCount; i++) {
    final className = _uniqueClassName('NoiseWorker', usedClassNames);
    dartClasses.add(className);
    final seed = random.nextInt(1 << 20) + 1;
    final methodNames = <String>[];
    final usedMethodNames = <String>{};
    classMethodNames[className] = methodNames;

    final targetFile = contentFiles[pageFileCountVal + (i % workerFileCount)];
    final buf = targetFile.buffer;
    buf
      ..writeln('class $className {')
      ..writeln('  const $className([this.seed = $seed]);')
      ..writeln()
      ..writeln('  final int seed;')
      ..writeln();

    for (var j = 0; j < config.methodCountPerClass; j++) {
      final methodName = _uniqueMethodName(usedMethodNames);
      methodNames.add(methodName);
      methods.add('$className.$methodName');
      final salt = random.nextInt(1 << 20) + 1;
      final shift = random.nextInt(12) + 1;
      final methodSnippet =
          methodSnippetPlan[methodIndex++ % methodSnippetPlan.length];
      _countSnippet(snippetUsage, methodSnippet);
      buf
        ..writeln('  int $methodName(int input) {')
        ..write(_methodBody(
          methodSnippet, salt, shift, modelClassName, enumName, config,
        ))
        ..writeln('  }')
        ..writeln();
    }
    buf
      ..writeln('}')
      ..writeln();
    targetFile.weight += 4;
  }

  // ── 4. Fill shard-only files with multi-function content ──
  for (final file in contentFiles.where((f) => !f.isPageFile && !f.isWorkerFile)) {
    _writeMultiShard(file.buffer, file.path, random);
    file.weight += 3;
  }

  // ── 5. Build bridge file (single file, all imports before code) ──
  final bridgeBuf = StringBuffer()
    ..writeln('// Generated by obfuscateflutter. Do not edit by hand.')
    ..writeln("import 'package:flutter/widgets.dart';");
  for (final f in contentFiles.where((f) => f.isPageFile)) {
    bridgeBuf.writeln("import '${_relativeImport(bridgePath, f.path)}';");
  }
  for (final f in contentFiles.where((f) => f.isWorkerFile)) {
    bridgeBuf.writeln("import '${_relativeImport(bridgePath, f.path)}';");
  }
  bridgeBuf
    ..writeln()
    ..writeln('int dartNoisePageBridge(int input) {')
    ..writeln('  var checksum = input;');
  for (final pageClass in pageClasses) {
    bridgeBuf.writeln('  checksum ^= $pageClass.noiseLink(checksum);');
  }
  bridgeBuf
    ..writeln('  return checksum;')
    ..writeln('}')
    ..writeln()
    ..writeln('int dartNoiseWorkerBridge(int input) {')
    ..writeln('  var checksum = input;');
  for (final className in dartClasses) {
    bridgeBuf
      ..writeln('  const ${_instanceName(className)} = $className();')
      ..writeln('  checksum += ${_instanceName(className)}.seed;');
    for (final methodName in classMethodNames[className]!) {
      bridgeBuf.writeln(
          '  checksum ^= ${_instanceName(className)}.$methodName(checksum);');
    }
  }
  bridgeBuf
    ..writeln('  return checksum;')
    ..writeln('}')
    ..writeln();

  // ── 6. Build entry file ──
  final entryBuffer = StringBuffer()
    ..writeln('// Generated by obfuscateflutter. Do not edit by hand.')
    ..writeln("import '${_relativeImport(entryPath, bridgePath)}';");
  for (final file in contentFiles) {
    entryBuffer.writeln("import '${_relativeImport(entryPath, file.path)}';");
  }
  entryBuffer.writeln();

  // Collect shard entry-point function names
  final extraFuncNames = <String>[];
  for (final file in contentFiles.where((f) => !f.isPageFile && !f.isWorkerFile)) {
    extraFuncNames.add(_shardFuncName(file.path));
  }

  entryBuffer
    ..writeln('Object? $_retainFunctionName() {')
    ..writeln('  final pageFactories = <Object Function()>[');
  for (final pageClass in pageClasses) {
    entryBuffer.writeln('    () => const $pageClass(),');
  }
  entryBuffer
    ..writeln('  ];')
    ..writeln('  var checksum = pageFactories.length;')
    ..writeln('  checksum ^= dartNoisePageBridge(checksum);')
    ..writeln('  checksum ^= dartNoiseWorkerBridge(checksum);');
  for (final funcName in extraFuncNames) {
    entryBuffer.writeln('  checksum ^= $funcName(checksum);');
  }
  entryBuffer
    ..writeln('  if (checksum == -1 && pageFactories.isNotEmpty) {')
    ..writeln('    return pageFactories.first();')
    ..writeln('  }')
    ..writeln('  return checksum;')
    ..writeln('}')
    ..writeln();

  // ── 7. Assemble sources ──
  final sources = <String, String>{};
  sources[entryPath] = entryBuffer.toString();
  sources[bridgePath] = bridgeBuf.toString();
  for (final file in contentFiles) {
    sources[file.path] = file.buffer.toString();
  }

  return _GeneratedNoise(
    entryPath: entryPath,
    source: entryBuffer.toString(),
    sources: sources,
    pageClasses: pageClasses,
    dartClasses: dartClasses,
    methods: methods,
    snippetUsage: snippetUsage,
  );
}

void _injectRetainHook(File mainFile, String importPath) {
  final source = mainFile.readAsStringSync();
  final importLine = "import '$importPath'; $_importMarker";
  var updated = source;
  if (!updated.contains(_importMarker) && !updated.contains(importLine)) {
    final unit = parseString(content: updated).unit;
    final offset = _importInsertOffset(unit);
    final prefix = offset == 0 ? '$importLine\n\n' : '\n$importLine';
    updated = updated.replaceRange(offset, offset, prefix);
  }

  if (!updated.contains(_callMarker)) {
    final unit = parseString(content: updated).unit;
    final mainFunction =
        unit.declarations.whereType<FunctionDeclaration>().where(
      (declaration) {
        return declaration.name.lexeme == 'main';
      },
    ).firstOrNull;
    final body = mainFunction?.functionExpression.body;
    if (mainFunction == null || body is! BlockFunctionBody) {
      throw StateError(
          'Cannot safely inject dart noise hook into lib/main.dart. '
          'Expected a block-bodied main() function.');
    }
    final insertOffset = body.block.leftBracket.end;
    updated = updated.replaceRange(
      insertOffset,
      insertOffset,
      '\n  $_retainFunctionName(); $_callMarker',
    );
  }

  mainFile.writeAsStringSync(updated);
}

int _importInsertOffset(CompilationUnit unit) {
  if (unit.directives.isEmpty) return 0;
  final nonPartDirectives =
      unit.directives.where((directive) => directive is! PartDirective);
  return nonPartDirectives.isEmpty ? 0 : nonPartDirectives.last.end;
}

int _readBoundedInt(
  Map<String, dynamic> json,
  String key,
  int min,
  int max,
) {
  final value = json[key];
  if (value is! int || value < min || value > max) {
    throw StateError('$key must be an integer from $min to $max.');
  }
  return value;
}

int _readOptionalBoundedInt(
  Map<String, dynamic> json,
  String key,
  int min,
  int max,
  int defaultValue,
) {
  if (!json.containsKey(key)) return defaultValue;
  return _readBoundedInt(json, key, min, max);
}

_CustomTemplates _readCustomTemplates(Map<String, dynamic> json) {
  final value = json['customTemplates'];
  if (value == null) {
    return _CustomTemplates(pageBodies: [], methodBodies: []);
  }
  if (value is! Map<String, dynamic>) {
    throw StateError('customTemplates must be a JSON object.');
  }
  final pageBodies = _readTemplateList(value, 'pageBodies');
  final methodBodies = _readTemplateList(value, 'methodBodies');
  final ids = <String>{};
  for (final template in [...pageBodies, ...methodBodies]) {
    if (_knownSnippets.contains(template.id)) {
      throw StateError('custom template id conflicts with built-in snippet: '
          '${template.id}.');
    }
    if (!ids.add(template.id)) {
      throw StateError('Duplicate custom template id: ${template.id}.');
    }
  }
  return _CustomTemplates(
    pageBodies: pageBodies,
    methodBodies: methodBodies,
  );
}

List<NoiseTemplate> _readTemplateList(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value == null) return [];
  if (value is! List) {
    throw StateError('customTemplates.$key must be an array.');
  }
  return value.map((item) {
    if (item is! Map<String, dynamic>) {
      throw StateError('customTemplates.$key entries must be objects.');
    }
    final id = item['id'];
    final body = item['body'];
    if (id is! String || !_isIdentifier(id)) {
      throw StateError('customTemplates.$key.id must be an identifier.');
    }
    if (body is! String || body.trim().isEmpty) {
      throw StateError('customTemplates.$key.body must be a non-empty string.');
    }
    _validateTemplateBody(id, body);
    return NoiseTemplate(id: id, body: body);
  }).toList();
}

List<String> _readSnippets(
  Map<String, dynamic> json,
  _CustomTemplates customTemplates,
) {
  final value = json['snippets'];
  if (value == null) return List<String>.from(_defaultSnippets);
  if (value is! List || value.isEmpty) {
    throw StateError('snippets must be a non-empty string array.');
  }
  final snippets = <String>[];
  for (final item in value) {
    if (item is! String ||
        (!_knownSnippets.contains(item) &&
            !customTemplates.allIds.contains(item))) {
      throw StateError('Unsupported dart noise snippet: $item.');
    }
    if (!snippets.contains(item)) snippets.add(item);
  }
  if (!snippets.any((snippet) => _isMethodSnippet(snippet, customTemplates))) {
    throw StateError('snippets must include at least one sync_* snippet.');
  }
  return snippets;
}

bool _isMethodSnippet(String snippet, _CustomTemplates customTemplates) {
  return _methodSnippets.contains(snippet) ||
      customTemplates.methodBodies.any((template) => template.id == snippet);
}

Map<String, int> _readSnippetWeights(
  Map<String, dynamic> json,
  List<String> snippets,
  Set<String> customSnippetIds,
) {
  final weights = {for (final snippet in snippets) snippet: 1};
  final value = json['snippetWeights'];
  if (value == null) return weights;
  if (value is! Map<String, dynamic>) {
    throw StateError('snippetWeights must be a JSON object.');
  }
  for (final entry in value.entries) {
    if (!_knownSnippets.contains(entry.key) &&
        !customSnippetIds.contains(entry.key)) {
      throw StateError('Unsupported snippet weight key: ${entry.key}.');
    }
    if (!snippets.contains(entry.key)) continue;
    final weight = entry.value;
    if (weight is! int || weight < 1 || weight > 20) {
      throw StateError('snippetWeights.${entry.key} must be from 1 to 20.');
    }
    weights[entry.key] = weight;
  }
  return weights;
}

String _pickPageSnippet(DartNoiseConfig config, Random random) {
  final customPageIds =
      config.customPageTemplates.map((template) => template.id).toSet();
  final pageSnippets = config.snippets.where((snippet) {
    return snippet == 'widget_layout_page' || customPageIds.contains(snippet);
  }).toList();
  if (pageSnippets.isEmpty) return 'widget_empty_page';

  final weighted = <String>[];
  for (final snippet in pageSnippets) {
    final weight = config.snippetWeights[snippet] ?? 1;
    for (var i = 0; i < weight; i++) {
      weighted.add(snippet);
    }
  }
  return weighted[random.nextInt(weighted.length)];
}

List<String> _methodSnippetPlan(DartNoiseConfig config) {
  final plan = <String>[];
  for (final snippet in config.snippets.where((snippet) {
    return _methodSnippets.contains(snippet) ||
        config.customMethodTemplates.any((template) => template.id == snippet);
  })) {
    final weight = config.snippetWeights[snippet] ?? 1;
    for (var i = 0; i < weight; i++) {
      plan.add(snippet);
    }
  }
  return plan.isEmpty ? ['sync_math'] : plan;
}

String _pageBody(String snippet, Random random, DartNoiseConfig config) {
  final customTemplate = _findTemplate(config.customPageTemplates, snippet);
  if (customTemplate != null) {
    return _indentBlock(
      _renderTemplate(customTemplate.body, {
        'width': '${random.nextInt(80) + 12}',
        'height': '${random.nextInt(80) + 12}',
        'padding': '${random.nextInt(12) + 1}',
      }),
      '    ',
    );
  }
  if (snippet == 'widget_layout_page') {
    final width = random.nextInt(80) + 12;
    final height = random.nextInt(80) + 12;
    final padding = random.nextInt(12) + 1;
    return '''
    return const Padding(
      padding: EdgeInsets.all($padding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: $width, height: $height),
          SizedBox(width: $height, height: $width),
        ],
      ),
    );
''';
  }
  return '    return const SizedBox.shrink();\n';
}

String _modelClass(String className) {
  return '''
class $className {
  const $className(this.value, this.count, this.label);

  final int value;
  final int count;
  final String label;

  $className copyWith({int? value, int? count, String? label}) {
    return $className(
      value ?? this.value,
      count ?? this.count,
      label ?? this.label,
    );
  }
}

''';
}

String _enumDeclaration(String enumName) {
  return '''
enum $enumName {
  alpha,
  beta,
  gamma,
}

''';
}

String _methodBody(
  String snippet,
  int salt,
  int shift,
  String? modelClassName,
  String? enumName,
  DartNoiseConfig config,
) {
  final customTemplate = _findTemplate(config.customMethodTemplates, snippet);
  if (customTemplate != null) {
    return _indentBlock(
      _renderTemplate(customTemplate.body, {
        'salt': '$salt',
        'shift': '$shift',
      }),
      '    ',
    );
  }
  switch (snippet) {
    case 'sync_string':
      return '''
    final text = 'n$salt\$input\$seed';
    return text.codeUnits.fold(seed, (acc, unit) {
      return ((acc + unit + $salt) ^ (unit << ${shift % 6 + 1})) & 0x3fffffff;
    });
''';
    case 'sync_list':
      return '''
    final values = List<int>.generate(
      ${shift % 5 + 3},
      (index) => input + seed + index + $salt,
    );
    return values.fold(0, (acc, value) {
      return ((acc ^ value) + $salt) & 0x3fffffff;
    });
''';
    case 'sync_model':
      return '''
    final model = $modelClassName(input + $salt, seed, 'm$salt');
    final changed = model.copyWith(value: model.value ^ model.count);
    return (changed.value + changed.count + changed.label.length) & 0x3fffffff;
''';
    case 'sync_enum_switch':
      return '''
    final mode = $enumName.values[(input + seed).abs() % $enumName.values.length];
    switch (mode) {
      case $enumName.alpha:
        return (input + seed + $salt) & 0x3fffffff;
      case $enumName.beta:
        return ((input ^ seed) + $salt) & 0x3fffffff;
      case $enumName.gamma:
        return ((input + $salt) ^ (seed << ${shift % 6 + 1})) & 0x3fffffff;
    }
''';
    case 'sync_math':
    default:
      return '''
    final mixed = input + seed + $salt;
    return ((mixed ^ (mixed << $shift)) & 0x3fffffff);
''';
  }
}

void _countSnippet(Map<String, int> usage, String snippet) {
  usage[snippet] = (usage[snippet] ?? 0) + 1;
}

NoiseTemplate? _findTemplate(List<NoiseTemplate> templates, String id) {
  for (final template in templates) {
    if (template.id == id) return template;
  }
  return null;
}

String _renderTemplate(String body, Map<String, String> values) {
  var rendered = body.trim();
  values.forEach((key, value) {
    rendered = rendered.replaceAll('{{$key}}', value);
  });
  return rendered;
}

String _indentBlock(String source, String indent) {
  final lines = source.trim().split('\n');
  return '${lines.map((line) {
    final trimmedRight = line.trimRight();
    if (trimmedRight.isEmpty) return '';
    return '$indent$trimmedRight';
  }).join('\n')}\n';
}

void _validateTemplateBody(String id, String body) {
  final forbiddenPatterns = [
    RegExp(r'\bFuture\b'),
    RegExp(r'\bStream\b'),
    RegExp(r'\basync\b'),
    RegExp(r'\bawait\b'),
    RegExp(r'\bTimer\b'),
    RegExp(r'\bimport\b'),
    RegExp(r'\bexport\b'),
    RegExp(r'\bpart\b'),
    RegExp(r'dart:io'),
    RegExp(r'dart:async'),
    RegExp(r'@pragma'),
  ];
  for (final pattern in forbiddenPatterns) {
    if (pattern.hasMatch(body)) {
      throw StateError('custom template $id contains forbidden code: '
          '${pattern.pattern}.');
    }
  }
}

bool _isIdentifier(String value) {
  return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
}

int _randomInRange(Random random, int min, int max) {
  if (min == max) return min;
  return min + random.nextInt(max - min + 1);
}

void _writePageClass(StringBuffer buf, String className, String snippet,
    Random random, DartNoiseConfig config) {
  buf
    ..writeln('class $className extends StatelessWidget {')
    ..writeln('  const $className({super.key});')
    ..writeln()
    ..writeln('  static int noiseLink(int input) {')
    ..writeln(
        '    return dartNoiseWorkerBridge(input + ${random.nextInt(1 << 16) + 1});')
    ..writeln('  }')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  Widget build(BuildContext context) {')
    ..write(_pageBody(snippet, random, config))
    ..writeln('  }')
    ..writeln('}')
    ..writeln();
}

void _writeMultiShard(StringBuffer buf, String filePath, Random random) {
  final count = 4 + random.nextInt(4); // 4-7 internal functions
  final baseName = _shardFuncName(filePath);
  buf.writeln();
  for (var i = 0; i < count; i++) {
    final salt = random.nextInt(1 << 20) + 1;
    final shift = random.nextInt(8) + 1;
    buf
      ..writeln('int ${baseName}_$i(int input) {')
      ..writeln('  final mixed = input + $salt;')
      ..writeln('  final folded = (mixed ^ (mixed << $shift)) & 0x3fffffff;')
      ..writeln('  return (folded + $salt + input) & 0x3fffffff;')
      ..writeln('}')
      ..writeln();
  }
  // Public entry-point chains all internal functions (prevents tree shaking)
  buf
    ..writeln('int $baseName(int input) {')
    ..writeln('  var checksum = input;');
  for (var i = 0; i < count; i++) {
    buf.writeln('  checksum ^= ${baseName}_$i(checksum);');
  }
  buf
    ..writeln('  return checksum;')
    ..writeln('}')
    ..writeln();
}

String _shardFuncName(String filePath) {
  final base = p.posix.basenameWithoutExtension(filePath);
  // Sanitize: remove non-identifier chars, ensure starts with letter
  final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  return cleaned.isEmpty
      ? 'dartNoiseShardF'
      : cleaned.startsWith('_') || RegExp(r'^[A-Za-z]').hasMatch(cleaned)
          ? cleaned
          : '_$cleaned';
}

List<String> _candidateNoiseDirs(
  DartNoiseConfig config,
  Directory libDir,
  int extraCount,
) {
  final outputDir = _libRelativeOutputDir(config);
  final existingDirs = libDir
      .listSync(recursive: true)
      .whereType<Directory>()
      .map((dir) => _posixRelative(dir.path, from: libDir.path))
      .where((dir) => dir.isNotEmpty)
      .where((dir) => !dir.split('/').any((part) => part.startsWith('.')))
      .where((dir) => outputDir.isEmpty || !dir.startsWith(outputDir))
      .toList()
    ..sort((a, b) {
      final depthCompare = b.split('/').length.compareTo(a.split('/').length);
      if (depthCompare != 0) return depthCompare;
      return a.compareTo(b);
    });
  final directories = <String>[
    ...existingDirs,
  ];
  final neededDirs = max(1, (extraCount / 2).ceil());
  while (directories.length < neededDirs) {
    final randomDir = p.posix.join(genRandomKey(8), genRandomKey(8));
    if (outputDir.isEmpty || !randomDir.startsWith(outputDir)) {
      directories.add(randomDir);
    }
  }
  return directories;
}

String _coreFilePath(String dir, String role) {
  return p.posix
      .join(dir, '${_semanticPrefix(dir, role)}_${genRandomKey(10)}.dart');
}

String _typedFilePath(String dir, _ExtraFileKind kind) {
  final role = switch (kind) {
    _ExtraFileKind.page => 'view',
    _ExtraFileKind.worker => 'state',
    _ExtraFileKind.shard => 'util',
  };
  return p.posix
      .join(dir, '${_semanticPrefix(dir, role)}_${genRandomKey(10)}.dart');
}

String _semanticPrefix(String dir, String role) {
  final segments = dir.split('/');
  if (segments.contains('config')) return 'config';
  if (segments.contains('cache')) return 'cache';
  if (segments.contains('http') || segments.contains('api')) return 'client';
  if (segments.contains('navigation')) return 'route';
  if (segments.contains('theme') || segments.contains('ui')) return 'style';
  if (segments.contains('widgets')) return 'widget';
  if (segments.contains('home')) return 'state';
  if (segments.contains('settings')) return 'setting';
  if (segments.contains('auth')) return 'session';
  if (segments.contains('support')) return 'support';
  if (segments.contains('web')) return 'bridge';
  if (segments.contains('data')) return 'model';
  if (segments.contains('managers')) return 'manager';
  if (segments.contains('core')) return 'core';
  if (segments.contains('features')) return 'feature';
  return role;
}

String _relativeImport(String fromFile, String toFile) {
  final fromDir = p.posix.dirname(fromFile);
  return p.posix.relative(toFile, from: fromDir);
}

String _uniqueClassName(String prefix, Set<String> usedNames) {
  while (true) {
    final name = '$prefix${genRandomKey(10)}';
    if (usedNames.add(name)) return name;
  }
}

String _methodName() => 'm${genRandomKey(10)}';

String _uniqueMethodName(Set<String> usedNames) {
  while (true) {
    final name = _methodName();
    if (usedNames.add(name)) return name;
  }
}

String _instanceName(String className) => '_${className[0].toLowerCase()}'
    '${className.substring(1)}';

String _posixRelative(String fullPath, {required String from}) {
  return p.relative(fullPath, from: from).replaceAll(p.separator, '/');
}

String _timestamp() {
  final now = DateTime.now();
  return '${now.year}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}_'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}'
      '${now.millisecond.toString().padLeft(3, '0')}';
}
