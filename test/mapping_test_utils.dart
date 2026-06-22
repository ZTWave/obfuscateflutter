import 'dart:convert';
import 'dart:io';

import 'package:obfuscateflutter/html_mapping_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Map<String, dynamic> readHtmlFeatureMapping(
  Directory projectDir,
  String featureId,
) {
  final file = File(p.join(projectDir.path, unifiedMappingFileName));
  expect(file.existsSync(), isTrue);
  final html = file.readAsStringSync();
  expect(html, contains('Obfuscation Mapping'));
  expect(html, contains('功能'));
  final match = RegExp(
    r'<script[^>]*id="obfuscation-mapping-data"[^>]*>([\s\S]*?)</script>',
  ).firstMatch(html);
  expect(match, isNotNull);
  final decoded = jsonDecode(_unescapeHtml(match!.group(1)!.trim()))
      as Map<String, dynamic>;
  final features = decoded['features'] as Map<String, dynamic>;
  expect(features, contains(featureId));
  final feature = features[featureId] as Map<String, dynamic>;
  return feature['mapping'] as Map<String, dynamic>;
}

String _unescapeHtml(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');
}
