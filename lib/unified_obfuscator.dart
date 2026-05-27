import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:obfuscateflutter/utils/obfuscation_mapping.dart';
import 'package:obfuscateflutter/utils/unified_ast_visitor.dart';
import 'package:obfuscateflutter/yaml_helper.dart';
import 'package:path/path.dart' as p;

final String _defaultStringKeyStoreFile = p.join('lib', 'stren_arg.dart');
final String _defaultStringKeyName = 'SEK';
final String _defaultStringPrefixName = 'SEP';
final String _obfStringFuncName = 'des';

/// Run unified obfuscation: file renaming + string encryption using a single
/// AST pass, then output a mapping document for traceability.
void runUnifiedObfuscation(String projectPath) {
  final libDir = Directory(p.join(projectPath, 'lib'));
  if (!libDir.existsSync()) {
    Log.log('ERROR: lib directory not found in $projectPath');
    exit(-1);
  }

  final pubName = YamlHelper.getPubSpecName(projectPath);
  if (pubName.isEmpty) {
    Log.log('ERROR: cannot read pubspec name');
    exit(-1);
  }

  // ── 1. Collect all processable .dart files ───────────────────────
  final keyFilePath = p.join(projectPath, _defaultStringKeyStoreFile);
  final allDartFiles = Directory(p.join(projectPath, 'lib'))
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
      .where((f) => f.path != keyFilePath)
      .toList();

  Log.log('Found ${allDartFiles.length} .dart files to process');

  // ── 2. Build file-rename mapping ─────────────────────────────────
  // Collect unique basenames (without .dart) across all files.
  final basenameSet = <String>{};
  for (final f in allDartFiles) {
    final basename =
        p.basenameWithoutExtension(f.path);
    basenameSet.add(basename);
  }

  // Generate obfuscated names.  main stays as-is.
  final obfuscatedNames = genRandomKeys(basenameSet.length).toList();
  final fileMappings = <String, String>{};
  var idx = 0;
  for (final name in basenameSet) {
    if (name == 'main') {
      fileMappings[name] = name;
    } else {
      fileMappings[name] = obfuscatedNames[idx++];
    }
  }

  Log.log('File rename mappings:');
  fileMappings.forEach((orig, ob) {
    if (orig != ob) Log.log('  $orig.dart → $ob.dart');
  });

  // ── 3. Set up string encryption keys ────────────────────────────
  final keyFile = File(keyFilePath);
  String sep;
  int sek;

  if (keyFile.existsSync()) {
    sep = _readSep(keyFile);
    sek = int.tryParse(_readSek(keyFile)) ?? 0;
    if (sep.isEmpty || sek <= 0) {
      Log.log('ERROR: $keyFilePath exists but SEP/SEK could not be read');
      exit(-1);
    }
    if (!_hasCurrentKeyStoreTemplate(keyFile.readAsStringSync())) {
      Log.log('$keyFilePath is outdated, regenerating...');
      _writeKeyStoreFile(keyFile, sep, sek);
    }
  } else {
    sep = _genRandomSep();
    sek = _genRandomSek();
    _writeKeyStoreFile(keyFile, sep, sek);
  }

  Log.log('String encryption: SEP=$sep SEK=$sek');

  // ── 4. Build the mapping document ────────────────────────────────
  final mappingBuilder = MappingBuilder(pubName);
  mappingBuilder.setStringEncryption(_defaultStringKeyStoreFile, sep, sek);
  for (final entry in fileMappings.entries) {
    if (entry.key != entry.value) {
      mappingBuilder.addFileRename('${entry.key}.dart', '${entry.value}.dart');
    }
  }

  final importLine = "import 'package:$pubName/stren_arg.dart';";

  // ── 5. AST rewrite pass — one visitor per file ───────────────────
  final libPath = libDir.path;

  for (final file in allDartFiles) {
    final source = file.readAsStringSync();
    final hasImport = source.contains('stren_arg.dart');

    CompilationUnit unit;
    try {
      unit = parseString(content: source).unit;
    } catch (e) {
      Log.log('  WARN: cannot parse ${file.path}, skipping ($e)');
      continue;
    }

    final visitor =
        UnifiedObfuscationVisitor(fileMappings, sep, sek, _obfStringFuncName);
    unit.accept(visitor);

    if (visitor.replacements.isEmpty && hasImport) {
      // File already processed (import exists) and nothing to encrypt/rewrite.
      mappingBuilder.addProcessedFile(
        _relativePath(file.path, libPath),
        0,
        0,
      );
      continue;
    }

    if (visitor.replacements.isEmpty) {
      mappingBuilder.addProcessedFile(
        _relativePath(file.path, libPath),
        0,
        0,
      );
      continue;
    }

    // Apply replacements end-to-start so offsets stay valid.
    String modified = source;
    final sorted = visitor.replacements
      ..sort((a, b) => b.offset.compareTo(a.offset));
    for (final rep in sorted) {
      modified = modified.replaceRange(rep.offset, rep.end, rep.replacement);
    }

    // Add string-encryption import if any strings were encrypted
    // and the import is not already present.
    if (visitor.stringEncryptCount > 0 && !hasImport) {
      try {
        // Re-parse the modified source to find the correct insertion point,
        // since offsets may have shifted.
        final modifiedUnit = parseString(content: modified).unit;
        modified = _insertImport(modified, importLine, modifiedUnit);
      } catch (_) {
        // If re-parsing fails, prepend the import.
        modified = '$importLine\n$modified';
      }
    }

    file.writeAsStringSync(modified);

    mappingBuilder.addProcessedFile(
      _relativePath(file.path, libPath),
      visitor.stringEncryptCount,
      visitor.importRewriteCount,
    );

    Log.log('  ${_relativePath(file.path, libPath)}: '
        '${visitor.stringEncryptCount} strings, '
        '${visitor.importRewriteCount} imports');
  }

  // ── 6. Physically rename files on disk ───────────────────────────
  // Rename deepest files first so parent dirs are still present.
  final filesToRename = allDartFiles
      .where((f) {
        final basename = p.basenameWithoutExtension(f.path);
        return fileMappings.containsKey(basename) &&
            fileMappings[basename] != basename;
      })
      .toList()
    ..sort((a, b) => -a.path.length.compareTo(b.path.length));

  for (final file in filesToRename) {
    final basename = p.basenameWithoutExtension(file.path);
    final newName = fileMappings[basename]!;
    final dir = p.dirname(file.path);
    final newPath = p.join(dir, '$newName.dart');

    if (file.path != newPath) {
      Log.log('  rename: ${_relativePath(file.path, libPath)} → '
          '${_relativePath(newPath, libPath)}');
      file.renameSync(newPath);
    }
  }

  // ── 7. Fix part-of directives in generated files ──────────────────
  // .g.dart / .freezed.dart files are excluded from AST processing,
  // but their `part of 'parent.dart'` references must be updated when
  // the parent file was renamed.
  final generatedFiles = Directory(p.join(projectPath, 'lib'))
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.g.dart') || f.path.endsWith('.freezed.dart'))
      .toList();

  for (final gf in generatedFiles) {
    var content = gf.readAsStringSync();
    var changed = false;
    for (final entry in fileMappings.entries) {
      if (entry.key == entry.value) continue;
      final oldName = '${entry.key}.dart';
      final newName = '${entry.value}.dart';
      // Match: part of 'oldName';  or  part of "oldName";
      final singleQuote = "part of '$oldName';";
      final doubleQuote = 'part of "$oldName";';
      if (content.contains(singleQuote)) {
        content = content.replaceFirst(
            singleQuote, "part of '$newName';");
        changed = true;
      } else if (content.contains(doubleQuote)) {
        content = content.replaceFirst(
            doubleQuote, 'part of "$newName";');
        changed = true;
      }
    }
    if (changed) {
      gf.writeAsStringSync(content);
      Log.log('  fix part-of: ${_relativePath(gf.path, libPath)}');
    }
  }

  // ── 8. Write mapping document ────────────────────────────────────
  final mapping = mappingBuilder.build();
  final mappingPath =
      p.join(projectPath, 'obfuscation_mapping_${_timestamp()}.json');
  mapping.writeToFile(mappingPath);

  Log.log('');
  Log.log('Unified obfuscation complete.');
  Log.log('Mapping document: $mappingPath');
  Log.log('Summary:');
  final summary = mapping.toJson()['summary'] as Map<String, dynamic>;
  summary.forEach((k, v) => Log.log('  $k: $v'));
}

// ── Helpers ────────────────────────────────────────────────────────────

String _relativePath(String fullPath, String basePath) {
  var rel = fullPath;
  if (fullPath.startsWith(basePath)) {
    rel = fullPath.substring(basePath.length);
    if (rel.startsWith(p.separator)) rel = rel.substring(1);
  }
  return rel;
}

String _timestamp() {
  final now = DateTime.now();
  return '${now.year}${_pad(now.month)}${_pad(now.day)}_'
      '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
}

String _pad(int n) => n.toString().padLeft(2, '0');

String _insertImport(String source, String importLine, CompilationUnit unit) {
  final directives = unit.directives;
  if (directives.isEmpty) return '$importLine\n$source';

  // Insert after the last import/export, but before the first part directive.
  // Dart requires: imports → exports → parts
  final firstPartIdx = directives.indexWhere((d) => d is PartDirective);
  if (firstPartIdx >= 0) {
    final insertPos = directives[firstPartIdx].offset;
    return '${source.substring(0, insertPos)}$importLine\n'
        '${source.substring(insertPos)}';
  }

  // No part directives — insert after the last directive.
  final insertPos = directives.last.end;
  return '${source.substring(0, insertPos)}\n$importLine'
      '${source.substring(insertPos)}';
}

// ── Key store file ────────────────────────────────────────────────────

String _readSep(File storeFile) {
  final content = storeFile.readAsStringSync();
  final m1 =
      RegExp(r"const String SEP\s*=\s*'([^']*)'").firstMatch(content);
  if (m1 != null) return m1.group(1)!;
  final m2 =
      RegExp(r'const String SEP\s*=\s*"([^"]*)"').firstMatch(content);
  return m2?.group(1) ?? '';
}

String _readSek(File storeFile) {
  final content = storeFile.readAsStringSync();
  final match = RegExp(r'const int SEK\s*=\s*(\d+)').firstMatch(content);
  return match?.group(1) ?? '';
}

bool _hasCurrentKeyStoreTemplate(String content) {
  return content.contains('String $_obfStringFuncName(') &&
      content.contains('_DES_CACHE_LIMIT') &&
      content.contains('LinkedHashMap<String, String>');
}

void _writeKeyStoreFile(File file, String sep, int sek) {
  file.writeAsStringSync('''
// Auto-generated by obfuscateflutter -- do not edit manually.
import 'dart:collection';
import 'dart:convert';

const String $_defaultStringPrefixName = '$sep';
const int $_defaultStringKeyName = $sek;
const int _DES_CACHE_LIMIT = 512;

final _desCache = LinkedHashMap<String, String>();

String $_obfStringFuncName(String s) {
  if (!s.startsWith($_defaultStringPrefixName)) return s;
  final cached = _desCache.remove(s);
  if (cached != null) {
    _desCache[s] = cached;
    return cached;
  }
  try {
    final encoded = s.substring($_defaultStringPrefixName.length);
    final shifted = base64.decode(encoded);
    final bytes = shifted.map((b) => (b - $_defaultStringKeyName + 256) % 256).toList();
    final decoded = utf8.decode(bytes);
    if (_desCache.length >= _DES_CACHE_LIMIT) {
      _desCache.remove(_desCache.keys.first);
    }
    _desCache[s] = decoded;
    return decoded;
  } catch (_) {
    return s;
  }
}
''');
}

String _genRandomSep() {
  const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz';
  final rand = Random();
  return List.generate(3, (_) => chars[rand.nextInt(chars.length)]).join();
}

int _genRandomSek() => Random().nextInt(255) + 1;
