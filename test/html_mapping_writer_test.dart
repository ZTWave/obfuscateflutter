import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/html_mapping_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('writes release report with project file counts and summary metrics',
      () {
    final projectDir =
        Directory.systemTemp.createTempSync('html_mapping_writer_');
    addTearDown(() {
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    });

    File(p.join(projectDir.path, 'pubspec.yaml'))
        .writeAsStringSync('name: app');
    Directory(p.join(projectDir.path, 'lib')).createSync();
    File(p.join(projectDir.path, 'lib', 'main.dart'))
        .writeAsStringSync('void main() {}');
    Directory(p.join(projectDir.path, 'build')).createSync();
    File(p.join(projectDir.path, 'build', 'cache.bin')).writeAsStringSync('x');
    Directory(p.join(projectDir.path, '.dart_tool')).createSync();
    File(p.join(projectDir.path, '.dart_tool', 'cache'))
        .writeAsStringSync('ignored');

    initializeHtmlMappingReport(projectDir.path);
    File(p.join(projectDir.path, 'lib', 'noise.dart')).writeAsStringSync('');

    writeHtmlFeatureMapping(
      projectPath: projectDir.path,
      featureId: 'android_noise',
      featureTitle: 'Android项目垃圾代码生成',
      mapping: {
        'resource_renames': {'drawable/old': 'drawable/new'},
        'generated_components': [
          {'type': 'activity', 'class': 'TraceActivity'},
          {'type': 'service', 'class': 'TraceService'},
        ],
        'skipped_items': [
          {'kind': 'class', 'item': 'KeepActivity', 'reason': 'skipClasses'},
        ],
        'warnings': ['reflection string was not rewritten'],
      },
    );
    writeHtmlFeatureMapping(
      projectPath: projectDir.path,
      featureId: 'class_inner_noise',
      featureTitle: '类内垃圾代码/字符串注入',
      mapping: {
        'strings_injected': [
          {'file': 'lib/main.dart', 'count': 2},
          {'file': 'lib/home.dart', 'count': 1},
        ],
        'members': [
          {'file': 'lib/main.dart', 'class': 'HomePage'},
        ],
        'skipped': [
          {'file': 'lib/keep.dart', 'reason': 'no_safe_class_candidates'},
        ],
      },
    );

    final html = File(p.join(projectDir.path, unifiedMappingFileName))
        .readAsStringSync();
    expect(html, contains('发布报告'));
    expect(html, contains('风险项'));
    expect(html, contains('人工检查项'));

    final document = _readDocument(projectDir);
    final report = document['release_report'] as Map<String, dynamic>;
    final fileCounts = report['file_counts'] as Map<String, dynamic>;
    expect(fileCounts['before'], 2);
    expect(fileCounts['after'], 3);
    expect(fileCounts['excluded_directories'], contains('build'));
    expect(fileCounts['excluded_directories'], contains('.dart_tool'));

    final totals = report['totals'] as Map<String, dynamic>;
    expect(totals['strings_processed'], 3);
    expect(totals['resources_renamed'], 1);
    expect(totals['dart_injections'], 1);
    expect(totals['ios_injections'], 0);
    expect(totals['android_injections'], 2);

    final skipReasons = report['skip_reasons'] as List<dynamic>;
    expect(skipReasons.toString(), contains('skipClasses'));
    expect(skipReasons.toString(), contains('no_safe_class_candidates'));
    expect((report['risk_items'] as List<dynamic>).join('\n'),
        contains('reflection string was not rewritten'));
    expect((report['manual_check_items'] as List<dynamic>).join('\n'),
        contains('检查 Android 注入组件'));
  });
}

Map<String, dynamic> _readDocument(Directory projectDir) {
  final html =
      File(p.join(projectDir.path, unifiedMappingFileName)).readAsStringSync();
  final match = RegExp(
    r'<script[^>]*id="obfuscation-mapping-data"[^>]*>([\s\S]*?)</script>',
  ).firstMatch(html);
  expect(match, isNotNull);
  return jsonDecode(_unescapeHtml(match!.group(1)!.trim()))
      as Map<String, dynamic>;
}

String _unescapeHtml(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');
}
