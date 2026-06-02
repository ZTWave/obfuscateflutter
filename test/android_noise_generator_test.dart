import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/android_noise_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
      'android noise generation creates manifest-retained components and resources',
      () {
    final projectDir = _createAndroidProject();

    runAndroidNoiseGeneration(projectDir.path);

    final manifest = File(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
      'AndroidManifest.xml',
    )).readAsStringSync();
    expect(manifest, contains('obfuscateflutter: android-noise start'));
    expect(manifest, contains('obfuscateflutter: android-noise end'));
    expect(manifest, contains('<activity'));
    expect(manifest, contains('<service'));
    expect(manifest, contains('<receiver'));
    expect(manifest, contains('<provider'));
    expect(manifest, contains('android:exported="false"'));
    expect(manifest, isNot(contains('<intent-filter')));

    final javaRoot = Directory(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
      'java',
      'com',
      'example',
      'sample',
      'noise',
    ));
    final javaFiles = javaRoot
        .listSync()
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.java')
        .toList();
    expect(javaFiles, hasLength(4));
    expect(
      javaFiles.map((file) => file.readAsStringSync()).join('\n'),
      allOf(
        contains('extends Activity'),
        contains('extends Service'),
        contains('extends BroadcastReceiver'),
        contains('extends ContentProvider'),
        contains('StringBuilder'),
        contains('Bundle'),
      ),
    );

    expect(
      File(p.join(
        projectDir.path,
        'android',
        'app',
        'src',
        'main',
        'res',
        'drawable',
        'activity_panel.xml',
      )).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(
        projectDir.path,
        'android',
        'app',
        'src',
        'main',
        'res',
        'drawable',
        'profile_badge.png',
      )).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(
        projectDir.path,
        'android',
        'app',
        'src',
        'main',
        'res',
        'layout',
        'session_marker.xml',
      )).existsSync(),
      isTrue,
    );
    final resourceBasenames = Directory(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
      'res',
    ))
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => p.basename(file.path))
        .toList();
    expect(resourceBasenames, everyElement(isNot(contains('obf'))));
    expect(resourceBasenames, everyElement(isNot(contains('noise'))));

    final mappingFile = projectDir.listSync().whereType<File>().singleWhere(
          (file) => p.basename(file.path).startsWith('android_noise_mapping_'),
        );
    final mapping =
        jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
    expect(mapping['namespace'], 'com.example.sample');
    expect(mapping['generated_components'], hasLength(4));
    expect(mapping['generated_resources'], isNotEmpty);
    expect(mapping['manifest_entries'], hasLength(4));

    runAndroidNoiseGeneration(projectDir.path);
    final secondManifest = File(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
      'AndroidManifest.xml',
    )).readAsStringSync();
    expect(
      RegExp('obfuscateflutter: android-noise start')
          .allMatches(secondManifest)
          .length,
      1,
    );
  });

  test(
      'android noise generation supports custom class and method name templates',
      () {
    final projectDir = _createAndroidProject();
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'pageCount': 1,
      'classCount': 1,
      'methodCountPerClass': 1,
      'template': 'page_sync_class',
      'outputDir': 'lib/dart_noise',
      'androidNoise': {
        'componentCount': {
          'activity': 1,
          'service': 0,
          'receiver': 0,
          'provider': 0,
        },
        'packageSegment': 'audit',
        'nameTemplates': {
          'classNames': ['BillingAudit{{component}}'],
          'methodNames': ['collectInvoiceSignal'],
        },
        'generateResources': {
          'xml': false,
          'images': false,
        },
      },
    }));

    runAndroidNoiseGeneration(projectDir.path);

    final javaFile = File(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
      'java',
      'com',
      'example',
      'sample',
      'audit',
      'BillingAuditActivity.java',
    ));
    expect(javaFile.existsSync(), isTrue);
    expect(javaFile.readAsStringSync(), contains('collectInvoiceSignal'));
  });

  test('android noise generation renders drawable and layout xml templates',
      () {
    final projectDir = _createAndroidProject();
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'androidNoise': {
        'componentCount': {
          'activity': 1,
          'service': 0,
          'receiver': 0,
          'provider': 0,
        },
        'generateResources': {
          'xml': true,
          'images': false,
        },
        'resourceTemplates': {
          'drawableXml': [
            {
              'name': 'billing_panel',
              'body':
                  '<shape xmlns:android="http://schemas.android.com/apk/res/android"><solid android:color="#112233" /></shape>'
            }
          ],
          'layoutXml': [
            {
              'name': 'checkout_marker',
              'body':
                  '<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android" android:layout_width="1dp" android:layout_height="1dp" android:background="@drawable/{{drawableName}}" />'
            }
          ],
        },
      },
    }));

    runAndroidNoiseGeneration(projectDir.path);

    final drawable = File(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
      'res',
      'drawable',
      'billing_panel.xml',
    ));
    final layout = File(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
      'res',
      'layout',
      'checkout_marker.xml',
    ));
    expect(drawable.readAsStringSync(), contains('#112233'));
    expect(layout.readAsStringSync(), contains('@drawable/billing_panel'));
  });

  test('android noise generation selects java source from json template lists',
      () {
    final projectDir = _createAndroidProject();
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'androidNoise': {
        'componentCount': {
          'activity': 2,
          'service': 0,
          'receiver': 0,
          'provider': 0,
        },
        'packageSegment': 'audit',
        'nameTemplates': {
          'classNames': ['BillingAudit{{component}}'],
          'methodNames': ['collectInvoiceSignal'],
        },
        'generateResources': {
          'xml': false,
          'images': false,
        },
        'sourceTemplates': {
          'activity': [
            'package {{packageName}};\n\nimport android.app.Activity;\nimport android.os.Bundle;\n\npublic class {{className}} extends Activity {\n  private static final String TEMPLATE_MARKER = "{{stringLabel}}";\n\n  @Override\n  protected void onCreate(Bundle savedInstanceState) {\n    super.onCreate(savedInstanceState);\n    {{methodName}}(savedInstanceState);\n  }\n\n  private int {{methodName}}(Bundle bundle) {\n    return TEMPLATE_MARKER.length() + {{index}};\n  }\n}\n',
            'package {{packageName}};\n\nimport android.app.Activity;\nimport android.os.Bundle;\n\npublic class {{className}} extends Activity {\n  private static final String SECOND_TEMPLATE_MARKER = "{{className}}";\n\n  @Override\n  protected void onCreate(Bundle savedInstanceState) {\n    super.onCreate(savedInstanceState);\n    {{methodName}}(savedInstanceState);\n  }\n\n  private int {{methodName}}(Bundle bundle) {\n    return SECOND_TEMPLATE_MARKER.length() + {{index}};\n  }\n}\n',
          ],
        },
      },
    }));

    runAndroidNoiseGeneration(projectDir.path);

    final javaDir = Directory(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
      'java',
      'com',
      'example',
      'sample',
      'audit',
    ));
    final sources = javaDir
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(sources, contains('TEMPLATE_MARKER'));
    expect(sources, contains('SECOND_TEMPLATE_MARKER'));
    expect(sources, contains('collectInvoiceSignal(savedInstanceState)'));
    expect(sources, contains('collectInvoiceSignal1(savedInstanceState)'));
    expect(sources, contains('public class BillingAuditActivity'));
    expect(sources, contains('public class BillingAuditActivity1'));
  });

  test('android noise generation reports missing android project and namespace',
      () {
    final missingAndroid =
        Directory.systemTemp.createTempSync('obf_android_missing_');
    addTearDown(() {
      if (missingAndroid.existsSync()) {
        missingAndroid.deleteSync(recursive: true);
      }
    });
    File(p.join(missingAndroid.path, 'pubspec.yaml'))
        .writeAsStringSync('name: sample\n');

    expect(
      () => runAndroidNoiseGeneration(missingAndroid.path),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('android project not found'),
      )),
    );

    final missingNamespace = _createAndroidProject(includeNamespace: false);
    expect(
      () => runAndroidNoiseGeneration(missingNamespace.path),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        contains('Android namespace not found'),
      )),
    );
  });
}

Directory _createAndroidProject({bool includeNamespace = true}) {
  final projectDir = Directory.systemTemp.createTempSync('obf_android_test_');
  addTearDown(() {
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }
  });

  Directory(p.join(projectDir.path, 'lib')).createSync();
  File(p.join(projectDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: sample_app
environment:
  sdk: ^3.2.3
''');
  File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
      .writeAsStringSync(jsonEncode({
    'androidNoise': {
      'componentCount': {
        'activity': 1,
        'service': 1,
        'receiver': 1,
        'provider': 1,
      },
      'packageSegment': 'noise',
      'generateResources': {
        'xml': true,
        'images': true,
      },
    },
  }));

  final androidMain = Directory(p.join(
    projectDir.path,
    'android',
    'app',
    'src',
    'main',
  ));
  androidMain.createSync(recursive: true);
  File(p.join(projectDir.path, 'android', 'app', 'build.gradle'))
      .writeAsStringSync('''
plugins {
    id 'com.android.application'
}

android {
    ${includeNamespace ? "namespace 'com.example.sample'" : ''}
}
''');
  File(p.join(androidMain.path, 'AndroidManifest.xml')).writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="sample">
    </application>
</manifest>
''');
  return projectDir;
}
