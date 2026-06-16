import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:obfuscateflutter/html_mapping_writer.dart';
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
const _defaultStringNoiseTemplates = [
  {'id': 'session_word_seed', 'value': 'session_{{word}}_{{seed}}'},
  {
    'id': 'trace_context',
    'value': 'trace.{{className}}.{{methodName}}.{{index}}'
  },
  {'id': 'cache_ready', 'value': 'cache {{noun}} ready {{seed}}'},
  {'id': 'route_word', 'value': 'route/{{word}}/{{index}}'},
  {'id': 'metric_event', 'value': 'metric_{{verb}}_{{noun}}_{{seed}}'},
];
const _stringNoiseWords = [
  'signal',
  'anchor',
  'canvas',
  'packet',
  'cursor',
  'frame',
  'token',
  'scope',
  'buffer',
  'marker',
];
const _stringNoiseVerbs = [
  'sync',
  'merge',
  'trace',
  'cache',
  'route',
  'parse',
  'watch',
  'bind',
  'index',
  'stage',
];
const _stringNoiseNouns = [
  'session',
  'payload',
  'channel',
  'window',
  'record',
  'profile',
  'segment',
  'snapshot',
  'entry',
  'bucket',
];
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
    'string_templates_used': result.stringTemplatesUsed.toList()..sort(),
    'strings_injected': result.stringsInjected,
    'imports_added': result.importsAdded.toList()..sort(),
    'skipped': result.skipped,
  };
  final mappingPath = writeHtmlFeatureMapping(
    projectPath: projectPath,
    featureId: 'class_inner_noise',
    featureTitle: '类内垃圾代码/字符串注入',
    mapping: mapping,
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
  final mappingPath = writeHtmlFeatureMapping(
    projectPath: projectPath,
    featureId: 'dart_noise',
    featureTitle: 'Dart随机代码注入/保留',
    mapping: mapping,
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

    final pageCount = _readBoundedInt(decoded, 'pageCount', 1, 500);
    final classCount = _readBoundedInt(decoded, 'classCount', 1, 500);
    final methodCount = _readBoundedInt(decoded, 'methodCountPerClass', 1, 500);
    final garbageFileCountMin =
        _readOptionalBoundedInt(decoded, 'garbageFileCountMin', 3, 100, 3);
    final garbageFileCountMax = _readOptionalBoundedInt(
      decoded,
      'garbageFileCountMax',
      garbageFileCountMin,
      1000,
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
    required this.stringNoise,
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
  final ClassInnerStringNoiseConfig stringNoise;

  static ClassInnerNoiseConfig fromJson(Map<String, dynamic> json) {
    final value = json['classInnerNoise'];
    if (value == null) {
      return ClassInnerNoiseConfig(
        enabled: true,
        targetRatio: 1.5,
        maxTargetLines: 100000,
        maxMembersPerClass: 16,
        maxHooksPerFile: 30,
        executionPolicy: 'referenceOnly',
        skipFiles: const ['**/*.g.dart', '**/*.freezed.dart', '**/*.gr.dart'],
        lightweightTemplates: List<String>.from(_defaultLightweightTemplates),
        retainedTemplates: List<String>.from(_defaultRetainedTemplates),
        stringNoise: ClassInnerStringNoiseConfig.defaults(),
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
          _readOptionalBoundedInt(value, 'maxTargetLines', 20, 500000, 8000),
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
      stringNoise: ClassInnerStringNoiseConfig.fromJson(value),
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
      'stringNoise': stringNoise.toJson(),
    };
  }
}

class ClassInnerStringNoiseConfig {
  ClassInnerStringNoiseConfig({
    required this.enabled,
    required this.memberStringCountPerClass,
    required this.localStringCountPerHook,
    required this.templates,
    required this.templateWeights,
    required this.minLength,
    required this.maxLength,
  });

  final bool enabled;
  final IntRange memberStringCountPerClass;
  final IntRange localStringCountPerHook;
  final List<NoiseTemplate> templates;
  final Map<String, int> templateWeights;
  final int minLength;
  final int maxLength;

  factory ClassInnerStringNoiseConfig.defaults() {
    final templates = _defaultStringNoiseTemplates
        .map((item) => NoiseTemplate(
              id: item['id']!,
              body: item['value']!,
            ))
        .toList();
    return ClassInnerStringNoiseConfig(
      enabled: true,
      memberStringCountPerClass: const IntRange(2, 6),
      localStringCountPerHook: const IntRange(0, 3),
      templates: templates,
      templateWeights: {
        for (final template in templates) template.id: 1,
      },
      minLength: 6,
      maxLength: 96,
    );
  }

  static ClassInnerStringNoiseConfig fromJson(Map<String, dynamic> json) {
    final value = json['stringNoise'];
    final defaults = ClassInnerStringNoiseConfig.defaults();
    if (value == null) return defaults;
    if (value is! Map<String, dynamic>) {
      throw StateError('classInnerNoise.stringNoise must be a JSON object.');
    }
    final enabled = value['enabled'] != false;
    final templates = _readStringNoiseTemplates(value, defaults.templates);
    final minLength =
        _readOptionalBoundedInt(value, 'minLength', 1, 512, defaults.minLength);
    final maxLengthDefault = max(defaults.maxLength, minLength);
    final maxLength = _readOptionalBoundedInt(
        value, 'maxLength', minLength, 1024, maxLengthDefault);
    return ClassInnerStringNoiseConfig(
      enabled: enabled,
      memberStringCountPerClass: _readIntRange(
        value,
        'memberStringCountPerClass',
        defaults.memberStringCountPerClass,
        min: 0,
        max: 50,
      ),
      localStringCountPerHook: _readIntRange(
        value,
        'localStringCountPerHook',
        defaults.localStringCountPerHook,
        min: 0,
        max: 20,
      ),
      templates: templates,
      templateWeights: _readStringTemplateWeights(
        value,
        templates,
        defaults.templateWeights,
      ),
      minLength: minLength,
      maxLength: maxLength,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'memberStringCountPerClass': [
        memberStringCountPerClass.min,
        memberStringCountPerClass.max,
      ],
      'localStringCountPerHook': [
        localStringCountPerHook.min,
        localStringCountPerHook.max,
      ],
      'templates': templates
          .map((template) => {
                'id': template.id,
                'value': template.body,
              })
          .toList(),
      'templateWeights': templateWeights,
      'minLength': minLength,
      'maxLength': maxLength,
    };
  }
}

class IntRange {
  const IntRange(this.min, this.max);

  final int min;
  final int max;
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
    required this.stringTemplatesUsed,
    required this.stringsInjected,
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
  final Set<String> stringTemplatesUsed;
  final List<Map<String, dynamic>> stringsInjected;
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

class _StringNoiseItem {
  _StringNoiseItem({
    required this.templateId,
    required this.value,
  });

  final String templateId;
  final String value;
}

class _StringMemberPlan {
  _StringMemberPlan(this.strings);

  final List<_StringNoiseItem> strings;

  bool get isEmpty => strings.isEmpty;
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
  final stringTemplatesUsed = <String>{};
  final stringsInjected = <Map<String, dynamic>>[];
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
      final className = candidate.declaration.name.lexeme;
      final stringMemberPlan = _buildStringMemberPlan(
        config.stringNoise,
        random,
        prefix: prefix,
        className: className,
      );
      final memberSource = _classInnerMembersSource(
        prefix,
        selectedTemplates,
        random,
        stringMemberPlan,
      );
      final memberLines = _nonEmptyLineCount(memberSource);
      insertions.add(_SourceInsertion(
        candidate.memberInsertOffset,
        '\n$memberSource',
      ));
      classesTouched.add(className);
      members.addAll(_classInnerMemberNames(
        prefix,
        selectedTemplates,
        className,
        stringMemberPlan,
      ));
      templatesUsed.addAll(selectedTemplates);
      stringTemplatesUsed.addAll(
        stringMemberPlan.strings.map((item) => item.templateId),
      );
      stringsInjected.addAll(stringMemberPlan.strings.map((item) => {
            'file': relativeFile,
            'class': className,
            'kind': 'member',
            'templateId': item.templateId,
            'value': item.value,
          }));
      for (final template in selectedTemplates) {
        neededImports.addAll(_classInnerTemplateImports[template] ?? const []);
      }
      var hooksForClass = 0;
      var hookLinesForClass = 0;
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
          stringNoise: config.stringNoise,
          random: random,
          file: relativeFile,
          stringsInjected: stringsInjected,
          stringTemplatesUsed: stringTemplatesUsed,
        );
        hookLinesForClass += _nonEmptyLineCount(hookSource);
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
      actualAddedLines += memberLines + hookLinesForClass;
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
    stringTemplatesUsed: stringTemplatesUsed,
    stringsInjected: stringsInjected,
    importsAdded: importsAdded,
    skipped: skipped,
  );
}

class _SourceInsertion {
  _SourceInsertion(this.offset, this.text) : endOffset = offset;

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
  // Reserve: entry + bridge + content files. Extra files become shards.
  final pageFileCount = config.pageCount; // 1 page per file
  final workerFileCount = config.classCount; // 1 worker per file
  final classFileCount = pageFileCount + workerFileCount;
  final shardFileCount = (totalFileCount - 2 - classFileCount).clamp(0, 999999);
  final allContentFileCount = classFileCount + shardFileCount;
  final bridgePath = allContentFileCount > 0
      ? _coreFilePath(directories[0], 'bridge')
      : _coreFilePath(directories[0], 'worker');

  // Build content file descriptors
  final contentFiles = <_ContentFile>[];
  final contentDirs = _contentDirPlan(directories, allContentFileCount);
  var dirIdx = 0;
  for (var i = 0; i < pageFileCount; i++) {
    contentFiles.add(_ContentFile(
      path: _typedFilePath(contentDirs[dirIdx++], _ExtraFileKind.page),
      isPageFile: true,
      isWorkerFile: false,
    ));
  }
  for (var i = 0; i < workerFileCount; i++) {
    contentFiles.add(_ContentFile(
      path: _typedFilePath(contentDirs[dirIdx++], _ExtraFileKind.worker),
      isPageFile: false,
      isWorkerFile: true,
    ));
  }
  for (var i = 0; i < shardFileCount; i++) {
    contentFiles.add(_ContentFile(
      path: _typedFilePath(contentDirs[dirIdx++], _ExtraFileKind.shard),
      isPageFile: false,
      isWorkerFile: false,
    ));
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
          ..writeln(
              "import '${_relativeImport(f.path, firstWorkerFile.path)}';")
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
    buf
      ..writeln('}')
      ..writeln();
    targetFile.weight += 4;
  }

  // ── 4. Fill shard-only files with multi-function content ──
  var shardVariantIndex = 0;
  for (final file
      in contentFiles.where((f) => !f.isPageFile && !f.isWorkerFile)) {
    _writeMultiShard(file.buffer, file.path, random, shardVariantIndex++);
    file.weight += 3;
  }

  // ── 5. Build bridge file (single file, all imports before code) ──
  final bridgeBuf = StringBuffer()
    ..writeln('// Generated by obfuscateflutter. Do not edit by hand.');
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
    ..writeln('Object? dartNoisePageFactoryRetain(int checksum) {')
    ..writeln('  final pageFactories = <Object Function()>[');
  for (final pageClass in pageClasses) {
    bridgeBuf.writeln('    () => const $pageClass(),');
  }
  bridgeBuf
    ..writeln('  ];')
    ..writeln('  if (checksum == -1 && pageFactories.isNotEmpty) {')
    ..writeln('    return pageFactories.first();')
    ..writeln('  }')
    ..writeln('  return null;')
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
  for (final file
      in contentFiles.where((f) => !f.isPageFile && !f.isWorkerFile)) {
    entryBuffer.writeln("import '${_relativeImport(entryPath, file.path)}';");
  }
  entryBuffer.writeln();

  // Collect shard entry-point function names
  final extraFuncNames = <String>[];
  for (final file
      in contentFiles.where((f) => !f.isPageFile && !f.isWorkerFile)) {
    extraFuncNames.add(_shardFuncName(file.path));
  }

  entryBuffer
    ..writeln('Object? $_retainFunctionName() {')
    ..writeln('  final retainedSymbols = <Object?>[')
    ..writeln('    dartNoisePageBridge,')
    ..writeln('    dartNoiseWorkerBridge,')
    ..writeln('    dartNoisePageFactoryRetain,');
  for (final funcName in extraFuncNames) {
    entryBuffer.writeln('    $funcName,');
  }
  entryBuffer
    ..writeln('  ];')
    ..writeln('  return Object.hashAll(retainedSymbols);')
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

IntRange _readIntRange(
  Map<String, dynamic> json,
  String key,
  IntRange defaults, {
  required int min,
  required int max,
}) {
  final value = json[key];
  if (value == null) return defaults;
  if (value is! List || value.length != 2) {
    throw StateError('classInnerNoise.stringNoise.$key must be [min, max].');
  }
  final start = value[0];
  final end = value[1];
  if (start is! int || end is! int || start < min || end > max || start > end) {
    throw StateError(
        'classInnerNoise.stringNoise.$key must be integers from $min to $max.');
  }
  return IntRange(start, end);
}

List<NoiseTemplate> _readStringNoiseTemplates(
  Map<String, dynamic> json,
  List<NoiseTemplate> defaults,
) {
  final value = json['templates'];
  if (value == null) return List<NoiseTemplate>.from(defaults);
  if (value is! List || value.isEmpty) {
    throw StateError('classInnerNoise.stringNoise.templates must be an array.');
  }
  final ids = <String>{};
  return value.map((item) {
    if (item is! Map<String, dynamic>) {
      throw StateError(
          'classInnerNoise.stringNoise.templates entries must be objects.');
    }
    final id = item['id'];
    final body = item['value'] ?? item['body'];
    if (id is! String || !_isIdentifier(id)) {
      throw StateError(
          'classInnerNoise.stringNoise.templates.id must be an identifier.');
    }
    if (!ids.add(id)) {
      throw StateError('Duplicate stringNoise template id: $id.');
    }
    if (body is! String || body.trim().isEmpty) {
      throw StateError(
          'classInnerNoise.stringNoise.templates.value must be non-empty.');
    }
    _validateStringNoiseTemplate(id, body);
    return NoiseTemplate(id: id, body: body);
  }).toList();
}

Map<String, int> _readStringTemplateWeights(
  Map<String, dynamic> json,
  List<NoiseTemplate> templates,
  Map<String, int> defaults,
) {
  final ids = templates.map((template) => template.id).toSet();
  final weights = {
    for (final template in templates) template.id: defaults[template.id] ?? 1,
  };
  final value = json['templateWeights'];
  if (value == null) return weights;
  if (value is! Map<String, dynamic>) {
    throw StateError(
        'classInnerNoise.stringNoise.templateWeights must be an object.');
  }
  for (final entry in value.entries) {
    if (!ids.contains(entry.key)) {
      throw StateError(
          'Unsupported stringNoise template weight: ${entry.key}.');
    }
    final weight = entry.value;
    if (weight is! int || weight < 1 || weight > 20) {
      throw StateError(
          'classInnerNoise.stringNoise.templateWeights.${entry.key} must be from 1 to 20.');
    }
    weights[entry.key] = weight;
  }
  return weights;
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

void _validateStringNoiseTemplate(String id, String body) {
  final forbiddenPatterns = [
    RegExp(r'[\r\n;]'),
    RegExp(r'\bFuture\b'),
    RegExp(r'\bStream\b'),
    RegExp(r'\basync\b'),
    RegExp(r'\bawait\b'),
    RegExp(r'\bTimer\b'),
    RegExp(r'\bimport\b'),
    RegExp(r'\bexport\b'),
    RegExp(r'\bpart\b'),
    RegExp(r'\bclass\b'),
    RegExp(r'dart:io'),
    RegExp(r'dart:async'),
    RegExp(r'@pragma'),
  ];
  for (final pattern in forbiddenPatterns) {
    if (pattern.hasMatch(body)) {
      throw StateError('stringNoise template $id contains forbidden content: '
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

void _writeMultiShard(
  StringBuffer buf,
  String filePath,
  Random random,
  int variantSeed,
) {
  final count = 4 + random.nextInt(4); // 4-7 internal functions
  final baseName = _shardFuncName(filePath);
  final startVariant = variantSeed % 4;
  buf.writeln();
  for (var i = 0; i < count; i++) {
    final salt = random.nextInt(1 << 20) + 1;
    final shift = random.nextInt(8) + 1;
    final variant = (startVariant + i) % 4;
    _writeShardStep(buf, '${baseName}Step$i', variant, salt, shift);
  }
  // Public entry-point chains all internal functions (prevents tree shaking)
  buf
    ..writeln('int $baseName(int input) {')
    ..writeln('  var checksum = input;');
  for (var i = 0; i < count; i++) {
    buf.writeln('  checksum ^= ${baseName}Step$i(checksum);');
  }
  buf
    ..writeln('  return checksum;')
    ..writeln('}')
    ..writeln();
}

void _writeShardStep(
  StringBuffer buf,
  String name,
  int variant,
  int salt,
  int shift,
) {
  buf.writeln('int $name(int input) {');
  switch (variant) {
    case 1:
      buf
        ..writeln('  var mixed = input ^ $salt;')
        ..writeln('  for (var i = 0; i < ${shift + 2}; i++) {')
        ..writeln(
            '    mixed = ((mixed + i + $salt) ^ (mixed >> 1)) & 0x3fffffff;')
        ..writeln('  }')
        ..writeln('  return mixed;');
      break;
    case 2:
      buf
        ..writeln('  switch ((input + $salt) & 3) {')
        ..writeln('    case 0:')
        ..writeln('      return (input + $salt) & 0x3fffffff;')
        ..writeln('    case 1:')
        ..writeln(
            '      return ((input ^ $salt) << ${shift % 5 + 1}) & 0x3fffffff;')
        ..writeln('    case 2:')
        ..writeln('      return ((input >> 1) + $salt) & 0x3fffffff;')
        ..writeln('    default:')
        ..writeln('      return ((input * ${shift + 3}) ^ $salt) & 0x3fffffff;')
        ..writeln('  }');
      break;
    case 3:
      buf
        ..writeln('  final values = <int>[')
        ..writeln('    input,')
        ..writeln('    input + $salt,')
        ..writeln('    input ^ $salt,')
        ..writeln('    input << ${shift % 4 + 1},')
        ..writeln('  ];')
        ..writeln('  return values.fold($salt, (acc, value) {')
        ..writeln('    return ((acc + value) ^ (value >> 1)) & 0x3fffffff;')
        ..writeln('  });');
      break;
    case 0:
    default:
      buf
        ..writeln('  final mixed = input + $salt;')
        ..writeln('  final folded = (mixed ^ (mixed << $shift)) & 0x3fffffff;')
        ..writeln('  return (folded + $salt + input) & 0x3fffffff;');
      break;
  }
  buf
    ..writeln('}')
    ..writeln();
}

String _shardFuncName(String filePath) {
  final base = p.posix.basenameWithoutExtension(filePath);
  final parts = base
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'dartNoiseShardF';
  final identifier = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    final normalized = part.substring(0, 1).toUpperCase() + part.substring(1);
    if (i == 0) {
      identifier.write(part.substring(0, 1).toLowerCase() + part.substring(1));
    } else {
      identifier.write(normalized);
    }
  }
  final value = identifier.toString();
  return RegExp(r'^[a-z]').hasMatch(value) ? value : 'noise$value';
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

List<String> _contentDirPlan(List<String> directories, int contentFileCount) {
  if (contentFileCount <= 0) return const [];
  if (directories.isEmpty) {
    throw StateError('No directories available for dart noise files.');
  }

  final contentDirs = <String>[];
  var remaining = contentFileCount;
  var startIndex = 1;
  if (contentFileCount.isOdd || directories.length == 1) {
    contentDirs.add(directories.first);
    remaining--;
  }

  final pairedDirs =
      directories.length > 1 ? directories.sublist(startIndex) : directories;
  var dirIndex = 0;
  while (remaining > 0) {
    final dir = pairedDirs[dirIndex % pairedDirs.length];
    contentDirs.add(dir);
    remaining--;
    if (remaining > 0) {
      contentDirs.add(dir);
      remaining--;
    }
    dirIndex++;
  }
  return contentDirs;
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

_StringMemberPlan _buildStringMemberPlan(
  ClassInnerStringNoiseConfig config,
  Random random, {
  required String prefix,
  required String className,
}) {
  if (!config.enabled) return _StringMemberPlan([]);
  final count = _randomInRange(
    random,
    config.memberStringCountPerClass.min,
    config.memberStringCountPerClass.max,
  );
  final strings = <_StringNoiseItem>[];
  for (var i = 0; i < count; i++) {
    strings.add(_renderStringNoiseItem(
      config,
      random,
      prefix: prefix,
      className: className,
      methodName: 'member',
      index: i,
    ));
  }
  return _StringMemberPlan(strings);
}

List<_StringNoiseItem> _buildLocalStringNoise(
  ClassInnerStringNoiseConfig config,
  Random random, {
  required String prefix,
  required String className,
  required String methodName,
}) {
  if (!config.enabled) return [];
  final count = _randomInRange(
    random,
    config.localStringCountPerHook.min,
    config.localStringCountPerHook.max,
  );
  return [
    for (var i = 0; i < count; i++)
      _renderStringNoiseItem(
        config,
        random,
        prefix: prefix,
        className: className,
        methodName: methodName,
        index: i,
      ),
  ];
}

_StringNoiseItem _renderStringNoiseItem(
  ClassInnerStringNoiseConfig config,
  Random random, {
  required String prefix,
  required String className,
  required String methodName,
  required int index,
}) {
  final template = _pickStringNoiseTemplate(config, random);
  final value = _fitStringNoiseLength(
    _renderTemplate(template.body, {
      'prefix': prefix.replaceFirst('_', ''),
      'className': className,
      'methodName': methodName,
      'seed': '${random.nextInt(900000) + 100000}',
      'word': _stringNoiseWords[random.nextInt(_stringNoiseWords.length)],
      'verb': _stringNoiseVerbs[random.nextInt(_stringNoiseVerbs.length)],
      'noun': _stringNoiseNouns[random.nextInt(_stringNoiseNouns.length)],
      'index': '$index',
    }),
    config,
    random,
  );
  return _StringNoiseItem(templateId: template.id, value: value);
}

NoiseTemplate _pickStringNoiseTemplate(
  ClassInnerStringNoiseConfig config,
  Random random,
) {
  final weighted = <NoiseTemplate>[];
  for (final template in config.templates) {
    final weight = config.templateWeights[template.id] ?? 1;
    for (var i = 0; i < weight; i++) {
      weighted.add(template);
    }
  }
  return weighted[random.nextInt(weighted.length)];
}

String _fitStringNoiseLength(
  String value,
  ClassInnerStringNoiseConfig config,
  Random random,
) {
  var result = value.trim();
  while (result.length < config.minLength) {
    result =
        '${result}_${_stringNoiseWords[random.nextInt(_stringNoiseWords.length)]}';
  }
  if (result.length > config.maxLength) {
    result = result.substring(0, config.maxLength);
  }
  return result;
}

String _dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
  return "'$escaped'";
}

String _classInnerMembersSource(
  String prefix,
  List<String> templates,
  Random random,
  _StringMemberPlan stringPlan,
) {
  final seed = random.nextInt(1 << 20) + 1;
  final buffer = StringBuffer()
    ..writeln('  $_classInnerMemberMarker')
    ..writeln('  static final int ${prefix}Seed = identityHashCode(\'$seed\');')
    ..writeln();
  if (!stringPlan.isEmpty) {
    for (var i = 0; i < stringPlan.strings.length; i++) {
      buffer.writeln(
          '  static const String ${prefix}Text$i = ${_dartStringLiteral(stringPlan.strings[i].value)};');
    }
    buffer.writeln('  static const List<String> ${prefix}Texts = [');
    for (var i = 0; i < stringPlan.strings.length; i++) {
      buffer.writeln('    ${prefix}Text$i,');
    }
    buffer
      ..writeln('  ];')
      ..writeln('  static const Map<String, String> ${prefix}TextMap = {');
    for (var i = 0; i < stringPlan.strings.length; i++) {
      buffer.writeln('    ${_dartStringLiteral('k$i')}: ${prefix}Text$i,');
    }
    buffer
      ..writeln('  };')
      ..writeln();
  }
  buffer
    ..writeln('  static int ${prefix}Retain(Object? seed) {')
    ..writeln('    final refs = <Object?>[');
  for (final template in templates.where(
      (template) => template != 'sync_hash' && template != 'sync_switch')) {
    buffer.writeln('      $prefix${_classInnerTemplateSuffix(template)},');
  }
  buffer
    ..writeln('    ];')
    ..writeln('    var value = ${prefix}SyncHash(seed) ^ refs.length;');
  if (!stringPlan.isEmpty) {
    buffer
      ..writeln('    value ^= ${prefix}Texts.length;')
      ..writeln('    value ^= ${prefix}Texts.first.hashCode;')
      ..writeln('    value ^= ${prefix}TextMap.length;');
  }
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
  _StringMemberPlan stringPlan,
) {
  return [
    '$className.${prefix}Seed',
    for (var i = 0; i < stringPlan.strings.length; i++)
      '$className.${prefix}Text$i',
    if (!stringPlan.isEmpty) '$className.${prefix}Texts',
    if (!stringPlan.isEmpty) '$className.${prefix}TextMap',
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
  required ClassInnerStringNoiseConfig stringNoise,
  required Random random,
  required String file,
  required List<Map<String, dynamic>> stringsInjected,
  required Set<String> stringTemplatesUsed,
}) {
  final localName = 'obfNoise${genRandomKey(6)}';
  final seed = isStatic
      ? "Object.hash('$className', '$methodName')"
      : 'identityHashCode(this)';
  final localStrings = _buildLocalStringNoise(
    stringNoise,
    random,
    prefix: prefix,
    className: className,
    methodName: methodName,
  );
  for (final item in localStrings) {
    stringTemplatesUsed.add(item.templateId);
    stringsInjected.add({
      'file': file,
      'class': className,
      'method': methodName,
      'kind': 'local',
      'templateId': item.templateId,
      'value': item.value,
    });
  }
  final buffer = StringBuffer()
    ..writeln()
    ..writeln();
  final textSeedName = 'obfTextSeed${genRandomKey(5)}';
  if (localStrings.isNotEmpty) {
    buffer.writeln('    var $textSeedName = $seed;');
  }
  for (var i = 0; i < localStrings.length; i++) {
    final textName = 'obfText${genRandomKey(6)}';
    buffer
      ..writeln(
          '    final $textName = ${_dartStringLiteral(localStrings[i].value)};')
      ..writeln(
          '    $textSeedName ^= $textName.codeUnits.fold<int>($seed, (value, unit) => ((value * 31) ^ unit) & 0x3fffffff);');
  }
  final retainSeed = localStrings.isEmpty ? seed : textSeedName;
  buffer.write('''

    final $localName = ${prefix}Retain($retainSeed); $_classInnerHookMarker
    if ($localName == -1) {
      ${prefix}Retain($localName);
    }
''');
  return buffer.toString();
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

  final insertOffset = _importInsertOffset(unit);
  final lines = _sortImportSpecs(missing).map(_importLineFromSpec).join('\n');
  final prefix = insertOffset == 0 ? '' : '\n';
  final suffix = source.startsWith('\n', insertOffset) ? '' : '\n';
  return _ImportInsertions(
    [_SourceInsertion(insertOffset, '$prefix$lines$suffix')],
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
  final match = RegExp(
    r'''import\s+['"]([^'"]+)['"]\s*(?:as\s+([A-Za-z_][A-Za-z0-9_]*))?\s*;''',
  ).firstMatch(line.trim());
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
