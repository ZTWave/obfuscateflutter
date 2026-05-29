import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:path/path.dart' as p;

const _configFileName = 'obfuscate_dart_noise.json';
const _templateName = 'page_sync_class';
const _retainFunctionName = 'obfDartNoiseRetain';
const _importMarker = '// obfuscateflutter: dart-noise import';
const _callMarker = '// obfuscateflutter: dart-noise retain';
const _classInnerMemberMarker = '// obfuscateflutter: class-inner members';
const _classInnerHookMarker = '// obfuscateflutter: class-inner hook';
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
const _defaultLightweightTemplates = ['sync_hash', 'sync_switch'];
const _defaultRetainedTemplates = [
  'async_future',
  'timer_stub',
  'file_io_stub',
  'network_stub',
  'platform_channel_stub',
  'navigator_stub',
  'set_state_stub',
  'run_app_stub',
  'debug_log_stub',
];
const _knownClassInnerTemplates = {
  'sync_hash',
  'sync_switch',
  'async_future',
  'timer_stub',
  'file_io_stub',
  'network_stub',
  'platform_channel_stub',
  'navigator_stub',
  'set_state_stub',
  'run_app_stub',
  'debug_log_stub',
};
const _classInnerTemplateImports = {
  'async_future': ['dart:async as obf_async'],
  'timer_stub': [
    'dart:async as obf_async',
    'package:flutter/widgets.dart as obf_widgets',
  ],
  'file_io_stub': ['dart:io as obf_io'],
  'network_stub': ['dart:io as obf_io'],
  'platform_channel_stub': ['package:flutter/services.dart as obf_services'],
  'navigator_stub': ['package:flutter/widgets.dart as obf_widgets'],
  'set_state_stub': ['package:flutter/widgets.dart as obf_widgets'],
  'run_app_stub': ['package:flutter/widgets.dart as obf_widgets'],
  'debug_log_stub': ['package:flutter/widgets.dart as obf_widgets'],
};
const _methodSnippets = {
  'sync_math',
  'sync_string',
  'sync_list',
  'sync_model',
  'sync_enum_switch',
};

void runClassInnerNoiseObfuscation(String projectPath) {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    throw StateError('Project directory not found: $projectPath');
  }

  final config = DartNoiseConfig.load(projectPath);
  final innerConfig = config.classInnerNoise;
  if (!innerConfig.enabled) {
    Log.log('Class inner noise is disabled by config.');
    return;
  }

  final libDir = Directory(p.join(projectPath, 'lib'));
  if (!libDir.existsSync()) {
    throw StateError('lib directory not found in $projectPath');
  }

  final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
  final hasFlutter = pubspec.existsSync() &&
      RegExp(r'^\s*flutter\s*:', multiLine: true)
          .hasMatch(pubspec.readAsStringSync());
  final result = _injectClassInnerNoise(
    libDir: libDir,
    config: innerConfig,
    hasFlutter: hasFlutter,
  );

  final mappingPath =
      p.join(projectPath, 'class_inner_noise_mapping_${_timestamp()}.json');
  final mapping = {
    'generated_at': DateTime.now().toIso8601String(),
    'config': innerConfig.toJson(),
    'config_file': config.configSource,
    'original_lines': result.originalLines,
    'target_lines': result.targetLines,
    'actual_added_lines': result.actualAddedLines,
    'files_touched': result.filesTouched,
    'classes_touched': result.classesTouched,
    'members': result.members,
    'hooks': result.hooks,
    'templates_used': result.templatesUsed.toList()..sort(),
    'imports_added': result.importsAdded.toList()..sort(),
    'skipped': result.skipped,
  };
  File(mappingPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(mapping),
  );

  Log.log('Class inner noise obfuscation complete.');
  Log.log('Mapping document: $mappingPath');
}

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
    required this.classInnerNoise,
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
  final ClassInnerNoiseConfig classInnerNoise;

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

    final pageCount = _readBoundedInt(decoded, 'pageCount', 1, 20);
    final classCount = _readBoundedInt(decoded, 'classCount', 1, 50);
    final methodCount = _readBoundedInt(decoded, 'methodCountPerClass', 1, 20);
    final garbageFileCountMin =
        _readOptionalBoundedInt(decoded, 'garbageFileCountMin', 3, 50, 3);
    final garbageFileCountMax = _readOptionalBoundedInt(
      decoded,
      'garbageFileCountMax',
      garbageFileCountMin,
      50,
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
    final classInnerNoise = ClassInnerNoiseConfig.fromJson(decoded);

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
      classInnerNoise: classInnerNoise,
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
      'classInnerNoise': classInnerNoise.toJson(),
    };
  }
}

class ClassInnerNoiseConfig {
  ClassInnerNoiseConfig({
    required this.enabled,
    required this.targetRatio,
    required this.maxTargetLines,
    required this.maxMembersPerClass,
    required this.maxHooksPerFile,
    required this.executionPolicy,
    required this.skipFiles,
    required this.lightweightTemplates,
    required this.retainedTemplates,
  });

  final bool enabled;
  final double targetRatio;
  final int maxTargetLines;
  final int maxMembersPerClass;
  final int maxHooksPerFile;
  final String executionPolicy;
  final List<String> skipFiles;
  final List<String> lightweightTemplates;
  final List<String> retainedTemplates;

  static ClassInnerNoiseConfig fromJson(Map<String, dynamic> json) {
    final value = json['classInnerNoise'];
    if (value == null) {
      return ClassInnerNoiseConfig(
        enabled: true,
        targetRatio: 1,
        maxTargetLines: 8000,
        maxMembersPerClass: 16,
        maxHooksPerFile: 30,
        executionPolicy: 'referenceOnly',
        skipFiles: const ['**/*.g.dart', '**/*.freezed.dart', '**/*.gr.dart'],
        lightweightTemplates: List<String>.from(_defaultLightweightTemplates),
        retainedTemplates: List<String>.from(_defaultRetainedTemplates),
      );
    }
    if (value is! Map<String, dynamic>) {
      throw StateError('classInnerNoise must be a JSON object.');
    }
    final enabled = value['enabled'] != false;
    final ratioValue = value['targetRatio'] ?? 1.0;
    if (ratioValue is! num || ratioValue <= 0 || ratioValue > 3) {
      throw StateError('classInnerNoise.targetRatio must be from 0 to 3.');
    }
    final policy = value['executionPolicy'] ?? 'referenceOnly';
    if (policy is! String ||
        !const {'referenceOnly', 'guardedRare'}.contains(policy)) {
      throw StateError('classInnerNoise.executionPolicy is unsupported.');
    }
    final templateGroups = value['templateGroups'];
    final groupJson = templateGroups is Map<String, dynamic>
        ? templateGroups
        : <String, dynamic>{};
    return ClassInnerNoiseConfig(
      enabled: enabled,
      targetRatio: ratioValue.toDouble(),
      maxTargetLines:
          _readOptionalBoundedInt(value, 'maxTargetLines', 20, 50000, 8000),
      maxMembersPerClass:
          _readOptionalBoundedInt(value, 'maxMembersPerClass', 1, 80, 16),
      maxHooksPerFile:
          _readOptionalBoundedInt(value, 'maxHooksPerFile', 1, 300, 30),
      executionPolicy: policy,
      skipFiles: _readStringList(
        value,
        'skipFiles',
        const ['**/*.g.dart', '**/*.freezed.dart', '**/*.gr.dart'],
      ),
      lightweightTemplates: _readTemplateIds(
        groupJson,
        'executedLightweight',
        _defaultLightweightTemplates,
      ),
      retainedTemplates: _readTemplateIds(
        groupJson,
        'retainedOnly',
        _defaultRetainedTemplates,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'targetRatio': targetRatio,
      'maxTargetLines': maxTargetLines,
      'maxMembersPerClass': maxMembersPerClass,
      'maxHooksPerFile': maxHooksPerFile,
      'executionPolicy': executionPolicy,
      'skipFiles': skipFiles,
      'templateGroups': {
        'executedLightweight': lightweightTemplates,
        'retainedOnly': retainedTemplates,
      },
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

class _ClassInnerResult {
  _ClassInnerResult({
    required this.originalLines,
    required this.targetLines,
    required this.actualAddedLines,
    required this.filesTouched,
    required this.classesTouched,
    required this.members,
    required this.hooks,
    required this.templatesUsed,
    required this.importsAdded,
    required this.skipped,
  });

  final int originalLines;
  final int targetLines;
  final int actualAddedLines;
  final List<String> filesTouched;
  final List<String> classesTouched;
  final List<String> members;
  final List<Map<String, dynamic>> hooks;
  final Set<String> templatesUsed;
  final Set<String> importsAdded;
  final List<Map<String, dynamic>> skipped;
}

class _ClassCandidate {
  _ClassCandidate({
    required this.declaration,
    required this.methods,
    required this.memberInsertOffset,
  });

  final ClassDeclaration declaration;
  final List<_HookCandidate> methods;
  final int memberInsertOffset;
}

class _HookCandidate {
  _HookCandidate({
    required this.name,
    required this.insertOffset,
    required this.isStatic,
  });

  final String name;
  final int insertOffset;
  final bool isStatic;
}

class _ClassCandidateVisitor extends RecursiveAstVisitor<void> {
  final classes = <_ClassCandidate>[];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final hooks = <_HookCandidate>[];
    for (final member in node.members) {
      if (member is MethodDeclaration) {
        if (member.isAbstract || member.externalKeyword != null) continue;
        if (member.isGetter || member.isSetter || member.isOperator) continue;
        final body = member.body;
        if (body is BlockFunctionBody) {
          hooks.add(_HookCandidate(
            name: member.name.lexeme,
            insertOffset: _hookInsertOffset(body.block),
            isStatic: member.isStatic,
          ));
        }
      } else if (member is ConstructorDeclaration) {
        if (member.constKeyword != null ||
            member.externalKeyword != null ||
            member.factoryKeyword != null) {
          continue;
        }
        final body = member.body;
        if (body is BlockFunctionBody) {
          hooks.add(_HookCandidate(
            name: member.name?.lexeme ?? node.name.lexeme,
            insertOffset: _hookInsertOffset(body.block),
            isStatic: false,
          ));
        }
      }
    }
    if (hooks.isNotEmpty) {
      classes.add(_ClassCandidate(
        declaration: node,
        methods: hooks,
        memberInsertOffset: _memberInsertOffset(node),
      ));
    }
    super.visitClassDeclaration(node);
  }
}

int _hookInsertOffset(Block block) {
  final statements = block.statements;
  if (statements.length >= 2) {
    return statements.first.end;
  }
  return block.leftBracket.end;
}

int _memberInsertOffset(ClassDeclaration declaration) {
  final members = declaration.members;
  if (members.length >= 3) {
    return members[members.length ~/ 2].offset;
  }
  if (members.length >= 2) {
    return members.last.offset;
  }
  return declaration.rightBracket.offset;
}

_ClassInnerResult _injectClassInnerNoise({
  required Directory libDir,
  required ClassInnerNoiseConfig config,
  required bool hasFlutter,
}) {
  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => p.extension(file.path) == '.dart')
      .where((file) {
    final rel = _posixRelative(file.path, from: libDir.path);
    return !_shouldSkipClassInnerFile(rel, config.skipFiles);
  }).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final skipped = <Map<String, dynamic>>[];
  var originalLines = 0;
  for (final file in dartFiles) {
    final source = file.readAsStringSync();
    originalLines += _nonEmptyLineCount(source);
  }
  final targetLines = min(config.maxTargetLines,
      max(1, (originalLines * config.targetRatio).ceil()));
  var actualAddedLines = 0;
  final filesTouched = <String>[];
  final classesTouched = <String>[];
  final members = <String>[];
  final hooks = <Map<String, dynamic>>[];
  final templatesUsed = <String>{};
  final importsAdded = <String>{};
  final random = Random();

  for (final file in dartFiles) {
    if (actualAddedLines >= targetLines) break;
    final relativeFile =
        p.posix.join('lib', _posixRelative(file.path, from: libDir.path));
    final source = file.readAsStringSync();
    if (source.contains(_classInnerMemberMarker)) {
      skipped.add({'file': relativeFile, 'reason': 'already_injected'});
      continue;
    }
    final parseResult = parseString(content: source, throwIfDiagnostics: false);
    if (parseResult.errors.isNotEmpty ||
        parseResult.unit.directives
            .any((directive) => directive is PartOfDirective)) {
      skipped.add({'file': relativeFile, 'reason': 'parse_error_or_part_file'});
      continue;
    }
    final visitor = _ClassCandidateVisitor();
    parseResult.unit.accept(visitor);
    if (visitor.classes.isEmpty) {
      skipped.add({'file': relativeFile, 'reason': 'no_safe_class_candidates'});
      continue;
    }

    final insertions = <_SourceInsertion>[];
    final neededImports = <String>{};
    var hooksInFile = 0;
    var touchedFile = false;
    for (final candidate in visitor.classes) {
      if (actualAddedLines >= targetLines) break;
      if (hooksInFile >= config.maxHooksPerFile) break;
      final selectedTemplates = _selectClassInnerTemplates(
        config,
        hasFlutter: hasFlutter,
        skipped: skipped,
        file: relativeFile,
      );
      if (selectedTemplates.isEmpty) continue;
      final prefix = '_obf${genRandomKey(8)}';
      final memberSource =
          _classInnerMembersSource(prefix, selectedTemplates, random);
      final memberLines = _nonEmptyLineCount(memberSource);
      final className = candidate.declaration.name.lexeme;
      insertions.add(_SourceInsertion(
        candidate.memberInsertOffset,
        '\n$memberSource',
      ));
      classesTouched.add(className);
      members
          .addAll(_classInnerMemberNames(prefix, selectedTemplates, className));
      templatesUsed.addAll(selectedTemplates);
      for (final template in selectedTemplates) {
        neededImports.addAll(_classInnerTemplateImports[template] ?? const []);
      }
      var hooksForClass = 0;
      for (final hook in candidate.methods) {
        if (hooksInFile >= config.maxHooksPerFile) break;
        if (actualAddedLines + memberLines >= targetLines &&
            hooksForClass > 0) {
          break;
        }
        final hookSource = _classInnerHookSource(
          prefix,
          className: className,
          methodName: hook.name,
          isStatic: hook.isStatic,
        );
        insertions.add(_SourceInsertion(hook.insertOffset, hookSource));
        hooks.add({
          'file': relativeFile,
          'class': className,
          'method': hook.name,
          'hook': '${prefix}Retain',
        });
        hooksInFile++;
        hooksForClass++;
      }
      if (hooksForClass == 0) continue;
      actualAddedLines += memberLines + (hooksForClass * 4);
      touchedFile = true;
    }
    if (!touchedFile) continue;
    final importInsertions = _classInnerImportInsertions(
      parseResult.unit,
      source,
      neededImports,
      hasFlutter: hasFlutter,
      skipped: skipped,
      file: relativeFile,
    );
    insertions.addAll(importInsertions.insertions);
    importsAdded.addAll(importInsertions.added);
    final updated = _applyInsertions(source, insertions);
    final updatedParse =
        parseString(content: updated, throwIfDiagnostics: false);
    if (updatedParse.errors.isNotEmpty) {
      skipped
          .add({'file': relativeFile, 'reason': 'updated_source_parse_error'});
      continue;
    }
    file.writeAsStringSync(updated);
    filesTouched.add(relativeFile);
  }

  return _ClassInnerResult(
    originalLines: originalLines,
    targetLines: targetLines,
    actualAddedLines: actualAddedLines,
    filesTouched: filesTouched,
    classesTouched: classesTouched.toSet().toList(),
    members: members,
    hooks: hooks,
    templatesUsed: templatesUsed,
    importsAdded: importsAdded,
    skipped: skipped,
  );
}

class _SourceInsertion {
  _SourceInsertion(this.offset, this.text) : endOffset = offset;

  _SourceInsertion.replace(this.offset, this.endOffset, this.text);

  final int offset;
  final int endOffset;
  final String text;
}

class _ImportInsertions {
  _ImportInsertions(this.insertions, this.added);

  final List<_SourceInsertion> insertions;
  final Set<String> added;
}

enum _ExtraFileKind {
  page,
  worker,
  shard,
}

class _ExtraFile {
  _ExtraFile({
    required this.path,
    required this.kind,
    required this.functionName,
  });

  final String path;
  final _ExtraFileKind kind;
  final String functionName;
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
  final pagesPath = _coreFilePath(directories[0], 'page');
  final workersPath = _coreFilePath(directories[0], 'worker');
  final extraFiles = _buildExtraFiles(
    config,
    directories,
    totalFileCount - 3,
    random,
  );
  final entryBuffer = StringBuffer()
    ..writeln('// Generated by obfuscateflutter. Do not edit by hand.')
    ..writeln("import '${_relativeImport(entryPath, pagesPath)}';")
    ..writeln("import '${_relativeImport(entryPath, workersPath)}';");
  for (final extraFile in extraFiles) {
    entryBuffer
        .writeln("import '${_relativeImport(entryPath, extraFile.path)}';");
  }
  entryBuffer.writeln();
  final pagesBuffer = StringBuffer()
    ..writeln('// Generated by obfuscateflutter. Do not edit by hand.')
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln("import '${_relativeImport(pagesPath, workersPath)}';")
    ..writeln();
  final workersBuffer = StringBuffer()
    ..writeln('// Generated by obfuscateflutter. Do not edit by hand.')
    ..writeln();

  for (var i = 0; i < config.pageCount; i++) {
    final className = _uniqueClassName('NoisePage', usedClassNames);
    final pageSnippet = _pickPageSnippet(config, i);
    _countSnippet(snippetUsage, pageSnippet);
    pageClasses.add(className);
    pagesBuffer
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
      ..write(_pageBody(pageSnippet, random, config))
      ..writeln('  }')
      ..writeln('}')
      ..writeln();
  }

  pagesBuffer
    ..writeln('int dartNoisePageBridge(int input) {')
    ..writeln('  var checksum = input;');
  for (final pageClass in pageClasses) {
    pagesBuffer.writeln('  checksum ^= $pageClass.noiseLink(checksum);');
  }
  pagesBuffer
    ..writeln('  return checksum;')
    ..writeln('}')
    ..writeln();

  if (modelClassName != null) {
    workersBuffer.write(_modelClass(modelClassName));
  }
  if (enumName != null) {
    workersBuffer.write(_enumDeclaration(enumName));
  }

  final classMethodNames = <String, List<String>>{};
  final methodSnippetPlan = _methodSnippetPlan(config);
  var methodIndex = 0;
  for (var i = 0; i < config.classCount; i++) {
    final className = _uniqueClassName('NoiseWorker', usedClassNames);
    dartClasses.add(className);
    final seed = random.nextInt(1 << 20) + 1;
    final methodNames = <String>[];
    final usedMethodNames = <String>{};
    classMethodNames[className] = methodNames;
    workersBuffer
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
      workersBuffer
        ..writeln('  int $methodName(int input) {')
        ..write(_methodBody(
          methodSnippet,
          salt,
          shift,
          modelClassName,
          enumName,
          config,
        ))
        ..writeln('  }')
        ..writeln();
    }
    workersBuffer
      ..writeln('}')
      ..writeln();
  }

  workersBuffer
    ..writeln('int dartNoiseWorkerBridge(int input) {')
    ..writeln('  var checksum = input;');
  for (final className in dartClasses) {
    workersBuffer
      ..writeln('  const ${_instanceName(className)} = $className();')
      ..writeln('  checksum += ${_instanceName(className)}.seed;');
    for (final methodName in classMethodNames[className]!) {
      workersBuffer.writeln(
          '  checksum ^= ${_instanceName(className)}.$methodName(checksum);');
    }
  }
  workersBuffer
    ..writeln('  return checksum;')
    ..writeln('}')
    ..writeln();

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
  for (final extraFile in extraFiles) {
    entryBuffer.writeln('  checksum ^= ${extraFile.functionName}(checksum);');
  }
  entryBuffer
    ..writeln('  if (checksum == -1 && pageFactories.isNotEmpty) {')
    ..writeln('    return pageFactories.first();')
    ..writeln('  }')
    ..writeln('  return checksum;')
    ..writeln('}')
    ..writeln();

  final entrySource = entryBuffer.toString();
  final pagesSource = pagesBuffer.toString();
  final workersSource = workersBuffer.toString();
  final sources = <String, String>{
    entryPath: entrySource,
    pagesPath: pagesSource,
    workersPath: workersSource,
  };
  for (final extraFile in extraFiles) {
    sources[extraFile.path] = _extraSource(extraFile, random);
  }
  return _GeneratedNoise(
    entryPath: entryPath,
    source: entrySource,
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

List<String> _readStringList(
  Map<String, dynamic> json,
  String key,
  List<String> defaults,
) {
  final value = json[key];
  if (value == null) return List<String>.from(defaults);
  if (value is! List) {
    throw StateError('$key must be a string array.');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty) {
      throw StateError('$key must be a string array.');
    }
    result.add(item);
  }
  return result;
}

List<String> _readTemplateIds(
  Map<String, dynamic> json,
  String key,
  List<String> defaults,
) {
  final ids = _readStringList(json, key, defaults);
  for (final id in ids) {
    if (!_knownClassInnerTemplates.contains(id)) {
      throw StateError('Unsupported class inner noise template: $id.');
    }
  }
  return ids;
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

String _pickPageSnippet(DartNoiseConfig config, int index) {
  final customPageIds =
      config.customPageTemplates.map((template) => template.id).toSet();
  final pageSnippets = config.snippets.where((snippet) {
    return snippet == 'widget_layout_page' || customPageIds.contains(snippet);
  }).toList();
  if (pageSnippets.isEmpty) return 'widget_empty_page';
  return pageSnippets[index % pageSnippets.length];
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

List<_ExtraFile> _buildExtraFiles(
  DartNoiseConfig config,
  List<String> directories,
  int extraCount,
  Random random,
) {
  if (extraCount <= 0) return [];
  final files = <_ExtraFile>[];
  var index = 0;
  final secondaryDirs =
      directories.length > 1 ? directories.skip(1).toList() : directories;

  if (extraCount >= 1) {
    files.add(_extraFile(secondaryDirs.first, _ExtraFileKind.page, index++));
  }
  if (extraCount >= 2) {
    files.add(_extraFile(secondaryDirs.first, _ExtraFileKind.worker, index++));
  }

  final kinds = [
    _ExtraFileKind.shard,
    _ExtraFileKind.page,
    _ExtraFileKind.worker,
  ];
  while (files.length < extraCount) {
    final dir = secondaryDirs[(files.length ~/ 2) % secondaryDirs.length];
    final kind = kinds[files.length % kinds.length];
    files.add(_extraFile(dir, kind, index++));
  }

  return files;
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

_ExtraFile _extraFile(String dir, _ExtraFileKind kind, int index) {
  final functionPrefix = switch (kind) {
    _ExtraFileKind.page => 'dartNoiseExtraPage',
    _ExtraFileKind.worker => 'dartNoiseExtraWorker',
    _ExtraFileKind.shard => 'dartNoiseShard',
  };
  return _ExtraFile(
    path: _typedFilePath(dir, kind),
    kind: kind,
    functionName: '$functionPrefix$index',
  );
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

String _extraSource(_ExtraFile file, Random random) {
  return switch (file.kind) {
    _ExtraFileKind.page => _extraPageSource(file.functionName, random),
    _ExtraFileKind.worker => _extraWorkerSource(file.functionName, random),
    _ExtraFileKind.shard => _extraShardSource(file.functionName, random),
  };
}

String _extraShardSource(String functionName, Random random) {
  final salt = random.nextInt(1 << 20) + 1;
  final shift = random.nextInt(8) + 1;
  return '''
// Generated by obfuscateflutter. Do not edit by hand.

int $functionName(int input) {
  final mixed = input + $salt;
  final folded = (mixed ^ (mixed << $shift)) & 0x3fffffff;
  return (folded + $salt + input) & 0x3fffffff;
}

''';
}

String _extraPageSource(String functionName, Random random) {
  final width = random.nextInt(64) + 16;
  final height = random.nextInt(64) + 16;
  final className = _uniqueClassName('NoiseExtraPage', <String>{});
  return '''
// Generated by obfuscateflutter. Do not edit by hand.
import 'package:flutter/widgets.dart';

class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: $width, height: $height);
  }
}

int $functionName(int input) {
  final factory = () => const $className();
  return input + factory().hashCode;
}

''';
}

String _extraWorkerSource(String functionName, Random random) {
  final className = _uniqueClassName('NoiseExtraWorker', <String>{});
  final salt = random.nextInt(1 << 20) + 1;
  return '''
// Generated by obfuscateflutter. Do not edit by hand.

class $className {
  const $className(this.seed);

  final int seed;

  int fold(int input) {
    final values = List<int>.generate(4, (index) => input + seed + index);
    return values.fold(seed, (acc, item) => (acc ^ item) & 0x3fffffff);
  }
}

int $functionName(int input) {
  const worker = $className($salt);
  return worker.fold(input);
}

''';
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

bool _shouldSkipClassInnerFile(String relativePath, List<String> patterns) {
  final basename = p.posix.basename(relativePath);
  if (relativePath.split('/').any((part) => part.startsWith('.'))) return true;
  for (final pattern in patterns) {
    if (pattern.startsWith('**/*.') &&
        basename.endsWith(pattern.substring(4))) {
      return true;
    }
    if (pattern == relativePath || pattern == basename) return true;
  }
  return false;
}

int _nonEmptyLineCount(String source) {
  return source.split('\n').where((line) => line.trim().isNotEmpty).length;
}

List<String> _selectClassInnerTemplates(
  ClassInnerNoiseConfig config, {
  required bool hasFlutter,
  required List<Map<String, dynamic>> skipped,
  required String file,
}) {
  final selected = <String>[
    ...config.lightweightTemplates.take(max(1, config.maxMembersPerClass ~/ 4)),
  ];
  final remaining = max(0, config.maxMembersPerClass - selected.length);
  for (final template in config.retainedTemplates.take(remaining)) {
    final imports = _classInnerTemplateImports[template] ?? const [];
    final needsFlutter =
        imports.any((item) => item.startsWith('package:flutter/'));
    if (needsFlutter && !hasFlutter) {
      skipped.add({
        'file': file,
        'template': template,
        'reason': 'missing_flutter_dependency',
      });
      continue;
    }
    selected.add(template);
  }
  return selected.toSet().toList();
}

String _classInnerMembersSource(
  String prefix,
  List<String> templates,
  Random random,
) {
  final seed = random.nextInt(1 << 20) + 1;
  final buffer = StringBuffer()
    ..writeln('  $_classInnerMemberMarker')
    ..writeln('  static final int ${prefix}Seed = identityHashCode(\'$seed\');')
    ..writeln()
    ..writeln('  static int ${prefix}Retain(Object? seed) {')
    ..writeln('    final refs = <Object?>[');
  for (final template in templates.where(
      (template) => template != 'sync_hash' && template != 'sync_switch')) {
    buffer.writeln('      $prefix${_classInnerTemplateSuffix(template)},');
  }
  buffer
    ..writeln('    ];')
    ..writeln('    var value = ${prefix}SyncHash(seed) ^ refs.length;');
  if (templates.contains('sync_switch')) {
    buffer.writeln('    value ^= ${prefix}SyncSwitch(value);');
  }
  buffer
    ..writeln('    if (value == -1 && refs.isNotEmpty) {')
    ..writeln('      return identityHashCode(refs.first);')
    ..writeln('    }')
    ..writeln('    return value;')
    ..writeln('  }')
    ..writeln()
    ..writeln('  static int ${prefix}SyncHash(Object? seed) {')
    ..writeln('    final text = seed?.toString() ?? \'\';')
    ..writeln('    var hash = ${prefix}Seed;')
    ..writeln('    for (final unit in text.codeUnits) {')
    ..writeln('      hash = ((hash * 33) ^ unit) & 0x3fffffff;')
    ..writeln('    }')
    ..writeln('    return hash;')
    ..writeln('  }')
    ..writeln();
  if (templates.contains('sync_switch')) {
    buffer
      ..writeln('  static int ${prefix}SyncSwitch(int seed) {')
      ..writeln('    switch (seed & 3) {')
      ..writeln('      case 0:')
      ..writeln('        return seed ^ ${prefix}Seed;')
      ..writeln('      case 1:')
      ..writeln('        return seed + ${prefix}Seed;')
      ..writeln('      case 2:')
      ..writeln('        return seed - ${prefix}Seed;')
      ..writeln('      default:')
      ..writeln('        return seed;')
      ..writeln('    }')
      ..writeln('  }')
      ..writeln();
  }
  for (final template in templates) {
    buffer.write(_retainedTemplateSource(prefix, template));
  }
  return buffer.toString();
}

String _classInnerTemplateSuffix(String template) {
  return switch (template) {
    'async_future' => 'AsyncFuture',
    'timer_stub' => 'TimerStub',
    'file_io_stub' => 'FileIoStub',
    'network_stub' => 'NetworkStub',
    'platform_channel_stub' => 'PlatformChannelStub',
    'navigator_stub' => 'NavigatorStub',
    'set_state_stub' => 'SetStateStub',
    'run_app_stub' => 'RunAppStub',
    'debug_log_stub' => 'DebugLogStub',
    _ => 'SyncHash',
  };
}

List<String> _classInnerMemberNames(
  String prefix,
  List<String> templates,
  String className,
) {
  return [
    '$className.${prefix}Seed',
    '$className.${prefix}Retain',
    '$className.${prefix}SyncHash',
    if (templates.contains('sync_switch')) '$className.${prefix}SyncSwitch',
    for (final template in templates.where(
        (template) => template != 'sync_hash' && template != 'sync_switch'))
      '$className.$prefix${_classInnerTemplateSuffix(template)}',
  ];
}

String _retainedTemplateSource(String prefix, String template) {
  switch (template) {
    case 'async_future':
      return '''
  static obf_async.Future<int> ${prefix}AsyncFuture(Object? seed) async {
    final value = await obf_async.Future<int>.value(identityHashCode(seed));
    return value ^ ${prefix}Seed;
  }

''';
    case 'timer_stub':
      return '''
  static void ${prefix}TimerStub(Object? seed) {
    obf_async.Timer(const Duration(milliseconds: 1), () {
      obf_widgets.debugPrint(seed?.toString());
    });
  }

''';
    case 'file_io_stub':
      return '''
  static String ${prefix}FileIoStub(Object? seed) {
    final file = obf_io.File(seed?.toString() ?? '');
    return file.path;
  }

''';
    case 'network_stub':
      return '''
  static Object ${prefix}NetworkStub(Object? seed) {
    final client = obf_io.HttpClient();
    client.userAgent = seed?.toString();
    return client;
  }

''';
    case 'platform_channel_stub':
      return '''
  static Object ${prefix}PlatformChannelStub(Object? seed) {
    return obf_services.MethodChannel('obf.\${identityHashCode(seed)}');
  }

''';
    case 'navigator_stub':
      return '''
  static Object ${prefix}NavigatorStub(obf_widgets.BuildContext context) {
    return obf_widgets.Navigator.of(context);
  }

''';
    case 'set_state_stub':
      return '''
  static void ${prefix}SetStateStub(dynamic state) {
    state.setState(() {});
  }

''';
    case 'run_app_stub':
      return '''
  static obf_widgets.Widget ${prefix}RunAppStub(Object? seed) {
    const widget = obf_widgets.SizedBox.shrink();
    obf_widgets.runApp(widget);
    return widget;
  }

''';
    case 'debug_log_stub':
      return '''
  static void ${prefix}DebugLogStub(Object? seed) {
    obf_widgets.debugPrint(seed?.toString());
  }

''';
    default:
      return '';
  }
}

String _classInnerHookSource(
  String prefix, {
  required String className,
  required String methodName,
  required bool isStatic,
}) {
  final localName = 'obfNoise${genRandomKey(6)}';
  final seed = isStatic
      ? "Object.hash('$className', '$methodName')"
      : 'identityHashCode(this)';
  return '''

    final $localName = ${prefix}Retain($seed); $_classInnerHookMarker
    if ($localName == -1) {
      ${prefix}Retain($localName);
    }
''';
}

_ImportInsertions _classInnerImportInsertions(
  CompilationUnit unit,
  String source,
  Set<String> neededImports, {
  required bool hasFlutter,
  required List<Map<String, dynamic>> skipped,
  required String file,
}) {
  final importDirectives =
      unit.directives.whereType<ImportDirective>().toList();
  final existing = importDirectives
      .map((directive) => _normalizeImportLine(
            source.substring(directive.offset, directive.end),
          ))
      .whereType<String>()
      .toSet();
  final missing = <String>{};
  for (final import in neededImports) {
    if (_importSpecUri(import).startsWith('package:flutter/') && !hasFlutter) {
      skipped.add({
        'file': file,
        'import': import,
        'reason': 'missing_flutter_dependency',
      });
      continue;
    }
    if (!existing.contains(import)) {
      missing.add(import);
    }
  }
  if (missing.isEmpty) return _ImportInsertions([], {});
  if (importDirectives.isEmpty) {
    final lines = _sortImportSpecs(missing).map(_importLineFromSpec).join('\n');
    return _ImportInsertions([_SourceInsertion(0, '$lines\n\n')], missing);
  }

  final firstOffset = importDirectives.first.offset;
  final lastEnd = importDirectives.last.end;
  final importSpecs = <String>{...existing, ...missing};
  final lines =
      _sortImportSpecs(importSpecs).map(_importLineFromSpec).join('\n');
  final replacement = '$lines\n';
  return _ImportInsertions(
    [_SourceInsertion.replace(firstOffset, lastEnd, replacement)],
    missing,
  );
}

String _applyInsertions(String source, List<_SourceInsertion> insertions) {
  final sorted = insertions.toList()
    ..sort((a, b) => b.offset.compareTo(a.offset));
  var updated = source;
  for (final insertion in sorted) {
    updated = updated.replaceRange(
      insertion.offset,
      insertion.endOffset,
      insertion.text,
    );
  }
  return updated;
}

String? _normalizeImportLine(String line) {
  final match =
      RegExp(r"import\s+'([^']+)'\s*(?:as\s+([A-Za-z_][A-Za-z0-9_]*))?\s*;")
          .firstMatch(line.trim());
  if (match == null) return null;
  final uri = match.group(1)!;
  final prefix = match.group(2);
  return prefix == null ? uri : '$uri as $prefix';
}

String _importSpecUri(String spec) {
  final asIndex = spec.indexOf(' as ');
  return asIndex == -1 ? spec : spec.substring(0, asIndex);
}

String _importLineFromSpec(String spec) {
  final asIndex = spec.indexOf(' as ');
  if (asIndex == -1) return "import '$spec';";
  final uri = spec.substring(0, asIndex);
  final prefix = spec.substring(asIndex + 4);
  return "import '$uri' as $prefix;";
}

List<String> _sortImportSpecs(Iterable<String> specs) {
  return specs.toList()
    ..sort((a, b) {
      final aRank = _importRank(a);
      final bRank = _importRank(b);
      if (aRank != bRank) return aRank.compareTo(bRank);
      return a.compareTo(b);
    });
}

int _importRank(String spec) {
  final uri = _importSpecUri(spec);
  if (uri.startsWith('dart:')) return 0;
  if (uri.startsWith('package:')) return 1;
  return 2;
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
