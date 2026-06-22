import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const unifiedMappingFileName = 'obfuscation_mapping.html';
const _dataScriptId = 'obfuscation-mapping-data';

String writeHtmlFeatureMapping({
  required String projectPath,
  required String featureId,
  required String featureTitle,
  required Map<String, dynamic> mapping,
}) {
  final outputFile = File(p.join(projectPath, unifiedMappingFileName));
  final document = outputFile.existsSync()
      ? _readDocument(outputFile.readAsStringSync())
      : <String, dynamic>{
          'version': '2.0',
          'created_at': DateTime.now().toIso8601String(),
          'features': <String, dynamic>{},
        };

  final features = (document['features'] is Map)
      ? Map<String, dynamic>.from(document['features'] as Map)
      : <String, dynamic>{};
  final now = DateTime.now().toIso8601String();
  document['updated_at'] = now;
  document['features'] = features;
  features[featureId] = {
    'title': featureTitle,
    'updated_at': now,
    'mapping': mapping,
  };

  outputFile.writeAsStringSync(_renderHtml(document));
  return outputFile.path;
}

Map<String, dynamic> _readDocument(String html) {
  final pattern = RegExp(
    '<script[^>]*id="$_dataScriptId"[^>]*>([\\s\\S]*?)</script>',
    multiLine: true,
  );
  final match = pattern.firstMatch(html);
  if (match == null) {
    return {
      'version': '2.0',
      'created_at': DateTime.now().toIso8601String(),
      'features': <String, dynamic>{},
    };
  }
  try {
    final decoded = jsonDecode(_unescapeHtml(match.group(1)!.trim()));
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // Fall through and rebuild the document. A broken mapping page should not
    // block the current obfuscation task from writing a fresh report.
  }
  return {
    'version': '2.0',
    'created_at': DateTime.now().toIso8601String(),
    'features': <String, dynamic>{},
  };
}

String _renderHtml(Map<String, dynamic> document) {
  final features = document['features'] is Map
      ? Map<String, dynamic>.from(document['features'] as Map)
      : <String, dynamic>{};
  final orderedEntries = features.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final dataJson = const JsonEncoder.withIndent('  ').convert(document);
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
    .feature {
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 8px;
      margin-bottom: 18px;
      overflow: hidden;
    }
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
      $navItems
    </nav>
    <main>
      $featureCards
    </main>
  </div>
  <script id="$_dataScriptId" type="application/json">${_escapeHtml(dataJson)}</script>
</body>
</html>
''';
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
