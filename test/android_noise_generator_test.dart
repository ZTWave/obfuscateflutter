import 'dart:async';
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
    expect(manifest, isNot(contains('<meta-data')));

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
        contains(
            'setContentView(com.example.sample.R.layout.activity_resource_panel)'),
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
    final retainLayout = File(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
      'res',
      'layout',
      'activity_resource_panel.xml',
    ));
    expect(retainLayout.existsSync(), isTrue);
    final retainLayoutSource = retainLayout.readAsStringSync();
    expect(retainLayoutSource, contains('@drawable/activity_panel'));
    expect(retainLayoutSource, contains('@drawable/profile_badge'));
    expect(retainLayoutSource, contains('@layout/session_marker'));
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

  test(
      'android deep obfuscation skips flutter registrant and rewrites safe android references',
      () {
    final projectDir = _createAndroidProject();
    final androidMain = Directory(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
    ));
    final javaRoot = Directory(p.join(
      androidMain.path,
      'java',
      'com',
      'example',
      'sample',
    ));
    final featureDir = Directory(p.join(javaRoot.path, 'feature'));
    final widgetDir = Directory(p.join(javaRoot.path, 'widget'));
    final flutterDir = Directory(p.join(javaRoot.path, 'flutter'));
    featureDir.createSync(recursive: true);
    widgetDir.createSync(recursive: true);
    flutterDir.createSync(recursive: true);

    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'androidNoise': {
        'componentCount': {
          'activity': 0,
          'service': 0,
          'receiver': 0,
          'provider': 0,
        },
        'generateResources': {
          'xml': false,
          'images': false,
        },
        'deepObfuscation': {
          'enabled': true,
          'packageTemplates': ['account.{{word}}'],
          'classTemplates': ['Session{{className}}'],
          'resourceTemplates': ['profile_{{name}}'],
          'semanticWords': ['profile'],
          'reflectionRewrite': {
            'enabled': true,
            'strict': true,
          },
        },
      },
    }));

    File(p.join(featureDir.path, 'UserRouteActivity.java'))
        .writeAsStringSync('''
package com.example.sample.feature;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;
import java.util.List;
import com.example.sample.widget.ProfileCardView;

public class UserRouteActivity extends Activity {
  ProfileCardView profileCardView;
  UserRouteActivity parentRoute;
  List<ProfileCardView> profileCards;

  public UserRouteActivity() {}

  public UserRouteActivity(byte[] data) {
    super();
  }

  @Override
  protected void onCreate(Bundle bundle) {
    super.onCreate(bundle);
    int id = com.example.sample.R.layout.checkout_screen;
    String untouchedLog = "old class name for log com.example.sample.feature.UserRouteActivity";
    String url = "https://example.com/com.example.sample.feature.UserRouteActivity";
    String json = "{\\"class\\":\\"com.example.sample.feature.UserRouteActivity\\"}";
    Class.forName("com.example.sample.feature.UserRouteActivity");
    getClassLoader().loadClass("com.example.sample.widget.ProfileCardView");
    new Intent().setClassName(this, "com.example.sample.feature.UserRouteActivity");
    ComponentName componentName = new ComponentName(this, "com.example.sample.feature.UserRouteActivity");
    Class.forName("com.example.sample." + "feature.UserRouteActivity");
    new ProfileCardView(this);
  }
}
''');

    File(p.join(widgetDir.path, 'ProfileCardView.java')).writeAsStringSync('''
package com.example.sample.widget;

import android.content.Context;
import android.view.View;

public class ProfileCardView extends View {
  public ProfileCardView(Context context) {
    super(context);
  }
}
''');

    File(p.join(javaRoot.path, 'MainActivity.java')).writeAsStringSync('''
package com.example.sample;

import android.app.Activity;
import com.example.sample.feature.UserRouteActivity;

public class MainActivity extends Activity {
  UserRouteActivity routeActivity;
}
''');

    File(p.join(flutterDir.path, 'GeneratedPluginRegistrant.java'))
        .writeAsStringSync('''
package com.example.sample.flutter;

public final class GeneratedPluginRegistrant {
  public static void registerWith(Object registry) {}
}
''');

    Directory(p.join(androidMain.path, 'res', 'layout'))
        .createSync(recursive: true);
    Directory(p.join(androidMain.path, 'res', 'drawable'))
        .createSync(recursive: true);
    File(p.join(androidMain.path, 'res', 'layout', 'checkout_screen.xml'))
        .writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/checkout_panel"
    tools:context="com.example.sample.feature.UserRouteActivity">
    <com.example.sample.widget.ProfileCardView
        android:layout_width="match_parent"
        android:layout_height="wrap_content" />
</LinearLayout>
''');
    File(p.join(androidMain.path, 'res', 'drawable', 'checkout_panel.xml'))
        .writeAsStringSync('''
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="#112233" />
</shape>
''');
    File(p.join(androidMain.path, 'AndroidManifest.xml')).writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="sample">
        <activity android:name="com.example.sample.feature.UserRouteActivity" />
    </application>
</manifest>
''');

    runAndroidNoiseGeneration(projectDir.path);

    final registrant = File(p.join(
      flutterDir.path,
      'GeneratedPluginRegistrant.java',
    ));
    expect(registrant.existsSync(), isTrue);
    expect(
      registrant.readAsStringSync(),
      allOf(
        contains('package com.example.sample.flutter;'),
        contains('GeneratedPluginRegistrant'),
      ),
    );

    final mainActivity = File(p.join(javaRoot.path, 'MainActivity.java'));
    expect(mainActivity.existsSync(), isTrue);
    final mainActivitySource = mainActivity.readAsStringSync();
    expect(mainActivitySource, contains('package com.example.sample;'));
    expect(mainActivitySource, contains('class MainActivity'));
    expect(
      mainActivitySource,
      contains(
          'import com.example.sample.account.profile.SessionUserRouteActivity;'),
    );
    expect(
      mainActivitySource,
      contains('SessionUserRouteActivity routeActivity;'),
    );
    expect(
      mainActivitySource,
      isNot(contains('import com.example.sample.feature.UserRouteActivity;')),
    );
    expect(
      mainActivitySource,
      isNot(matches(RegExp(r'\bUserRouteActivity\s+routeActivity;'))),
    );

    final renamedActivity = Directory(p.join(
      javaRoot.path,
      'account',
      'profile',
    )).listSync().whereType<File>().singleWhere(
        (file) => p.basename(file.path).contains('UserRouteActivity'));
    final renamedSource = renamedActivity.readAsStringSync();
    expect(
        renamedSource, contains('package com.example.sample.account.profile;'));
    expect(renamedSource, contains('class SessionUserRouteActivity'));
    expect(renamedSource, contains('public SessionUserRouteActivity()'));
    expect(
      renamedSource,
      contains('public SessionUserRouteActivity(byte[] data)'),
    );
    expect(renamedSource, isNot(contains('public UserRouteActivity(')));
    expect(renamedSource, contains('SessionProfileCardView profileCardView;'));
    expect(renamedSource, contains('SessionUserRouteActivity parentRoute;'));
    expect(
        renamedSource, contains('List<SessionProfileCardView> profileCards;'));
    expect(renamedSource, contains('new SessionProfileCardView(this)'));
    expect(
      renamedSource,
      isNot(matches(RegExp(r'\bProfileCardView\s+profileCardView;'))),
    );
    expect(
      renamedSource,
      isNot(matches(RegExp(r'\bUserRouteActivity\s+parentRoute;'))),
    );
    expect(
      renamedSource,
      isNot(matches(RegExp(r'\bnew\s+ProfileCardView\s*\('))),
    );
    expect(renamedSource, contains('R.layout.profile_checkout_screen'));
    expect(
        renamedSource,
        contains(
            'Class.forName("com.example.sample.account.profile.SessionUserRouteActivity")'));
    expect(
        renamedSource,
        contains(
            'loadClass("com.example.sample.account.profile.SessionProfileCardView")'));
    expect(
        renamedSource,
        contains(
            'setClassName(this, "com.example.sample.account.profile.SessionUserRouteActivity")'));
    expect(
        renamedSource,
        contains(
            'ComponentName(this, "com.example.sample.account.profile.SessionUserRouteActivity")'));
    expect(
        renamedSource,
        contains(
            'old class name for log com.example.sample.feature.UserRouteActivity'));
    expect(
        renamedSource,
        contains(
            'https://example.com/com.example.sample.feature.UserRouteActivity'));
    expect(
      renamedSource,
      contains(r'\"class\":\"com.example.sample.feature.UserRouteActivity\"'),
    );
    expect(
      renamedSource,
      contains(
          'Class.forName("com.example.sample." + "feature.UserRouteActivity")'),
    );

    final manifest = File(p.join(
      androidMain.path,
      'AndroidManifest.xml',
    )).readAsStringSync();
    expect(
      manifest,
      contains('com.example.sample.account.profile.SessionUserRouteActivity'),
    );

    final renamedLayout = File(p.join(
      androidMain.path,
      'res',
      'layout',
      'profile_checkout_screen.xml',
    ));
    expect(renamedLayout.existsSync(), isTrue);
    final layoutSource = renamedLayout.readAsStringSync();
    expect(layoutSource, contains('@drawable/profile_checkout_panel'));
    expect(
      layoutSource,
      contains(
          'tools:context="com.example.sample.account.profile.SessionUserRouteActivity"'),
    );
    expect(
      layoutSource,
      contains('<com.example.sample.account.profile.SessionProfileCardView'),
    );
    expect(
      File(p.join(androidMain.path, 'res', 'drawable',
              'profile_checkout_panel.xml'))
          .existsSync(),
      isTrue,
    );

    final mappingFile = projectDir.listSync().whereType<File>().singleWhere(
          (file) => p.basename(file.path).startsWith('android_noise_mapping_'),
        );
    final mapping =
        jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
    expect(mapping['class_renames'], isNotEmpty);
    expect(mapping['resource_renames'], isNotEmpty);
    expect(mapping['reflection_rewrites'], isNotEmpty);
    expect(mapping['warnings'].toString(), contains('concatenated reflection'));
    expect(mapping['skipped_items'].toString(),
        contains('GeneratedPluginRegistrant.java'));
  });

  test('android deep obfuscation honors custom skip templates', () {
    final projectDir = _createAndroidProject();
    final androidMain = Directory(p.join(
      projectDir.path,
      'android',
      'app',
      'src',
      'main',
    ));
    final javaRoot = Directory(p.join(
      androidMain.path,
      'java',
      'com',
      'example',
      'sample',
      'billing',
    ))
      ..createSync(recursive: true);
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'androidNoise': {
        'componentCount': {
          'activity': 0,
          'service': 0,
          'receiver': 0,
          'provider': 0,
        },
        'generateResources': {
          'xml': false,
          'images': false,
        },
        'deepObfuscation': {
          'enabled': true,
          'skipClasses': ['BillingKeepActivity'],
          'skipResources': ['drawable/keep_badge'],
          'packageTemplates': ['account.{{word}}'],
          'classTemplates': ['Session{{className}}'],
          'resourceTemplates': ['profile_{{name}}'],
          'semanticWords': ['profile'],
        },
      },
    }));
    File(p.join(javaRoot.path, 'BillingKeepActivity.java'))
        .writeAsStringSync('''
package com.example.sample.billing;

public class BillingKeepActivity {}
''');
    File(p.join(javaRoot.path, 'BillingMoveActivity.java'))
        .writeAsStringSync('''
package com.example.sample.billing;

public class BillingMoveActivity {}
''');
    final drawableDir = Directory(p.join(androidMain.path, 'res', 'drawable'))
      ..createSync(recursive: true);
    File(p.join(drawableDir.path, 'keep_badge.xml')).writeAsStringSync('''
<shape xmlns:android="http://schemas.android.com/apk/res/android" />
''');
    File(p.join(drawableDir.path, 'move_badge.xml')).writeAsStringSync('''
<shape xmlns:android="http://schemas.android.com/apk/res/android" />
''');

    runAndroidNoiseGeneration(projectDir.path);

    expect(File(p.join(javaRoot.path, 'BillingKeepActivity.java')).existsSync(),
        isTrue);
    expect(
      File(p.join(javaRoot.path, 'BillingKeepActivity.java'))
          .readAsStringSync(),
      contains('package com.example.sample.billing;'),
    );
    expect(
        File(p.join(drawableDir.path, 'keep_badge.xml')).existsSync(), isTrue);
    expect(
      File(p.join(
        androidMain.path,
        'java',
        'com',
        'example',
        'sample',
        'account',
        'profile',
        'SessionBillingMoveActivity.java',
      )).existsSync(),
      isTrue,
    );
    expect(
        File(p.join(drawableDir.path, 'profile_move_badge.xml')).existsSync(),
        isTrue);

    final mappingFile = projectDir.listSync().whereType<File>().singleWhere(
          (file) => p.basename(file.path).startsWith('android_noise_mapping_'),
        );
    final mapping =
        jsonDecode(mappingFile.readAsStringSync()) as Map<String, dynamic>;
    expect(
        mapping['skipped_items'].toString(), contains('BillingKeepActivity'));
    expect(
        mapping['skipped_items'].toString(), contains('drawable/keep_badge'));
  });

  test('android deep obfuscation prints progress logs', () {
    final projectDir = _createAndroidProject();
    File(p.join(projectDir.path, 'obfuscate_dart_noise.json'))
        .writeAsStringSync(jsonEncode({
      'androidNoise': {
        'componentCount': {
          'activity': 0,
          'service': 0,
          'receiver': 0,
          'provider': 0,
        },
        'generateResources': {
          'xml': false,
          'images': false,
        },
        'deepObfuscation': {
          'enabled': true,
        },
      },
    }));
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
      'feature',
    ))
      ..createSync(recursive: true);
    File(p.join(javaRoot.path, 'OrderRouteActivity.java')).writeAsStringSync('''
package com.example.sample.feature;

public class OrderRouteActivity {}
''');

    final logs = <String>[];
    runZoned(
      () => runAndroidNoiseGeneration(projectDir.path),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) {
          logs.add(line);
        },
      ),
    );

    final output = logs.join('\n');
    expect(output, contains('Android deep obfuscation started'));
    expect(output, contains('Android deep obfuscation scan'));
    expect(output, contains('Android deep obfuscation rewrite'));
    expect(output, contains('Android deep obfuscation move'));
    expect(output, contains('Android deep obfuscation complete'));
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
