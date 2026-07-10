import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:obfuscateflutter/html_mapping_writer.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:path/path.dart' as p;

const _configFileName = 'obfuscate_dart_noise.json';
const _manifestStart = '<!-- obfuscateflutter: android-noise start -->';
const _manifestEnd = '<!-- obfuscateflutter: android-noise end -->';
const _defaultPackageSegment = 'platform';
const _activityResourceLayoutName = 'activity_resource_panel';
const _defaultClassTemplates = [
  'AnalyticsSession{{component}}',
  'PaymentRoute{{component}}',
  'CacheProfile{{component}}',
  'ContentSync{{component}}',
];
const _defaultMethodTemplates = [
  'collectSessionSignal',
  'mergePaymentRoute',
  'resolveCacheProfile',
  'traceContentSync',
];
const _defaultStringTemplates = [
  'session {{component}} payload {{index}}',
  'payment route {{className}} {{index}}',
  'cache profile {{methodName}} {{index}}',
  'content sync channel {{index}}',
];
const _defaultDeepPackageTemplates = [
  'account.{{word}}',
  'session.{{word}}',
  'profile.{{word}}',
  'payment.{{word}}',
];
const _defaultDeepClassTemplates = [
  'Session{{className}}',
  'Account{{className}}',
  'Profile{{className}}',
  'Payment{{className}}',
];
const _defaultDeepResourceTemplates = [
  'profile_{{name}}',
  'session_{{name}}',
  'account_{{name}}',
  'payment_{{name}}',
];
const _defaultDeepSemanticWords = [
  'profile',
  'session',
  'account',
  'payment',
  'cache',
  'route',
];
const _defaultSkipFiles = [
  '**/GeneratedPluginRegistrant.java',
  '**/GeneratedPluginRegistrant.kt',
  '**/MainActivity.java',
  '**/MainActivity.kt',
];
const _defaultSkipClasses = [
  'GeneratedPluginRegistrant',
  'MainActivity',
];
const _defaultSkipResources = [
  'ic_launcher*',
  'mipmap/ic_launcher*',
];
const _resourceReferenceTypes = {
  'anim',
  'color',
  'drawable',
  'layout',
  'menu',
  'mipmap',
  'xml',
  'style',
};
const _defaultSourceTemplates = {
  'activity': [
    '''
package {{packageName}};

import android.app.Activity;
import android.os.Bundle;
import java.util.ArrayList;
import java.util.List;

public class {{className}} extends Activity {
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    {{methodName}}(savedInstanceState);
    setContentView({{layoutResourceRef}});
  }

{{sharedMethods}}
}
''',
  ],
  'service': [
    '''
package {{packageName}};

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.IBinder;
import java.util.ArrayList;
import java.util.List;

public class {{className}} extends Service {
  @Override
  public IBinder onBind(Intent intent) {
    {{methodName}}(intent == null ? null : intent.getExtras());
    return null;
  }

  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    {{methodName}}(intent == null ? null : intent.getExtras());
    return START_NOT_STICKY;
  }

{{sharedMethods}}
}
''',
  ],
  'receiver': [
    '''
package {{packageName}};

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import java.util.ArrayList;
import java.util.List;

public class {{className}} extends BroadcastReceiver {
  @Override
  public void onReceive(Context context, Intent intent) {
    {{methodName}}(intent == null ? null : intent.getExtras());
  }

{{sharedMethods}}
}
''',
  ],
  'provider': [
    '''
package {{packageName}};

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import java.util.ArrayList;
import java.util.List;

public class {{className}} extends ContentProvider {
  @Override
  public boolean onCreate() {
    {{methodName}}(null);
    return true;
  }

  @Override
  public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
    {{methodName}}(null);
    return null;
  }

  @Override
  public String getType(Uri uri) {
    return "vnd.android.cursor.item/platform";
  }

  @Override
  public Uri insert(Uri uri, ContentValues values) {
    {{methodName}}(null);
    return uri;
  }

  @Override
  public int delete(Uri uri, String selection, String[] selectionArgs) {
    return {{methodName}}(null) & 1;
  }

  @Override
  public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
    return {{methodName}}(null) & 3;
  }

{{sharedMethods}}
}
''',
  ],
};
const _defaultDrawableTemplates = [
  {
    'name': 'activity_panel',
    'body': '''
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#01000000" />
    <size android:width="2dp" android:height="2dp" />
</shape>
''',
  },
];
const _defaultLayoutTemplates = [
  {
    'name': 'session_marker',
    'body': '''
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="1dp"
    android:layout_height="1dp"
    android:background="@drawable/{{drawableName}}" />
''',
  },
];
const _defaultStringValueTemplates = [
  {
    'name': 'session_title',
    'value': 'Session {{index}}',
  },
  {
    'name': 'profile_state',
    'value': 'Profile route {{packageName}}',
  },
];

void runAndroidNoiseGeneration(String projectPath) {
  final projectDir = Directory(projectPath);
  if (!projectDir.existsSync()) {
    throw StateError('Project directory not found: $projectPath');
  }

  final androidDir = Directory(p.join(projectPath, 'android'));
  if (!androidDir.existsSync()) {
    throw StateError('android project not found in $projectPath');
  }

  final mainDir = Directory(p.join(
    projectPath,
    'android',
    'app',
    'src',
    'main',
  ));
  if (!mainDir.existsSync()) {
    throw StateError('android app main source set not found: ${mainDir.path}');
  }

  final manifestFile = File(p.join(mainDir.path, 'AndroidManifest.xml'));
  if (!manifestFile.existsSync()) {
    throw StateError('AndroidManifest.xml not found: ${manifestFile.path}');
  }

  final config = AndroidNoiseConfig.load(projectPath);
  if (!config.enabled) {
    Log.log('Android noise generation is disabled by config.');
    return;
  }

  final namespace = _resolveNamespace(projectPath, manifestFile);
  final generated = _generateAndroidNoise(
    projectPath: projectPath,
    mainDir: mainDir,
    manifestFile: manifestFile,
    namespace: namespace,
    config: config,
  );
  final deepResult = config.deepObfuscation.enabled
      ? _runAndroidDeepObfuscation(
          projectPath: projectPath,
          mainDir: mainDir,
          manifestFile: manifestFile,
          namespace: namespace,
          config: config.deepObfuscation,
        )
      : _AndroidDeepObfuscationResult.empty();

  final mappingPath = writeHtmlFeatureMapping(
    projectPath: projectPath,
    featureId: 'android_noise',
    featureTitle: 'Android项目垃圾代码生成',
    mapping: {
      'generated_at': DateTime.now().toIso8601String(),
      'summary': {
        'generated_components': generated.components.length,
        'generated_resources': generated.resources.length,
        'manifest_entries': generated.manifestEntries.length,
        'package_renames': deepResult.packageRenames.length,
        'class_renames': deepResult.classRenames.length,
        'resource_renames': deepResult.resourceRenames.length,
        'reflection_rewrites': deepResult.reflectionRewrites.length,
        'skipped_items': deepResult.skippedItems.length,
        'warnings': deepResult.warnings.length,
      },
      'config': config.toJson(),
      'config_file': config.configSource,
      'namespace': namespace,
      'package': generated.packageName,
      'generated_components': generated.components,
      'generated_resources': generated.resources,
      'manifest_entries': generated.manifestEntries,
      'package_renames': deepResult.packageRenames,
      'class_renames': deepResult.classRenames,
      'resource_renames': deepResult.resourceRenames,
      'reflection_rewrites': deepResult.reflectionRewrites,
      'skipped_items': deepResult.skippedItems,
      'warnings': deepResult.warnings,
    },
  );

  Log.log('Android noise generation complete.');
  Log.log('Mapping document: $mappingPath');
}

class AndroidNoiseConfig {
  AndroidNoiseConfig({
    required this.enabled,
    required this.activityCount,
    required this.serviceCount,
    required this.receiverCount,
    required this.providerCount,
    required this.packageSegment,
    required this.classNameTemplates,
    required this.methodNameTemplates,
    required this.stringTemplates,
    required this.sourceTemplates,
    required this.generateXmlResources,
    required this.generateImageResources,
    required this.drawableXmlTemplates,
    required this.layoutXmlTemplates,
    required this.stringValueTemplates,
    required this.deepObfuscation,
    required this.configSource,
  });

  final bool enabled;
  final int activityCount;
  final int serviceCount;
  final int receiverCount;
  final int providerCount;
  final String packageSegment;
  final List<String> classNameTemplates;
  final List<String> methodNameTemplates;
  final List<String> stringTemplates;
  final Map<String, List<String>> sourceTemplates;
  final bool generateXmlResources;
  final bool generateImageResources;
  final List<AndroidXmlResourceTemplate> drawableXmlTemplates;
  final List<AndroidXmlResourceTemplate> layoutXmlTemplates;
  final List<AndroidStringResourceTemplate> stringValueTemplates;
  final AndroidDeepObfuscationConfig deepObfuscation;
  final String configSource;

  static AndroidNoiseConfig load(String projectPath) {
    final file = _resolveConfigFile(projectPath);
    var configSource = 'defaults';
    var json = <String, dynamic>{};
    if (file.existsSync()) {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        throw StateError('$_configFileName must contain a JSON object.');
      }
      json = decoded;
      configSource = p.equals(p.dirname(file.path), p.normalize(projectPath))
          ? 'project'
          : 'tool_default';
    }

    final value = json['androidNoise'];
    if (value == null) {
      return AndroidNoiseConfig.defaults(configSource);
    }
    if (value is! Map<String, dynamic>) {
      throw StateError('androidNoise must be a JSON object.');
    }

    final counts = value['componentCount'] is Map<String, dynamic>
        ? value['componentCount'] as Map<String, dynamic>
        : <String, dynamic>{};
    final nameTemplates = value['nameTemplates'] is Map<String, dynamic>
        ? value['nameTemplates'] as Map<String, dynamic>
        : <String, dynamic>{};
    final resources = value['generateResources'] is Map<String, dynamic>
        ? value['generateResources'] as Map<String, dynamic>
        : <String, dynamic>{};
    final sourceTemplates = value['sourceTemplates'] is Map<String, dynamic>
        ? value['sourceTemplates'] as Map<String, dynamic>
        : <String, dynamic>{};
    final resourceTemplates = value['resourceTemplates'] is Map<String, dynamic>
        ? value['resourceTemplates'] as Map<String, dynamic>
        : <String, dynamic>{};
    final deepObfuscation = value['deepObfuscation'] is Map<String, dynamic>
        ? value['deepObfuscation'] as Map<String, dynamic>
        : <String, dynamic>{};
    final packageSegment = value['packageSegment'] ?? _defaultPackageSegment;
    if (packageSegment is! String ||
        !_isPackageSegment(packageSegment.trim())) {
      throw StateError(
          'androidNoise.packageSegment must be a Java package segment.');
    }

    return AndroidNoiseConfig(
      enabled: value['enabled'] != false,
      activityCount: _readOptionalCount(counts, 'activity', 1),
      serviceCount: _readOptionalCount(counts, 'service', 1),
      receiverCount: _readOptionalCount(counts, 'receiver', 1),
      providerCount: _readOptionalCount(counts, 'provider', 1),
      packageSegment: packageSegment.trim(),
      classNameTemplates: _readTemplateList(
        nameTemplates,
        'classNames',
        _defaultClassTemplates,
      ),
      methodNameTemplates: _readTemplateList(
        nameTemplates,
        'methodNames',
        _defaultMethodTemplates,
      ),
      stringTemplates: _readTemplateList(
        value,
        'stringTemplates',
        _defaultStringTemplates,
      ),
      sourceTemplates: _readSourceTemplates(sourceTemplates),
      generateXmlResources: resources['xml'] != false,
      generateImageResources: resources['images'] != false,
      drawableXmlTemplates: _readXmlResourceTemplates(
        resourceTemplates,
        'drawableXml',
        _defaultDrawableTemplates,
      ),
      layoutXmlTemplates: _readXmlResourceTemplates(
        resourceTemplates,
        'layoutXml',
        _defaultLayoutTemplates,
      ),
      stringValueTemplates: _readStringResourceTemplates(
        resourceTemplates,
        'stringValues',
        _defaultStringValueTemplates,
      ),
      deepObfuscation: AndroidDeepObfuscationConfig.fromJson(deepObfuscation),
      configSource: configSource,
    );
  }

  factory AndroidNoiseConfig.defaults(String configSource) {
    return AndroidNoiseConfig(
      enabled: true,
      activityCount: 1,
      serviceCount: 1,
      receiverCount: 1,
      providerCount: 1,
      packageSegment: _defaultPackageSegment,
      classNameTemplates: List<String>.from(_defaultClassTemplates),
      methodNameTemplates: List<String>.from(_defaultMethodTemplates),
      stringTemplates: List<String>.from(_defaultStringTemplates),
      sourceTemplates: _cloneDefaultSourceTemplates(),
      generateXmlResources: true,
      generateImageResources: true,
      drawableXmlTemplates: _defaultDrawableTemplates
          .map(AndroidXmlResourceTemplate.fromDefault)
          .toList(),
      layoutXmlTemplates: _defaultLayoutTemplates
          .map(AndroidXmlResourceTemplate.fromDefault)
          .toList(),
      stringValueTemplates: _defaultStringValueTemplates
          .map(AndroidStringResourceTemplate.fromDefault)
          .toList(),
      deepObfuscation: AndroidDeepObfuscationConfig.defaults(),
      configSource: configSource,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'componentCount': {
        'activity': activityCount,
        'service': serviceCount,
        'receiver': receiverCount,
        'provider': providerCount,
      },
      'packageSegment': packageSegment,
      'nameTemplates': {
        'classNames': classNameTemplates,
        'methodNames': methodNameTemplates,
      },
      'stringTemplates': stringTemplates,
      'sourceTemplates': sourceTemplates,
      'generateResources': {
        'xml': generateXmlResources,
        'images': generateImageResources,
      },
      'resourceTemplates': {
        'drawableXml':
            drawableXmlTemplates.map((template) => template.toJson()).toList(),
        'layoutXml':
            layoutXmlTemplates.map((template) => template.toJson()).toList(),
        'stringValues':
            stringValueTemplates.map((template) => template.toJson()).toList(),
      },
      'deepObfuscation': deepObfuscation.toJson(),
      'configSource': configSource,
    };
  }
}

class AndroidDeepObfuscationConfig {
  AndroidDeepObfuscationConfig({
    required this.enabled,
    required this.skipFiles,
    required this.skipClasses,
    required this.skipPackages,
    required this.skipResources,
    required this.packageTemplates,
    required this.classTemplates,
    required this.resourceTemplates,
    required this.semanticWords,
    required this.reflectionRewriteEnabled,
    required this.reflectionRewriteStrict,
  });

  final bool enabled;
  final List<String> skipFiles;
  final List<String> skipClasses;
  final List<String> skipPackages;
  final List<String> skipResources;
  final List<String> packageTemplates;
  final List<String> classTemplates;
  final List<String> resourceTemplates;
  final List<String> semanticWords;
  final bool reflectionRewriteEnabled;
  final bool reflectionRewriteStrict;

  factory AndroidDeepObfuscationConfig.defaults() {
    return AndroidDeepObfuscationConfig(
      enabled: false,
      skipFiles: List<String>.from(_defaultSkipFiles),
      skipClasses: List<String>.from(_defaultSkipClasses),
      skipPackages: const [],
      skipResources: List<String>.from(_defaultSkipResources),
      packageTemplates: List<String>.from(_defaultDeepPackageTemplates),
      classTemplates: List<String>.from(_defaultDeepClassTemplates),
      resourceTemplates: List<String>.from(_defaultDeepResourceTemplates),
      semanticWords: List<String>.from(_defaultDeepSemanticWords),
      reflectionRewriteEnabled: true,
      reflectionRewriteStrict: true,
    );
  }

  factory AndroidDeepObfuscationConfig.fromJson(Map<String, dynamic> json) {
    final defaults = AndroidDeepObfuscationConfig.defaults();
    final reflection = json['reflectionRewrite'] is Map<String, dynamic>
        ? json['reflectionRewrite'] as Map<String, dynamic>
        : <String, dynamic>{};
    return AndroidDeepObfuscationConfig(
      enabled: json['enabled'] == true,
      skipFiles: _readMergedTemplateList(
        json,
        'skipFiles',
        defaults.skipFiles,
      ),
      skipClasses: _readMergedTemplateList(
        json,
        'skipClasses',
        defaults.skipClasses,
      ),
      skipPackages: _readMergedTemplateList(
        json,
        'skipPackages',
        defaults.skipPackages,
      ),
      skipResources: _readMergedTemplateList(
        json,
        'skipResources',
        defaults.skipResources,
      ),
      packageTemplates: _readTemplateList(
        json,
        'packageTemplates',
        defaults.packageTemplates,
      ),
      classTemplates: _readTemplateList(
        json,
        'classTemplates',
        defaults.classTemplates,
      ),
      resourceTemplates: _readTemplateList(
        json,
        'resourceTemplates',
        defaults.resourceTemplates,
      ),
      semanticWords: _readTemplateList(
        json,
        'semanticWords',
        defaults.semanticWords,
      ),
      reflectionRewriteEnabled: reflection['enabled'] != false,
      reflectionRewriteStrict: reflection['strict'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'skipFiles': skipFiles,
      'skipClasses': skipClasses,
      'skipPackages': skipPackages,
      'skipResources': skipResources,
      'packageTemplates': packageTemplates,
      'classTemplates': classTemplates,
      'resourceTemplates': resourceTemplates,
      'semanticWords': semanticWords,
      'reflectionRewrite': {
        'enabled': reflectionRewriteEnabled,
        'strict': reflectionRewriteStrict,
      },
    };
  }
}

class AndroidXmlResourceTemplate {
  AndroidXmlResourceTemplate({
    required this.name,
    required this.body,
  });

  final String name;
  final String body;

  factory AndroidXmlResourceTemplate.fromDefault(Map<String, String> json) {
    return AndroidXmlResourceTemplate(
      name: json['name']!,
      body: json['body']!,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'body': body,
    };
  }
}

class AndroidStringResourceTemplate {
  AndroidStringResourceTemplate({
    required this.name,
    required this.value,
  });

  final String name;
  final String value;

  factory AndroidStringResourceTemplate.fromDefault(
    Map<String, String> json,
  ) {
    return AndroidStringResourceTemplate(
      name: json['name']!,
      value: json['value']!,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'value': value,
    };
  }
}

class _GeneratedAndroidNoise {
  _GeneratedAndroidNoise({
    required this.packageName,
    required this.components,
    required this.resources,
    required this.manifestEntries,
  });

  final String packageName;
  final List<Map<String, dynamic>> components;
  final List<String> resources;
  final List<String> manifestEntries;
}

class _AndroidDeepObfuscationResult {
  _AndroidDeepObfuscationResult({
    required this.packageRenames,
    required this.classRenames,
    required this.resourceRenames,
    required this.reflectionRewrites,
    required this.skippedItems,
    required this.warnings,
  });

  final Map<String, String> packageRenames;
  final Map<String, String> classRenames;
  final Map<String, String> resourceRenames;
  final List<Map<String, String>> reflectionRewrites;
  final List<Map<String, String>> skippedItems;
  final List<String> warnings;

  factory _AndroidDeepObfuscationResult.empty() {
    return _AndroidDeepObfuscationResult(
      packageRenames: const {},
      classRenames: const {},
      resourceRenames: const {},
      reflectionRewrites: const [],
      skippedItems: const [],
      warnings: const [],
    );
  }
}

class _AndroidSourceSymbol {
  _AndroidSourceSymbol({
    required this.file,
    required this.relativePath,
    required this.packageName,
    required this.className,
    required this.extension,
  });

  final File file;
  final String relativePath;
  final String packageName;
  final String className;
  final String extension;

  String get fqcn => '$packageName.$className';
}

class _AndroidResourceSymbol {
  _AndroidResourceSymbol({
    required this.file,
    required this.relativePath,
    required this.type,
    required this.name,
    required this.extension,
  });

  final File file;
  final String relativePath;
  final String type;
  final String name;
  final String extension;

  String get key => '$type/$name';
}

class _ComponentSpec {
  _ComponentSpec({
    required this.type,
    required this.manifestTag,
    required this.baseClass,
    required this.className,
    required this.methodName,
    required this.index,
    required this.sourceTemplateOffset,
  });

  final String type;
  final String manifestTag;
  final String baseClass;
  final String className;
  final String methodName;
  final int index;
  final int sourceTemplateOffset;
}

_GeneratedAndroidNoise _generateAndroidNoise({
  required String projectPath,
  required Directory mainDir,
  required File manifestFile,
  required String namespace,
  required AndroidNoiseConfig config,
}) {
  final packageName = '$namespace.${config.packageSegment}';
  final packagePath = packageName.split('.');
  final javaDir = Directory(p.joinAll([
    mainDir.path,
    'java',
    ...packagePath,
  ]));
  javaDir.createSync(recursive: true);

  final resources = <String>[];
  if (config.generateXmlResources) {
    resources.addAll(_writeXmlResources(
      mainDir: mainDir,
      namespace: namespace,
      packageName: packageName,
      config: config,
    ));
  }
  if (config.generateImageResources) {
    resources.add(_writeImageResource(mainDir));
  }
  if (config.activityCount > 0) {
    resources.add(_writeActivityResourceLayout(mainDir, resources));
  }

  final specs = _buildComponentSpecs(config);
  final components = <Map<String, dynamic>>[];
  for (final spec in specs) {
    final file = File(p.join(javaDir.path, '${spec.className}.java'));
    file.writeAsStringSync(_javaSource(
      packageName: packageName,
      spec: spec,
      config: config,
    ));
    components.add({
      'type': spec.type,
      'class': '$packageName.${spec.className}',
      'file': _posixRelative(file.path, from: projectPath),
      'method': spec.methodName,
    });
  }

  final manifestEntries = specs
      .map((spec) => _manifestEntry(namespace, packageName, spec))
      .toList();
  _injectManifestEntries(manifestFile, manifestEntries);

  return _GeneratedAndroidNoise(
    packageName: packageName,
    components: components,
    resources: resources,
    manifestEntries: manifestEntries,
  );
}

_AndroidDeepObfuscationResult _runAndroidDeepObfuscation({
  required String projectPath,
  required Directory mainDir,
  required File manifestFile,
  required String namespace,
  required AndroidDeepObfuscationConfig config,
}) {
  final stopwatch = Stopwatch()..start();
  Log.log('Android deep obfuscation started.');
  final skipped = <Map<String, String>>[];
  final warnings = <String>[];
  final reflectionRewrites = <Map<String, String>>[];
  final sourceSymbols = _collectAndroidSourceSymbols(
    projectPath: projectPath,
    mainDir: mainDir,
    namespace: namespace,
    config: config,
    skipped: skipped,
  );
  Log.log(
      'Android deep obfuscation scan: source=${sourceSymbols.length}, skipped=${skipped.length}, elapsed=${stopwatch.elapsedMilliseconds}ms');
  final packageRenames = _buildPackageRenames(
    sourceSymbols,
    namespace,
    config,
  );
  final classRenames = _buildClassRenames(
    sourceSymbols,
    packageRenames,
    config,
  );
  final resources = _collectAndroidResourceSymbols(
    mainDir: mainDir,
    config: config,
    skipped: skipped,
  );
  final resourceRenames = _buildResourceRenames(resources, config);
  Log.log(
      'Android deep obfuscation scan: resources=${resources.length}, packageRenames=${packageRenames.length}, classRenames=${classRenames.length}, resourceRenames=${resourceRenames.length}, elapsed=${stopwatch.elapsedMilliseconds}ms');

  final rewrittenSources = _rewriteAndroidSourceFiles(
    sourceSymbols: sourceSymbols,
    packageRenames: packageRenames,
    classRenames: classRenames,
    resourceRenames: resourceRenames,
    config: config,
    reflectionRewrites: reflectionRewrites,
    warnings: warnings,
  );
  final rewrittenSkippedSources = _rewriteSkippedAndroidSourceFiles(
    projectPath: projectPath,
    mainDir: mainDir,
    sourceSymbols: sourceSymbols,
    namespace: namespace,
    packageRenames: packageRenames,
    classRenames: classRenames,
    resourceRenames: resourceRenames,
    config: config,
    reflectionRewrites: reflectionRewrites,
    warnings: warnings,
  );
  final rewrittenXml = _rewriteAndroidXmlFiles(
    mainDir: mainDir,
    manifestFile: manifestFile,
    classRenames: classRenames,
    resourceRenames: resourceRenames,
  );
  Log.log(
      'Android deep obfuscation rewrite: sourceFiles=$rewrittenSources, skippedSourceFiles=$rewrittenSkippedSources, xmlFiles=$rewrittenXml, reflectionRewrites=${reflectionRewrites.length}, warnings=${warnings.length}, elapsed=${stopwatch.elapsedMilliseconds}ms');
  final movedResources = _moveAndroidResources(resources, resourceRenames);
  final movedSources = _moveAndroidSourceFiles(
    mainDir: mainDir,
    sourceSymbols: sourceSymbols,
    packageRenames: packageRenames,
    classRenames: classRenames,
  );
  Log.log(
      'Android deep obfuscation move: sourceFiles=$movedSources, resources=$movedResources, elapsed=${stopwatch.elapsedMilliseconds}ms');
  Log.log(
      'Android deep obfuscation complete: elapsed=${stopwatch.elapsedMilliseconds}ms');

  return _AndroidDeepObfuscationResult(
    packageRenames: packageRenames,
    classRenames: classRenames,
    resourceRenames: resourceRenames,
    reflectionRewrites: reflectionRewrites,
    skippedItems: skipped,
    warnings: warnings,
  );
}

List<_AndroidSourceSymbol> _collectAndroidSourceSymbols({
  required String projectPath,
  required Directory mainDir,
  required String namespace,
  required AndroidDeepObfuscationConfig config,
  required List<Map<String, String>> skipped,
}) {
  final roots = [
    Directory(p.join(mainDir.path, 'java')),
    Directory(p.join(mainDir.path, 'kotlin')),
  ];
  final symbols = <_AndroidSourceSymbol>[];
  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final extension = p.extension(entity.path);
      if (extension != '.java' && extension != '.kt') continue;
      final relative = _posixRelative(entity.path, from: projectPath);
      if (_matchesAnyGlob(relative, config.skipFiles)) {
        skipped.add({
          'kind': 'file',
          'path': relative,
          'reason': 'matched skipFiles',
        });
        continue;
      }
      final source = entity.readAsStringSync();
      final packageName = _readAndroidPackage(source);
      final className = _readAndroidClassName(source, extension);
      if (packageName == null || className == null) continue;
      if (!packageName.startsWith(namespace)) continue;
      if (_matchesAnyGlob(className, config.skipClasses)) {
        skipped.add({
          'kind': 'class',
          'path': relative,
          'name': className,
          'reason': 'matched skipClasses',
        });
        continue;
      }
      if (_matchesAnyPackage(packageName, config.skipPackages)) {
        skipped.add({
          'kind': 'package',
          'path': relative,
          'name': packageName,
          'reason': 'matched skipPackages',
        });
        continue;
      }
      symbols.add(_AndroidSourceSymbol(
        file: entity,
        relativePath: relative,
        packageName: packageName,
        className: className,
        extension: extension,
      ));
    }
  }
  return symbols;
}

Map<String, String> _buildPackageRenames(
  List<_AndroidSourceSymbol> symbols,
  String namespace,
  AndroidDeepObfuscationConfig config,
) {
  final packages = symbols.map((symbol) => symbol.packageName).toSet().toList()
    ..sort();
  final result = <String, String>{};
  for (var i = 0; i < packages.length; i++) {
    final oldPackage = packages[i];
    final word = config.semanticWords[i % config.semanticWords.length];
    final template =
        config.packageTemplates[i % config.packageTemplates.length];
    final segment = template
        .replaceAll('{{word}}', _toPackageSegment(word))
        .replaceAll('{{index}}', i.toString())
        .replaceAll('{{packageName}}', oldPackage.split('.').last);
    final newPackage = '$namespace.$segment';
    if (newPackage != oldPackage) result[oldPackage] = newPackage;
  }
  return result;
}

Map<String, String> _buildClassRenames(
  List<_AndroidSourceSymbol> symbols,
  Map<String, String> packageRenames,
  AndroidDeepObfuscationConfig config,
) {
  final usedByPackage = <String, Set<String>>{};
  final result = <String, String>{};
  for (var i = 0; i < symbols.length; i++) {
    final symbol = symbols[i];
    final template = config.classTemplates[i % config.classTemplates.length];
    final raw = template
        .replaceAll('{{className}}', symbol.className)
        .replaceAll(
            '{{word}}', config.semanticWords[i % config.semanticWords.length])
        .replaceAll('{{index}}', i.toString());
    final newClassName = _uniqueName(
      _toJavaIdentifier(raw, upperCamel: true),
      usedByPackage.putIfAbsent(
        packageRenames[symbol.packageName] ?? symbol.packageName,
        () => <String>{},
      ),
    );
    if (newClassName != symbol.className) {
      result[symbol.fqcn] =
          '${packageRenames[symbol.packageName] ?? symbol.packageName}.$newClassName';
    }
  }
  return result;
}

List<_AndroidResourceSymbol> _collectAndroidResourceSymbols({
  required Directory mainDir,
  required AndroidDeepObfuscationConfig config,
  required List<Map<String, String>> skipped,
}) {
  final resDir = Directory(p.join(mainDir.path, 'res'));
  if (!resDir.existsSync()) return const [];
  final symbols = <_AndroidResourceSymbol>[];
  for (final entity in resDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final parent = p.basename(p.dirname(entity.path));
    final type = parent.split('-').first;
    if (!_resourceReferenceTypes.contains(type)) continue;
    final name = p.basenameWithoutExtension(entity.path);
    final extension = p.extension(entity.path);
    final relative = _posixRelative(entity.path, from: mainDir.path);
    if (_matchesAnyResource(type, name, config.skipResources)) {
      skipped.add({
        'kind': 'resource',
        'path': relative,
        'name': '$type/$name',
        'reason': 'matched skipResources',
      });
      continue;
    }
    symbols.add(_AndroidResourceSymbol(
      file: entity,
      relativePath: relative,
      type: type,
      name: name,
      extension: extension,
    ));
  }
  return symbols;
}

Map<String, String> _buildResourceRenames(
  List<_AndroidResourceSymbol> symbols,
  AndroidDeepObfuscationConfig config,
) {
  final usedByType = <String, Set<String>>{};
  final result = <String, String>{};
  for (var i = 0; i < symbols.length; i++) {
    final symbol = symbols[i];
    final template =
        config.resourceTemplates[i % config.resourceTemplates.length];
    final raw = template
        .replaceAll('{{name}}', symbol.name)
        .replaceAll('{{type}}', symbol.type)
        .replaceAll(
            '{{word}}', config.semanticWords[i % config.semanticWords.length])
        .replaceAll('{{index}}', i.toString());
    var newName = _toAndroidResourceName(raw);
    final used = usedByType.putIfAbsent(symbol.type, () => <String>{});
    final base = newName;
    var suffix = 1;
    while (used.contains(newName)) {
      newName = '${base}_$suffix';
      suffix++;
    }
    used.add(newName);
    if (newName != symbol.name) {
      result[symbol.key] = '${symbol.type}/$newName';
    }
  }
  return result;
}

int _rewriteAndroidSourceFiles({
  required List<_AndroidSourceSymbol> sourceSymbols,
  required Map<String, String> packageRenames,
  required Map<String, String> classRenames,
  required Map<String, String> resourceRenames,
  required AndroidDeepObfuscationConfig config,
  required List<Map<String, String>> reflectionRewrites,
  required List<String> warnings,
}) {
  final classRenameEntries = _sortedClassRenameEntries(classRenames);
  var processed = 0;
  var rewrittenFiles = 0;
  for (final symbol in sourceSymbols) {
    var source = symbol.file.readAsStringSync();
    final original = source;
    source = _rewritePackageDeclarations(source, packageRenames);
    source = _rewriteImportsAndTypeNames(
      source,
      packageRenames,
      classRenames,
      classRenameEntries,
      currentClassFqcn: symbol.fqcn,
      currentPackageName: symbol.packageName,
    );
    source = _rewriteResourceReferencesInCode(source, resourceRenames);
    if (config.reflectionRewriteEnabled) {
      source = _rewriteReflectionReferences(
        source: source,
        classRenames: classRenames,
        strict: config.reflectionRewriteStrict,
        reflectionRewrites: reflectionRewrites,
      );
      warnings.addAll(_findConcatenatedReflectionWarnings(source));
    }
    if (source != original) {
      symbol.file.writeAsStringSync(source);
      rewrittenFiles++;
    }
    processed++;
    if (processed % 50 == 0) {
      Log.log(
          'Android deep obfuscation rewrite: processed source files=$processed');
    }
  }
  return rewrittenFiles;
}

int _rewriteSkippedAndroidSourceFiles({
  required String projectPath,
  required Directory mainDir,
  required List<_AndroidSourceSymbol> sourceSymbols,
  required String namespace,
  required Map<String, String> packageRenames,
  required Map<String, String> classRenames,
  required Map<String, String> resourceRenames,
  required AndroidDeepObfuscationConfig config,
  required List<Map<String, String>> reflectionRewrites,
  required List<String> warnings,
}) {
  final includedPaths = sourceSymbols.map((symbol) => symbol.file.path).toSet();
  final classRenameEntries = _sortedClassRenameEntries(classRenames);
  var rewrittenFiles = 0;
  for (final rootName in const ['java', 'kotlin']) {
    final root = Directory(p.join(mainDir.path, rootName));
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || includedPaths.contains(entity.path)) continue;
      final extension = p.extension(entity.path);
      if (extension != '.java' && extension != '.kt') continue;
      final source = entity.readAsStringSync();
      final packageName = _readAndroidPackage(source);
      final className = _readAndroidClassName(source, extension);
      if (packageName == null || className == null) continue;
      if (!packageName.startsWith(namespace)) continue;
      var updated = _rewriteImportsAndTypeNames(
        source,
        packageRenames,
        classRenames,
        classRenameEntries,
        rewriteDeclarations: false,
        currentPackageName: packageName,
      );
      updated = _rewriteResourceReferencesInCode(updated, resourceRenames);
      if (config.reflectionRewriteEnabled) {
        updated = _rewriteReflectionReferences(
          source: updated,
          classRenames: classRenames,
          strict: config.reflectionRewriteStrict,
          reflectionRewrites: reflectionRewrites,
        );
        warnings.addAll(_findConcatenatedReflectionWarnings(updated));
      }
      if (updated != source) {
        entity.writeAsStringSync(updated);
        rewrittenFiles++;
      }
    }
  }
  return rewrittenFiles;
}

int _rewriteAndroidXmlFiles({
  required Directory mainDir,
  required File manifestFile,
  required Map<String, String> classRenames,
  required Map<String, String> resourceRenames,
}) {
  final classRenameEntries = _sortedClassRenameEntries(classRenames);
  final files = <File>[manifestFile];
  final resDir = Directory(p.join(mainDir.path, 'res'));
  if (resDir.existsSync()) {
    files.addAll(resDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.xml'));
  }
  for (final file in files) {
    final source = file.readAsStringSync();
    final updated = _rewriteXmlOutsideComments(
      source,
      (segment) => _rewriteXmlSegment(
        segment,
        classRenameEntries: classRenameEntries,
        resourceRenames: resourceRenames,
      ),
    );
    if (updated != source) {
      file.writeAsStringSync(updated);
    }
  }
  return files.length;
}

int _moveAndroidResources(
  List<_AndroidResourceSymbol> symbols,
  Map<String, String> resourceRenames,
) {
  var moved = 0;
  for (final symbol in symbols) {
    final newKey = resourceRenames[symbol.key];
    if (newKey == null) continue;
    final newName = newKey.split('/').last;
    final target = File(p.join(
      p.dirname(symbol.file.path),
      '$newName${symbol.extension}',
    ));
    if (target.path == symbol.file.path) continue;
    target.parent.createSync(recursive: true);
    symbol.file.renameSync(target.path);
    moved++;
  }
  return moved;
}

int _moveAndroidSourceFiles({
  required Directory mainDir,
  required List<_AndroidSourceSymbol> sourceSymbols,
  required Map<String, String> packageRenames,
  required Map<String, String> classRenames,
}) {
  var moved = 0;
  for (final symbol in sourceSymbols) {
    final oldFqcn = symbol.fqcn;
    final newClassFqcn = classRenames[oldFqcn] ?? oldFqcn;
    final newClassName = newClassFqcn.split('.').last;
    final newPackage = packageRenames[symbol.packageName] ?? symbol.packageName;
    final sourceRoot =
        symbol.file.path.contains('/kotlin/') ? 'kotlin' : 'java';
    final target = File(p.joinAll([
      mainDir.path,
      sourceRoot,
      ...newPackage.split('.'),
      '$newClassName${symbol.extension}',
    ]));
    if (target.path == symbol.file.path) continue;
    target.parent.createSync(recursive: true);
    symbol.file.renameSync(target.path);
    moved++;
  }
  return moved;
}

List<_ComponentSpec> _buildComponentSpecs(AndroidNoiseConfig config) {
  final specs = <_ComponentSpec>[];
  final usedClassNames = <String>{};
  final usedMethodNames = <String>{};
  void add(String type, String tag, String baseClass, int count) {
    final sourceTemplateCount = config.sourceTemplates[type]?.length ?? 1;
    final sourceTemplateOffset =
        sourceTemplateCount <= 1 ? 0 : Random().nextInt(sourceTemplateCount);
    for (var i = 0; i < count; i++) {
      final className = _uniqueName(
        _renderClassName(config.classNameTemplates, type, i),
        usedClassNames,
      );
      final methodName = _uniqueName(
        _renderMethodName(config.methodNameTemplates, i),
        usedMethodNames,
        lowerCamel: true,
      );
      specs.add(_ComponentSpec(
        type: type,
        manifestTag: tag,
        baseClass: baseClass,
        className: className,
        methodName: methodName,
        index: i,
        sourceTemplateOffset: sourceTemplateOffset,
      ));
    }
  }

  add('activity', 'activity', 'Activity', config.activityCount);
  add('service', 'service', 'Service', config.serviceCount);
  add('receiver', 'receiver', 'BroadcastReceiver', config.receiverCount);
  add('provider', 'provider', 'ContentProvider', config.providerCount);
  return specs;
}

String _javaSource({
  required String packageName,
  required _ComponentSpec spec,
  required AndroidNoiseConfig config,
}) {
  final templates = config.sourceTemplates[spec.type];
  if (templates == null || templates.isEmpty) {
    throw StateError('Unsupported Android component: ${spec.type}');
  }
  final template = _selectSourceTemplate(templates, spec);
  return _renderSourceTemplate(
    template,
    packageName: packageName,
    spec: spec,
    config: config,
  );
}

String _sharedMethods(
  _ComponentSpec spec,
  AndroidNoiseConfig config,
  String parameter,
) {
  final label = _renderStringTemplate(
    config.stringTemplates[spec.index % config.stringTemplates.length],
    spec,
  );
  return '''
  private int ${spec.methodName}($parameter) {
    StringBuilder builder = new StringBuilder("$label");
    List<String> segments = new ArrayList<>();
    segments.add("${spec.type}");
    segments.add("${spec.className}");
    segments.add("${spec.methodName}");
    if (bundle != null) {
      for (String key : bundle.keySet()) {
        Object value = bundle.get(key);
        segments.add(key + ":" + String.valueOf(value));
      }
    }
    int checksum = builder.length();
    for (String segment : segments) {
      checksum = (checksum * 31) ^ segment.hashCode();
      builder.append('|').append(segment);
    }
    return checksum ^ builder.toString().hashCode();
  }

  private String ${spec.methodName}Label(int seed) {
    StringBuilder builder = new StringBuilder("${spec.className}");
    builder.append('#').append(seed);
    builder.append(':').append("${spec.type}");
    return builder.toString();
  }
''';
}

String _manifestEntry(
    String namespace, String packageName, _ComponentSpec spec) {
  final classRef = '$packageName.${spec.className}';
  final common =
      'android:name="$classRef"\n            android:exported="false"';
  if (spec.type == 'activity') {
    return '''        <activity
            $common
            android:theme="@style/ActivityPanelTheme" />''';
  }
  if (spec.type == 'provider') {
    return '''        <provider
            $common
            android:authorities="$namespace.${spec.className}.provider" />''';
  }
  return '''        <${spec.manifestTag}
            $common />''';
}

String? _androidResourceRef(String resourcePath) {
  final normalized = resourcePath.replaceAll(r'\', '/');
  final match = RegExp(r'(^|/)res/(drawable|layout)/([^/]+)\.[A-Za-z0-9]+$')
      .firstMatch(normalized);
  if (match == null) return null;
  return '@${match.group(2)}/${match.group(3)}';
}

void _injectManifestEntries(File manifestFile, List<String> entries) {
  final source = manifestFile.readAsStringSync();
  final block = [
    _manifestStart,
    ...entries,
    _manifestEnd,
  ].join('\n');
  final markerPattern = RegExp(
    '${RegExp.escape(_manifestStart)}[\\s\\S]*?${RegExp.escape(_manifestEnd)}',
  );

  var updated = source;
  if (markerPattern.hasMatch(updated)) {
    updated = updated.replaceFirst(markerPattern, block);
  } else {
    final appClose = updated.lastIndexOf('</application>');
    if (appClose < 0) {
      throw StateError(
          'AndroidManifest.xml must contain an <application> node.');
    }
    updated = updated.replaceRange(appClose, appClose, '    $block\n');
  }
  manifestFile.writeAsStringSync(updated);
}

List<String> _writeXmlResources({
  required Directory mainDir,
  required String namespace,
  required String packageName,
  required AndroidNoiseConfig config,
}) {
  final drawableDir = Directory(p.join(mainDir.path, 'res', 'drawable'));
  final valuesDir = Directory(p.join(mainDir.path, 'res', 'values'));
  final layoutDir = Directory(p.join(mainDir.path, 'res', 'layout'));
  drawableDir.createSync(recursive: true);
  valuesDir.createSync(recursive: true);
  layoutDir.createSync(recursive: true);

  final generated = <String>[];
  final firstDrawableName = config.drawableXmlTemplates.isEmpty
      ? 'activity_panel'
      : config.drawableXmlTemplates.first.name;
  for (var i = 0; i < config.drawableXmlTemplates.length; i++) {
    final template = config.drawableXmlTemplates[i];
    final file = File(p.join(drawableDir.path, '${template.name}.xml'));
    file.writeAsStringSync(_renderResourceTemplate(
      template.body,
      namespace: namespace,
      packageName: packageName,
      resourceName: template.name,
      drawableName: firstDrawableName,
      index: i,
    ));
    generated.add(_posixRelative(
      file.path,
      from: p.dirname(p.dirname(mainDir.path)),
    ));
  }

  final styles = File(p.join(valuesDir.path, 'activity_panel_styles.xml'));
  styles.writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="ActivityPanelTheme" parent="@android:style/Theme.Translucent.NoTitleBar">
        <item name="android:windowIsTranslucent">true</item>
        <item name="android:windowNoTitle">true</item>
        <item name="android:colorAccent">#01000000</item>
    </style>
</resources>
''');
  generated.add(_posixRelative(
    styles.path,
    from: p.dirname(p.dirname(mainDir.path)),
  ));

  if (config.stringValueTemplates.isNotEmpty) {
    final strings = File(p.join(valuesDir.path, 'strings.xml'));
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<resources>');
    final writtenStringNames = <String>{};
    for (var i = 0; i < config.stringValueTemplates.length; i++) {
      final template = config.stringValueTemplates[i];
      if (!writtenStringNames.add(template.name)) {
        continue;
      }
      final value = _renderResourceTemplate(
        template.value,
        namespace: namespace,
        packageName: packageName,
        resourceName: template.name,
        drawableName: firstDrawableName,
        index: i,
      );
      buffer.writeln(
        '    <string name="${template.name}">${_escapeXmlText(value)}</string>',
      );
    }
    buffer.writeln('</resources>');
    strings.writeAsStringSync(buffer.toString());
    generated.add(_posixRelative(
      strings.path,
      from: p.dirname(p.dirname(mainDir.path)),
    ));
  }

  for (var i = 0; i < config.layoutXmlTemplates.length; i++) {
    final template = config.layoutXmlTemplates[i];
    final file = File(p.join(layoutDir.path, '${template.name}.xml'));
    file.writeAsStringSync(_renderResourceTemplate(
      template.body,
      namespace: namespace,
      packageName: packageName,
      resourceName: template.name,
      drawableName: firstDrawableName,
      index: i,
    ));
    generated.add(_posixRelative(
      file.path,
      from: p.dirname(p.dirname(mainDir.path)),
    ));
  }

  return generated;
}

String _writeImageResource(Directory mainDir) {
  final drawableDir = Directory(p.join(mainDir.path, 'res', 'drawable'));
  drawableDir.createSync(recursive: true);
  final image = img.Image(width: 4, height: 4);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, 1 + x, 1 + y, 1, 1);
    }
  }
  final file = File(p.join(drawableDir.path, 'profile_badge.png'));
  file.writeAsBytesSync(img.encodePng(image));
  return _posixRelative(file.path, from: p.dirname(p.dirname(mainDir.path)));
}

String _writeActivityResourceLayout(
  Directory mainDir,
  List<String> resources,
) {
  final layoutDir = Directory(p.join(mainDir.path, 'res', 'layout'));
  layoutDir.createSync(recursive: true);
  final refs = resources
      .map(_androidResourceRef)
      .whereType<String>()
      .where((ref) => ref != '@layout/$_activityResourceLayoutName')
      .toList();
  final children = <String>[];
  for (var i = 0; i < refs.length; i++) {
    final ref = refs[i];
    if (ref.startsWith('@layout/')) {
      children.add('''
    <include
        android:id="@+id/resource_panel_include_$i"
        layout="$ref" />''');
    } else {
      children.add('''
    <ImageView
        android:id="@+id/resource_panel_drawable_$i"
        android:layout_width="1dp"
        android:layout_height="1dp"
        android:alpha="0.01"
        android:contentDescription="@null"
        android:src="$ref" />''');
    }
  }
  final file = File(p.join(layoutDir.path, '$_activityResourceLayoutName.xml'));
  file.writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="1dp"
    android:layout_height="1dp"
    android:visibility="gone">
${children.join('\n')}
</FrameLayout>
''');
  return _posixRelative(file.path, from: p.dirname(p.dirname(mainDir.path)));
}

String _resolveNamespace(String projectPath, File manifestFile) {
  final gradleFiles = [
    File(p.join(projectPath, 'android', 'app', 'build.gradle')),
    File(p.join(projectPath, 'android', 'app', 'build.gradle.kts')),
  ];
  for (final file in gradleFiles) {
    if (!file.existsSync()) continue;
    final source = file.readAsStringSync();
    final match = RegExp(
      r'''namespace\s*(?:=)?\s*['"]([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)['"]''',
    ).firstMatch(source);
    if (match != null) return match.group(1)!;
  }

  final manifest = manifestFile.readAsStringSync();
  final packageMatch = RegExp(
    r'''<manifest\b[^>]*\bpackage\s*=\s*['"]([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)['"]''',
  ).firstMatch(manifest);
  if (packageMatch != null) return packageMatch.group(1)!;

  throw StateError('Android namespace not found. Add android.namespace in '
      'android/app/build.gradle or a manifest package attribute.');
}

File _resolveConfigFile(String projectPath) {
  final projectConfig = File(p.join(projectPath, _configFileName));
  if (projectConfig.existsSync()) return projectConfig;
  return File(p.join(Directory.current.path, _configFileName));
}

String? _readAndroidPackage(String source) {
  return RegExp(
    r'^\s*package\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*;?',
    multiLine: true,
  ).firstMatch(source)?.group(1);
}

String? _readAndroidClassName(String source, String extension) {
  final publicMatch = RegExp(
    r'\bpublic\s+(?:final\s+|open\s+|abstract\s+|data\s+|sealed\s+)?(?:class|interface|enum|object)\s+([A-Za-z_][A-Za-z0-9_]*)',
  ).firstMatch(source);
  if (publicMatch != null) return publicMatch.group(1);
  return RegExp(
    r'\b(?:class|interface|enum|object)\s+([A-Za-z_][A-Za-z0-9_]*)',
  ).firstMatch(source)?.group(1);
}

String _rewritePackageDeclarations(
  String source,
  Map<String, String> packageRenames,
) {
  return source.replaceAllMapped(
    RegExp(
      r'^(\s*package\s+)([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)(\s*;?)',
      multiLine: true,
    ),
    (match) => '${match.group(1)}'
        '${packageRenames[match.group(2)] ?? match.group(2)}'
        '${match.group(3)}',
  );
}

String _rewriteImportsAndTypeNames(
  String source,
  Map<String, String> packageRenames,
  Map<String, String> classRenames,
  List<MapEntry<String, String>> classRenameEntries, {
  bool rewriteDeclarations = true,
  String? currentClassFqcn,
  String? currentPackageName,
}) {
  final simpleClassRenames = _buildSimpleClassRenameMap(
    source,
    classRenameEntries,
    currentClassFqcn: rewriteDeclarations ? currentClassFqcn : null,
    currentPackageName: currentPackageName,
  );
  var updated = source.replaceAllMapped(
    RegExp(
      r'^(\s*import\s+)([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)(\s*;?)',
      multiLine: true,
    ),
    (match) {
      final oldImport = match.group(2)!;
      final packageName = oldImport
          .split('.')
          .sublist(0, oldImport.split('.').length - 1)
          .join('.');
      final className = oldImport.split('.').last;
      final renamedClass = classRenames[oldImport];
      if (renamedClass != null) {
        final newPackage = packageRenames[packageName] ??
            renamedClass
                .split('.')
                .sublist(0, renamedClass.split('.').length - 1)
                .join('.');
        return '${match.group(1)}$newPackage.${renamedClass.split('.').last}${match.group(3)}';
      }
      final renamedPackage = packageRenames[oldImport];
      if (renamedPackage != null) {
        return '${match.group(1)}$renamedPackage${match.group(3)}';
      }
      if (packageRenames.containsKey(packageName)) {
        return '${match.group(1)}${packageRenames[packageName]}.$className${match.group(3)}';
      }
      return match.group(0)!;
    },
  );

  updated = _rewriteCodeOutsideStrings(updated, (segment) {
    var rewritten = segment;
    for (final entry in classRenameEntries) {
      final oldClassName = entry.key.split('.').last;
      if (!rewritten.contains(entry.key) && !rewritten.contains(oldClassName)) {
        continue;
      }
      final oldFqcn = RegExp.escape(entry.key);
      rewritten = rewritten.replaceAllMapped(
        RegExp('(^|[^A-Za-z0-9_])$oldFqcn(?![A-Za-z0-9_])'),
        (match) => '${match.group(1)}${entry.value}',
      );
      if (rewriteDeclarations && entry.key == currentClassFqcn) {
        rewritten = rewritten.replaceAllMapped(
          RegExp(r'\b(class|interface|enum|object)\s+' +
              RegExp.escape(entry.key.split('.').last) +
              r'\b'),
          (match) => '${match.group(1)} ${entry.value.split('.').last}',
        );
        rewritten = _rewriteJavaConstructors(
          rewritten,
          oldClassName: entry.key.split('.').last,
          newClassName: entry.value.split('.').last,
        );
      }
    }
    for (final entry in simpleClassRenames.entries) {
      rewritten = _rewriteSimpleClassReferences(
        rewritten,
        oldClassName: entry.key,
        newClassName: entry.value,
      );
    }
    return rewritten;
  });
  return updated;
}

Map<String, String> _buildSimpleClassRenameMap(
  String source,
  List<MapEntry<String, String>> classRenameEntries, {
  String? currentClassFqcn,
  String? currentPackageName,
}) {
  final simpleNameCounts = <String, int>{};
  for (final entry in classRenameEntries) {
    final simpleName = entry.key.split('.').last;
    simpleNameCounts[simpleName] = (simpleNameCounts[simpleName] ?? 0) + 1;
  }

  final importedClasses = RegExp(
    r'^\s*import\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s*;?',
    multiLine: true,
  ).allMatches(source).map((match) => match.group(1)!).toSet();

  final result = <String, String>{};
  final conflicts = <String>{};
  for (final entry in classRenameEntries) {
    final oldSimpleName = entry.key.split('.').last;
    final newSimpleName = entry.value.split('.').last;
    final oldPackageName =
        entry.key.substring(0, entry.key.length - oldSimpleName.length - 1);
    final shouldRewriteSimpleName = entry.key == currentClassFqcn ||
        importedClasses.contains(entry.key) ||
        oldPackageName == currentPackageName ||
        simpleNameCounts[oldSimpleName] == 1;
    if (!shouldRewriteSimpleName) continue;

    final existing = result[oldSimpleName];
    if (existing != null && existing != newSimpleName) {
      result.remove(oldSimpleName);
      conflicts.add(oldSimpleName);
      continue;
    }
    if (!conflicts.contains(oldSimpleName)) {
      result[oldSimpleName] = newSimpleName;
    }
  }
  return result;
}

String _rewriteSimpleClassReferences(
  String source, {
  required String oldClassName,
  required String newClassName,
}) {
  if (oldClassName == newClassName) return source;
  return source.replaceAllMapped(
    RegExp(r'\b' + RegExp.escape(oldClassName) + r'\b'),
    (_) => newClassName,
  );
}

String _rewriteJavaConstructors(
  String source, {
  required String oldClassName,
  required String newClassName,
}) {
  if (oldClassName == newClassName) return source;
  final constructorPattern = RegExp(
    r'(^|[;\{\}\n]\s*)((?:public|protected|private)\s+)?' +
        RegExp.escape(oldClassName) +
        r'(\s*\()',
  );
  return source.replaceAllMapped(
    constructorPattern,
    (match) =>
        '${match.group(1)}${match.group(2) ?? ''}$newClassName${match.group(3)}',
  );
}

String _rewriteResourceReferencesInCode(
  String source,
  Map<String, String> resourceRenames,
) {
  return source.replaceAllMapped(
    RegExp(r'\bR\.([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\b'),
    (match) {
      final key = '${match.group(1)}/${match.group(2)}';
      final renamed = resourceRenames[key];
      if (renamed == null) return match.group(0)!;
      return 'R.${match.group(1)}.${renamed.split('/').last}';
    },
  );
}

String _rewriteReflectionReferences({
  required String source,
  required Map<String, String> classRenames,
  required bool strict,
  required List<Map<String, String>> reflectionRewrites,
}) {
  var updated = source;
  String replacementFor(String oldName) => classRenames[oldName] ?? oldName;
  void record(String api, String oldName, String newName) {
    if (oldName == newName) return;
    reflectionRewrites.add({
      'api': api,
      'from': oldName,
      'to': newName,
    });
  }

  updated = updated.replaceAllMapped(
    RegExp(r'(Class\.forName\s*\(\s*")([^"]+)(")'),
    (match) {
      final oldName = match.group(2)!;
      final newName = replacementFor(oldName);
      record('Class.forName', oldName, newName);
      return '${match.group(1)}$newName${match.group(3)}';
    },
  );
  updated = updated.replaceAllMapped(
    RegExp(
        r'((?:getClassLoader\(\)|[A-Za-z_][A-Za-z0-9_]*ClassLoader|classLoader)\.loadClass\s*\(\s*")([^"]+)(")'),
    (match) {
      final oldName = match.group(2)!;
      final newName = replacementFor(oldName);
      record('ClassLoader.loadClass', oldName, newName);
      return '${match.group(1)}$newName${match.group(3)}';
    },
  );
  updated = updated.replaceAllMapped(
    RegExp(r'(\.setClassName\s*\(\s*[^,]+,\s*")([^"]+)(")'),
    (match) {
      final oldName = match.group(2)!;
      final newName = replacementFor(oldName);
      record('Intent.setClassName', oldName, newName);
      return '${match.group(1)}$newName${match.group(3)}';
    },
  );
  updated = updated.replaceAllMapped(
    RegExp(r'(ComponentName\s*\(\s*[^,]+,\s*")([^"]+)(")'),
    (match) {
      final oldName = match.group(2)!;
      final newName = replacementFor(oldName);
      record('ComponentName', oldName, newName);
      return '${match.group(1)}$newName${match.group(3)}';
    },
  );

  if (!strict) {
    for (final entry in classRenames.entries) {
      updated = updated.replaceAll('"${entry.key}"', '"${entry.value}"');
    }
  }
  return updated;
}

String _rewriteCodeOutsideStrings(
  String source,
  String Function(String segment) rewrite,
) {
  final buffer = StringBuffer();
  final segment = StringBuffer();
  var i = 0;
  var inDouble = false;
  var inSingle = false;
  var inLineComment = false;
  var inBlockComment = false;
  var escaped = false;

  void flushSegment() {
    if (segment.isNotEmpty) {
      buffer.write(rewrite(segment.toString()));
      segment.clear();
    }
  }

  while (i < source.length) {
    final char = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';

    if (inLineComment) {
      buffer.write(char);
      if (char == '\n') inLineComment = false;
      i++;
      continue;
    }
    if (inBlockComment) {
      buffer.write(char);
      if (char == '*' && next == '/') {
        buffer.write(next);
        inBlockComment = false;
        i += 2;
      } else {
        i++;
      }
      continue;
    }
    if (inDouble || inSingle) {
      buffer.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (inDouble && char == '"') {
        inDouble = false;
      } else if (inSingle && char == "'") {
        inSingle = false;
      }
      i++;
      continue;
    }

    if (char == '/' && next == '/') {
      flushSegment();
      buffer.write(char);
      buffer.write(next);
      inLineComment = true;
      i += 2;
      continue;
    }
    if (char == '/' && next == '*') {
      flushSegment();
      buffer.write(char);
      buffer.write(next);
      inBlockComment = true;
      i += 2;
      continue;
    }
    if (char == '"') {
      flushSegment();
      buffer.write(char);
      inDouble = true;
      i++;
      continue;
    }
    if (char == "'") {
      flushSegment();
      buffer.write(char);
      inSingle = true;
      i++;
      continue;
    }

    segment.write(char);
    i++;
  }
  flushSegment();
  return buffer.toString();
}

List<String> _findConcatenatedReflectionWarnings(String source) {
  final warnings = <String>[];
  final pattern = RegExp(
      r'(Class\.forName|loadClass|setClassName|ComponentName)\s*\([^)]*"[^"]*"\s*\+');
  for (final match in pattern.allMatches(source)) {
    warnings.add(
        'concatenated reflection string was not rewritten: ${match.group(1)}');
  }
  return warnings;
}

String _rewriteXmlOutsideComments(
  String source,
  String Function(String segment) rewrite,
) {
  final buffer = StringBuffer();
  var index = 0;
  final commentPattern = RegExp(r'<!--[\s\S]*?-->');
  for (final match in commentPattern.allMatches(source)) {
    buffer.write(rewrite(source.substring(index, match.start)));
    buffer.write(match.group(0));
    index = match.end;
  }
  buffer.write(rewrite(source.substring(index)));
  return buffer.toString();
}

String _rewriteXmlSegment(
  String segment, {
  required List<MapEntry<String, String>> classRenameEntries,
  required Map<String, String> resourceRenames,
}) {
  var updated = segment.replaceAllMapped(
    RegExp(r'(@|\?)([A-Za-z_][A-Za-z0-9_]*)/([A-Za-z_][A-Za-z0-9_]*)'),
    (match) {
      final key = '${match.group(2)}/${match.group(3)}';
      final renamed = resourceRenames[key];
      if (renamed == null) return match.group(0)!;
      return '${match.group(1)}${match.group(2)}/${renamed.split('/').last}';
    },
  );
  for (final entry in classRenameEntries) {
    if (!updated.contains(entry.key)) continue;
    updated = updated.replaceAllMapped(
      RegExp('([<"\\s=])${RegExp.escape(entry.key)}([>"\\s/])'),
      (match) => '${match.group(1)}${entry.value}${match.group(2)}',
    );
  }
  return updated;
}

List<MapEntry<String, String>> _sortedClassRenameEntries(
  Map<String, String> classRenames,
) {
  return classRenames.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
}

String _toPackageSegment(String value) {
  final raw = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
  final normalized =
      raw.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  if (normalized.isEmpty) return 'profile';
  if (RegExp(r'^[0-9]').hasMatch(normalized)) return 'p_$normalized';
  return normalized;
}

String _toAndroidResourceName(String value) {
  final raw = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
  var normalized =
      raw.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  if (normalized.isEmpty) normalized = 'profile_item';
  if (RegExp(r'^[0-9]').hasMatch(normalized)) normalized = 'r_$normalized';
  return normalized;
}

bool _matchesAnyPackage(String packageName, List<String> patterns) {
  return patterns.any((pattern) {
    if (pattern.endsWith('.*')) {
      return packageName == pattern.substring(0, pattern.length - 2) ||
          packageName.startsWith(pattern.substring(0, pattern.length - 1));
    }
    return _matchesGlob(packageName, pattern);
  });
}

bool _matchesAnyResource(String type, String name, List<String> patterns) {
  return patterns.any((pattern) {
    if (pattern.contains('/')) return _matchesGlob('$type/$name', pattern);
    return _matchesGlob(name, pattern);
  });
}

bool _matchesAnyGlob(String value, List<String> patterns) {
  return patterns.any((pattern) => _matchesGlob(value, pattern));
}

bool _matchesGlob(String value, String pattern) {
  final escaped = RegExp.escape(pattern)
      .replaceAll(r'\*\*', '.*')
      .replaceAll(r'\*', '[^/]*')
      .replaceAll(r'\?', '.');
  return RegExp('^$escaped\$').hasMatch(value);
}

int _readOptionalCount(
    Map<String, dynamic> json, String key, int defaultValue) {
  final value = json[key];
  if (value == null) return defaultValue;
  if (value is! int || value < 0 || value > 100) {
    throw StateError('androidNoise.componentCount.$key must be from 0 to 100.');
  }
  return value;
}

List<String> _readTemplateList(
  Map<String, dynamic> json,
  String key,
  List<String> defaults,
) {
  final value = json[key];
  if (value == null) return List<String>.from(defaults);
  if (value is! List || value.isEmpty) {
    throw StateError('androidNoise.$key must be a non-empty string array.');
  }
  return value.map((item) {
    if (item is! String || item.trim().isEmpty) {
      throw StateError('androidNoise.$key must be a non-empty string array.');
    }
    return item.trim();
  }).toList();
}

List<String> _readMergedTemplateList(
  Map<String, dynamic> json,
  String key,
  List<String> defaults,
) {
  final merged = <String>[...defaults];
  final value = json[key];
  if (value == null) return merged;
  if (value is! List) {
    throw StateError(
        'androidNoise.deepObfuscation.$key must be a string array.');
  }
  for (final item in value) {
    if (item is! String || item.trim().isEmpty) {
      throw StateError(
          'androidNoise.deepObfuscation.$key must be a string array.');
    }
    if (!merged.contains(item.trim())) merged.add(item.trim());
  }
  return merged;
}

List<AndroidXmlResourceTemplate> _readXmlResourceTemplates(
  Map<String, dynamic> json,
  String key,
  List<Map<String, String>> defaults,
) {
  final value = json[key];
  if (value == null) {
    return defaults.map(AndroidXmlResourceTemplate.fromDefault).toList();
  }
  if (value is! List || value.isEmpty) {
    throw StateError(
        'androidNoise.resourceTemplates.$key must be a non-empty array.');
  }
  return value.map((item) {
    if (item is! Map<String, dynamic>) {
      throw StateError(
          'androidNoise.resourceTemplates.$key entries must be objects.');
    }
    final name = item['name'];
    final body = item['body'];
    if (name is! String || !_isAndroidResourceName(name.trim())) {
      throw StateError(
          'androidNoise.resourceTemplates.$key.name must be an Android resource name.');
    }
    if (body is! String || body.trim().isEmpty) {
      throw StateError(
          'androidNoise.resourceTemplates.$key.body must be non-empty.');
    }
    return AndroidXmlResourceTemplate(
      name: name.trim(),
      body: body,
    );
  }).toList();
}

List<AndroidStringResourceTemplate> _readStringResourceTemplates(
  Map<String, dynamic> json,
  String key,
  List<Map<String, String>> defaults,
) {
  final value = json[key];
  if (value == null) {
    return _uniqueStringResourceTemplates(
      defaults.map(AndroidStringResourceTemplate.fromDefault),
    );
  }
  if (value is! List || value.isEmpty) {
    throw StateError(
        'androidNoise.resourceTemplates.$key must be a non-empty array.');
  }
  return _uniqueStringResourceTemplates(value.map((item) {
    if (item is! Map<String, dynamic>) {
      throw StateError(
          'androidNoise.resourceTemplates.$key entries must be objects.');
    }
    final name = item['name'];
    final stringValue = item['value'];
    if (name is! String || !_isAndroidResourceName(name.trim())) {
      throw StateError(
          'androidNoise.resourceTemplates.$key.name must be an Android resource name.');
    }
    if (stringValue is! String || stringValue.trim().isEmpty) {
      throw StateError(
          'androidNoise.resourceTemplates.$key.value must be non-empty.');
    }
    return AndroidStringResourceTemplate(
      name: name.trim(),
      value: stringValue,
    );
  }));
}

List<AndroidStringResourceTemplate> _uniqueStringResourceTemplates(
  Iterable<AndroidStringResourceTemplate> templates,
) {
  final usedNames = <String>{};
  final result = <AndroidStringResourceTemplate>[];
  for (final template in templates) {
    final uniqueName = _nextUniqueAndroidResourceName(template.name, usedNames);
    result.add(AndroidStringResourceTemplate(
      name: uniqueName,
      value: template.value,
    ));
  }
  return result;
}

String _nextUniqueAndroidResourceName(String baseName, Set<String> usedNames) {
  if (usedNames.add(baseName)) {
    return baseName;
  }

  var index = 2;
  while (true) {
    final candidate = '${baseName}_$index';
    if (usedNames.add(candidate)) {
      return candidate;
    }
    index++;
  }
}

Map<String, List<String>> _readSourceTemplates(Map<String, dynamic> json) {
  final templates = _cloneDefaultSourceTemplates();
  for (final entry in json.entries) {
    if (!templates.containsKey(entry.key)) {
      throw StateError(
          'androidNoise.sourceTemplates.${entry.key} is not supported.');
    }
    final value = entry.value;
    if (value is! List || value.isEmpty) {
      throw StateError(
          'androidNoise.sourceTemplates.${entry.key} must be a non-empty string array.');
    }
    templates[entry.key] = value.map((item) {
      if (item is! String || item.trim().isEmpty) {
        throw StateError(
            'androidNoise.sourceTemplates.${entry.key} must be a non-empty string array.');
      }
      return item;
    }).toList();
  }
  return templates;
}

Map<String, List<String>> _cloneDefaultSourceTemplates() {
  return _defaultSourceTemplates.map(
    (key, value) => MapEntry(key, List<String>.from(value)),
  );
}

String _selectSourceTemplate(List<String> templates, _ComponentSpec spec) {
  if (templates.length == 1) return templates.first;
  return templates[(spec.sourceTemplateOffset + spec.index) % templates.length];
}

String _renderSourceTemplate(
  String template, {
  required String packageName,
  required _ComponentSpec spec,
  required AndroidNoiseConfig config,
}) {
  final label = _renderStringTemplate(
    config.stringTemplates[spec.index % config.stringTemplates.length],
    spec,
  );
  final namespace = packageName.endsWith('.${config.packageSegment}')
      ? packageName.substring(
          0,
          packageName.length - config.packageSegment.length - 1,
        )
      : packageName;
  return template
      .replaceAll('{{packageName}}', packageName)
      .replaceAll('{{namespace}}', namespace)
      .replaceAll('{{className}}', spec.className)
      .replaceAll('{{methodName}}', spec.methodName)
      .replaceAll('{{component}}', spec.type)
      .replaceAll('{{componentClass}}', spec.baseClass)
      .replaceAll('{{manifestTag}}', spec.manifestTag)
      .replaceAll('{{stringLabel}}', label)
      .replaceAll('{{layoutResourceName}}', _activityResourceLayoutName)
      .replaceAll(
        '{{layoutResourceRef}}',
        '$namespace.R.layout.$_activityResourceLayoutName',
      )
      .replaceAll('{{index}}', spec.index.toString())
      .replaceAll(
        '{{sharedMethods}}',
        _sharedMethods(spec, config, 'Bundle bundle').trimRight(),
      );
}

String _renderResourceTemplate(
  String template, {
  required String namespace,
  required String packageName,
  required String resourceName,
  required String drawableName,
  required int index,
}) {
  return template
      .replaceAll('{{namespace}}', namespace)
      .replaceAll('{{packageName}}', packageName)
      .replaceAll('{{resourceName}}', resourceName)
      .replaceAll('{{drawableName}}', drawableName)
      .replaceAll('{{index}}', index.toString());
}

String _escapeXmlText(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String _renderClassName(List<String> templates, String type, int index) {
  final component = _componentSuffix(type);
  final raw = templates[index % templates.length]
      .replaceAll('{{component}}', component)
      .replaceAll('{{index}}', index.toString());
  final name = raw.contains(component) ? raw : '$raw$component';
  return _toJavaIdentifier(name, upperCamel: true);
}

String _renderMethodName(List<String> templates, int index) {
  final raw = templates[index % templates.length].replaceAll(
    '{{index}}',
    index.toString(),
  );
  return _toJavaIdentifier(raw, upperCamel: false);
}

String _renderStringTemplate(String template, _ComponentSpec spec) {
  return template
      .replaceAll('{{component}}', spec.type)
      .replaceAll('{{className}}', spec.className)
      .replaceAll('{{methodName}}', spec.methodName)
      .replaceAll('{{index}}', spec.index.toString())
      .replaceAll('"', "'");
}

String _componentSuffix(String type) {
  return switch (type) {
    'activity' => 'Activity',
    'service' => 'Service',
    'receiver' => 'Receiver',
    'provider' => 'Provider',
    _ => 'Component',
  };
}

String _uniqueName(
  String name,
  Set<String> used, {
  bool lowerCamel = false,
}) {
  var candidate = lowerCamel ? _lowerFirst(name) : name;
  var index = 1;
  while (!used.add(candidate)) {
    candidate = '${lowerCamel ? _lowerFirst(name) : name}$index';
    index++;
  }
  return candidate;
}

String _toJavaIdentifier(String value, {required bool upperCamel}) {
  final parts = value
      .split(RegExp(r'[^A-Za-z0-9_]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  final buffer = StringBuffer();
  for (final part in parts.isEmpty ? ['Noise'] : parts) {
    buffer.write(part[0].toUpperCase());
    if (part.length > 1) buffer.write(part.substring(1));
  }
  var result = buffer.toString().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
  if (result.isEmpty) result = 'Noise';
  if (RegExp(r'^[0-9]').hasMatch(result)) result = 'Noise$result';
  return upperCamel ? result : _lowerFirst(result);
}

String _lowerFirst(String value) {
  if (value.isEmpty) return value;
  return value[0].toLowerCase() + value.substring(1);
}

bool _isPackageSegment(String value) {
  return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$')
      .hasMatch(value);
}

bool _isAndroidResourceName(String value) {
  return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value);
}

String _posixRelative(String filePath, {required String from}) {
  return p.relative(filePath, from: from).replaceAll(p.separator, '/');
}
