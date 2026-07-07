import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const unifiedMappingFileName = 'obfuscation_mapping.html';
const _dataScriptId = 'obfuscation-mapping-data';
const _releaseReportKey = 'release_report';
const _excludedFileCountDirectories = [
  '.dart_tool',
  '.git',
  '.gradle',
  '.idea',
  '.symlinks',
  '.vscode',
  'Pods',
  'build',
];

String initializeHtmlMappingReport(String projectPath) {
  final outputFile = File(p.join(projectPath, unifiedMappingFileName));
  final document = outputFile.existsSync()
      ? _readDocument(outputFile.readAsStringSync())
      : _newDocument();
  final features = (document['features'] is Map)
      ? Map<String, dynamic>.from(document['features'] as Map)
      : <String, dynamic>{};
  final now = DateTime.now().toIso8601String();
  document['updated_at'] = now;
  document['features'] = features;
  document[_releaseReportKey] = _buildReleaseReport(
    projectPath: projectPath,
    features: features,
    beforeFileCount: _countProjectFiles(projectPath),
  );
  outputFile.writeAsStringSync(_renderHtml(document));
  return outputFile.path;
}

String writeHtmlFeatureMapping({
  required String projectPath,
  required String featureId,
  required String featureTitle,
  required Map<String, dynamic> mapping,
}) {
  final outputFile = File(p.join(projectPath, unifiedMappingFileName));
  final document = outputFile.existsSync()
      ? _readDocument(outputFile.readAsStringSync())
      : _newDocument();

  final features = (document['features'] is Map)
      ? Map<String, dynamic>.from(document['features'] as Map)
      : <String, dynamic>{};
  final previousReport = document[_releaseReportKey];
  final previousFileCounts =
      previousReport is Map ? previousReport['file_counts'] : null;
  final beforeFileCount = previousFileCounts is Map
      ? _asInt(previousFileCounts['before']) ?? _countProjectFiles(projectPath)
      : _countProjectFiles(projectPath);
  final now = DateTime.now().toIso8601String();
  document['updated_at'] = now;
  document['features'] = features;
  features[featureId] = {
    'title': featureTitle,
    'updated_at': now,
    'mapping': mapping,
  };
  document[_releaseReportKey] = _buildReleaseReport(
    projectPath: projectPath,
    features: features,
    beforeFileCount: beforeFileCount,
  );

  outputFile.writeAsStringSync(_renderHtml(document));
  return outputFile.path;
}

Map<String, dynamic> _newDocument() {
  return {
    'version': '2.0',
    'created_at': DateTime.now().toIso8601String(),
    'features': <String, dynamic>{},
  };
}

Map<String, dynamic> _readDocument(String html) {
  final pattern = RegExp(
    '<script[^>]*id="$_dataScriptId"[^>]*>([\\s\\S]*?)</script>',
    multiLine: true,
  );
  final match = pattern.firstMatch(html);
  if (match == null) {
    return _newDocument();
  }
  try {
    final decoded = jsonDecode(_unescapeHtml(match.group(1)!.trim()));
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // Fall through and rebuild the document. A broken mapping page should not
    // block the current obfuscation task from writing a fresh report.
  }
  return _newDocument();
}

String _renderHtml(Map<String, dynamic> document) {
  final features = document['features'] is Map
      ? Map<String, dynamic>.from(document['features'] as Map)
      : <String, dynamic>{};
  final releaseReport = document[_releaseReportKey] is Map
      ? Map<String, dynamic>.from(document[_releaseReportKey] as Map)
      : <String, dynamic>{};
  final orderedEntries = features.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final dataJson = const JsonEncoder.withIndent('  ').convert(document);
  final reportCard = _releaseReportCard(releaseReport);
  final featureCards = orderedEntries.map((entry) {
    final feature = Map<String, dynamic>.from(entry.value as Map);
    final mapping = Map<String, dynamic>.from(feature['mapping'] as Map);
    final title = '${feature['title'] ?? entry.key}';
    final summary = mapping['summary'];
    return '''
      <section class="feature" id="${_escapeAttr(entry.key)}">
        <div class="feature-header">
          <div>
            <p class="eyebrow">功能</p>
            <h2>${_escapeHtml(title)}</h2>
          </div>
          <span class="updated">更新 ${_escapeHtml('${feature['updated_at'] ?? ''}')}</span>
        </div>
        ${_summaryTable(summary)}
        <details open>
          <summary>Mapping 内容</summary>
          <pre>${_escapeHtml(const JsonEncoder.withIndent('  ').convert(mapping))}</pre>
        </details>
      </section>
    ''';
  }).join('\n');
  final navItems = orderedEntries.map((entry) {
    final feature = Map<String, dynamic>.from(entry.value as Map);
    return '<a href="#${_escapeAttr(entry.key)}">${_escapeHtml('${feature['title'] ?? entry.key}')}</a>';
  }).join('\n');

  return '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Obfuscation Mapping</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f5f7fb;
      --panel: #ffffff;
      --text: #172033;
      --muted: #667085;
      --border: #d9e0ea;
      --accent: #2357c6;
      --accent-soft: #e8efff;
      --code-bg: #101828;
      --code-text: #e6edf7;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.5;
    }
    header {
      padding: 28px 32px;
      background: var(--panel);
      border-bottom: 1px solid var(--border);
    }
    h1, h2 { margin: 0; letter-spacing: 0; }
    h1 { font-size: 26px; }
    h2 { font-size: 20px; }
    .meta {
      margin-top: 8px;
      color: var(--muted);
      font-size: 13px;
    }
    .layout {
      display: grid;
      grid-template-columns: 260px minmax(0, 1fr);
      gap: 20px;
      padding: 20px;
    }
    nav {
      position: sticky;
      top: 20px;
      align-self: start;
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 12px;
    }
    nav a {
      display: block;
      padding: 9px 10px;
      border-radius: 6px;
      color: var(--text);
      text-decoration: none;
      font-size: 14px;
    }
    nav a:hover { background: var(--accent-soft); color: var(--accent); }
    main { min-width: 0; }
    .release-report,
    .feature {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 8px;
      margin-bottom: 18px;
      overflow: hidden;
    }
    .report-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
      gap: 12px;
      padding: 18px 20px 4px;
    }
    .metric {
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 12px;
      background: #fbfcff;
    }
    .metric-label {
      color: var(--muted);
      font-size: 12px;
      font-weight: 600;
    }
    .metric-value {
      margin-top: 4px;
      font-size: 22px;
      font-weight: 800;
    }
    .report-section {
      padding: 0 20px 16px;
    }
    .report-section h3 {
      margin: 18px 0 8px;
      font-size: 15px;
    }
    .report-list {
      margin: 0;
      padding-left: 18px;
      color: var(--text);
      font-size: 13px;
    }
    .report-list li { margin: 4px 0; }
    .feature-header {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      padding: 18px 20px;
      border-bottom: 1px solid var(--border);
    }
    .eyebrow {
      margin: 0 0 4px;
      color: var(--accent);
      font-size: 12px;
      font-weight: 700;
    }
    .updated {
      color: var(--muted);
      font-size: 12px;
      white-space: nowrap;
    }
    table {
      width: calc(100% - 40px);
      margin: 16px 20px;
      border-collapse: collapse;
      font-size: 13px;
    }
    th, td {
      padding: 8px 10px;
      border-bottom: 1px solid var(--border);
      text-align: left;
      vertical-align: top;
    }
    th { color: var(--muted); font-weight: 600; width: 260px; }
    details { border-top: 1px solid var(--border); }
    summary {
      cursor: pointer;
      padding: 14px 20px;
      font-weight: 700;
    }
    pre {
      margin: 0;
      padding: 18px 20px 22px;
      overflow: auto;
      background: var(--code-bg);
      color: var(--code-text);
      font-size: 12px;
      line-height: 1.55;
    }
    @media (max-width: 840px) {
      .layout { grid-template-columns: 1fr; padding: 12px; }
      nav { position: static; }
      header { padding: 22px 16px; }
      .feature-header { flex-direction: column; }
      .updated { white-space: normal; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Obfuscation Mapping</h1>
    <div class="meta">创建 ${_escapeHtml('${document['created_at'] ?? ''}')} · 更新 ${_escapeHtml('${document['updated_at'] ?? ''}')} · ${orderedEntries.length} 个功能</div>
  </header>
  <div class="layout">
    <nav>
      <a href="#release-report">发布报告</a>
      $navItems
    </nav>
    <main>
      $reportCard
      $featureCards
    </main>
  </div>
  <script id="$_dataScriptId" type="application/json">${_escapeHtml(dataJson)}</script>
</body>
</html>
''';
}

Map<String, dynamic> _buildReleaseReport({
  required String projectPath,
  required Map<String, dynamic> features,
  required int beforeFileCount,
}) {
  final totals = {
    'strings_processed': 0,
    'resources_renamed': 0,
    'dart_injections': 0,
    'ios_injections': 0,
    'android_injections': 0,
  };
  final skipReasonCounts = <String, int>{};
  final riskItems = <String>{};

  for (final entry in features.entries) {
    if (entry.value is! Map) continue;
    final feature = Map<String, dynamic>.from(entry.value as Map);
    if (feature['mapping'] is! Map) continue;
    final mapping = Map<String, dynamic>.from(feature['mapping'] as Map);
    final featureTitle = '${feature['title'] ?? entry.key}';

    totals['strings_processed'] =
        totals['strings_processed']! + _countStringsProcessed(mapping);
    totals['resources_renamed'] =
        totals['resources_renamed']! + _mapLength(mapping['resource_renames']);
    totals['dart_injections'] =
        totals['dart_injections']! + _countDartInjections(entry.key, mapping);
    totals['ios_injections'] =
        totals['ios_injections']! + _countIosInjections(entry.key, mapping);
    totals['android_injections'] = totals['android_injections']! +
        _countAndroidInjections(entry.key, mapping);

    _collectSkipReasons(mapping['skipped'], skipReasonCounts);
    _collectSkipReasons(mapping['skipped_items'], skipReasonCounts);
    _collectWarnings(featureTitle, mapping['warnings'], riskItems);
    _collectFormatFailures(featureTitle, mapping['format_commands'], riskItems);
  }

  final skipReasons = skipReasonCounts.entries
      .map((entry) => {'reason': entry.key, 'count': entry.value})
      .toList()
    ..sort((a, b) => '${a['reason']}'.compareTo('${b['reason']}'));

  if (skipReasons.isNotEmpty) {
    riskItems.add('存在跳过项，需要确认是否符合预期。');
  }

  return {
    'generated_at': DateTime.now().toIso8601String(),
    'file_counts': {
      'before': beforeFileCount,
      'after': _countProjectFiles(projectPath),
      'excluded_directories': _excludedFileCountDirectories,
      'excluded_files': [unifiedMappingFileName],
    },
    'totals': totals,
    'skip_reasons': skipReasons,
    'risk_items': riskItems.toList()..sort(),
    'manual_check_items': _buildManualCheckItems(totals, skipReasons),
  };
}

int _countProjectFiles(String projectPath) {
  final root = Directory(projectPath);
  if (!root.existsSync()) return 0;
  var count = 0;
  void walk(Directory directory) {
    for (final entity in directory.listSync(followLinks: false)) {
      final basename = p.basename(entity.path);
      if (entity is Directory) {
        if (_shouldExcludeFileCountDirectory(basename)) continue;
        walk(entity);
      } else if (entity is File && basename != unifiedMappingFileName) {
        count++;
      }
    }
  }

  walk(root);
  return count;
}

bool _shouldExcludeFileCountDirectory(String basename) {
  return _excludedFileCountDirectories.contains(basename) ||
      basename.startsWith('temp_');
}

int _countStringsProcessed(Map<String, dynamic> mapping) {
  var count = 0;
  if (mapping['summary'] is Map) {
    count +=
        _asInt((mapping['summary'] as Map)['total_strings_encrypted']) ?? 0;
  }
  if (mapping['string_encryption'] is Map) {
    final stringEncryption = mapping['string_encryption'] as Map;
    count += _countListItemsWithOptionalCount(
        stringEncryption['processed_files'],
        countField: 'strings_encrypted');
  }
  count += _countListItemsWithOptionalCount(mapping['strings_injected']);
  return count;
}

int _countDartInjections(String featureId, Map<String, dynamic> mapping) {
  if (featureId == 'dart_noise') {
    return _listLength(mapping['generated_files']);
  }
  if (featureId == 'class_inner_noise') {
    return _listLength(mapping['members']) + _listLength(mapping['hooks']);
  }
  return 0;
}

int _countIosInjections(String featureId, Map<String, dynamic> mapping) {
  if (featureId == 'ios_noise') return _listLength(mapping['insertions']);
  return 0;
}

int _countAndroidInjections(String featureId, Map<String, dynamic> mapping) {
  if (featureId == 'android_noise') {
    return _listLength(mapping['generated_components']);
  }
  return 0;
}

int _countListItemsWithOptionalCount(Object? value,
    {String countField = 'count'}) {
  if (value is! List) return 0;
  var count = 0;
  for (final item in value) {
    if (item is Map) {
      count += _asInt(item[countField]) ?? _asInt(item['count']) ?? 1;
    } else {
      count++;
    }
  }
  return count;
}

int _listLength(Object? value) => value is List ? value.length : 0;

int _mapLength(Object? value) => value is Map ? value.length : 0;

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

void _collectSkipReasons(Object? value, Map<String, int> counts) {
  if (value is! List) return;
  for (final item in value) {
    var reason = 'unknown';
    if (item is Map) {
      reason = '${item['reason'] ?? item['kind'] ?? 'unknown'}';
    } else if (item != null) {
      reason = '$item';
    }
    counts[reason] = (counts[reason] ?? 0) + 1;
  }
}

void _collectWarnings(
    String featureTitle, Object? value, Set<String> riskItems) {
  if (value is! List) return;
  for (final warning in value) {
    final text = '$warning'.trim();
    if (text.isNotEmpty) riskItems.add('$featureTitle: $text');
  }
}

void _collectFormatFailures(
  String featureTitle,
  Object? value,
  Set<String> riskItems,
) {
  if (value is! List) return;
  for (final item in value) {
    if (item is! Map) continue;
    final exitCode = _asInt(item['exit_code']) ?? 0;
    if (exitCode != 0) {
      riskItems.add('$featureTitle: formatter failed for ${item['file']}');
    }
  }
}

List<String> _buildManualCheckItems(
  Map<String, int> totals,
  List<Map<String, dynamic>> skipReasons,
) {
  final items = <String>[
    '运行 flutter analyze/test/build，确认混淆后工程可编译。',
    '抽查 obfuscation_mapping.html 中的关键文件和资源映射。',
  ];
  if ((totals['android_injections'] ?? 0) > 0) {
    items.add('检查 Android 注入组件、Manifest 注册和资源引用是否符合预期。');
  }
  if ((totals['ios_injections'] ?? 0) > 0) {
    items.add('检查 iOS 注入代码、Xcode 工程引用和格式化结果。');
  }
  if ((totals['dart_injections'] ?? 0) > 0) {
    items.add('检查 Dart 注入入口是否被保留且没有影响启动流程。');
  }
  if (skipReasons.isNotEmpty) {
    items.add('复核跳过原因列表，确认跳过文件或符号不需要人工处理。');
  }
  return items;
}

String _releaseReportCard(Map<String, dynamic> report) {
  if (report.isEmpty) return '';
  final fileCounts = report['file_counts'] is Map
      ? Map<String, dynamic>.from(report['file_counts'] as Map)
      : <String, dynamic>{};
  final totals = report['totals'] is Map
      ? Map<String, dynamic>.from(report['totals'] as Map)
      : <String, dynamic>{};
  final metrics = [
    _metric('混淆前文件数', fileCounts['before']),
    _metric('混淆后文件数', fileCounts['after']),
    _metric('字符串处理数量', totals['strings_processed']),
    _metric('资源改名数量', totals['resources_renamed']),
    _metric('Dart 注入数量', totals['dart_injections']),
    _metric('iOS 注入数量', totals['ios_injections']),
    _metric('Android 注入数量', totals['android_injections']),
  ].join('\n');

  return '''
      <section class="release-report" id="release-report">
        <div class="feature-header">
          <div>
            <p class="eyebrow">发布</p>
            <h2>发布报告</h2>
          </div>
          <span class="updated">生成 ${_escapeHtml('${report['generated_at'] ?? ''}')}</span>
        </div>
        <div class="report-grid">
          $metrics
        </div>
        <div class="report-section">
          ${_reportList('跳过原因', report['skip_reasons'])}
          ${_reportList('风险项', report['risk_items'])}
          ${_reportList('人工检查项', report['manual_check_items'])}
        </div>
      </section>
    ''';
}

String _metric(String label, Object? value) {
  return '''
    <div class="metric">
      <div class="metric-label">${_escapeHtml(label)}</div>
      <div class="metric-value">${_escapeHtml('${value ?? 0}')}</div>
    </div>
  ''';
}

String _reportList(String title, Object? items) {
  if (items is! List || items.isEmpty) {
    return '<h3>${_escapeHtml(title)}</h3><p class="meta">无</p>';
  }
  final rows = items.map((item) {
    if (item is Map) {
      final reason =
          item['reason'] ?? item['item'] ?? item['kind'] ?? 'unknown';
      final count = item['count'];
      return '<li>${_escapeHtml('$reason${count == null ? '' : '：$count'}')}</li>';
    }
    return '<li>${_escapeHtml('$item')}</li>';
  }).join('\n');
  return '<h3>${_escapeHtml(title)}</h3><ul class="report-list">$rows</ul>';
}

String _summaryTable(Object? summary) {
  if (summary is! Map || summary.isEmpty) return '';
  final rows = summary.entries.map((entry) {
    return '<tr><th>${_escapeHtml('${entry.key}')}</th><td>${_escapeHtml('${entry.value}')}</td></tr>';
  }).join('\n');
  return '<table><tbody>$rows</tbody></table>';
}

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _escapeAttr(String value) => _escapeHtml(value);

String _unescapeHtml(String value) {
  return value
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');
}
