import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:obfuscateflutter/html_mapping_writer.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:obfuscateflutter/utils/obfuscation_mapping.dart';
import 'package:obfuscateflutter/utils/unified_ast_visitor.dart';
import 'package:obfuscateflutter/yaml_helper.dart';
import 'package:path/path.dart' as p;

final String _defaultStringKeyStoreFile = p.join('lib', 'stren_arg.dart');

/// Run unified obfuscation: file renaming using an AST pass, then output a
/// mapping document for traceability.
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

  // ── 2. Build directory and file rename mappings ──────────────────
  final libPath = libDir.path;
  final directoryMappings = _buildDirectoryMappings(libDir);
  final fileMappings = _buildFileMappings(
    allDartFiles,
    libPath,
    directoryMappings,
  );

  Log.log('Directory rename mappings:');
  directoryMappings.forEach((orig, ob) {
    if (orig != ob) Log.log('  $orig → $ob');
  });

  Log.log('File rename mappings:');
  fileMappings.forEach((orig, ob) {
    if (orig != ob) Log.log('  $orig → $ob');
  });

  // ── 3. Build the mapping document ────────────────────────────────
  final mappingBuilder = MappingBuilder(pubName);
  for (final entry in directoryMappings.entries) {
    if (entry.key != entry.value) {
      mappingBuilder.addDirectoryRename(entry.key, entry.value);
    }
  }
  for (final entry in fileMappings.entries) {
    if (entry.key != entry.value) {
      mappingBuilder.addFileRename(entry.key, entry.value);
    }
  }

  // ── 4. AST rewrite pass — one visitor per file ───────────────────
  for (final file in allDartFiles) {
    final source = file.readAsStringSync();

    CompilationUnit unit;
    try {
      unit = parseString(content: source).unit;
    } catch (e) {
      Log.log('  WARN: cannot parse ${file.path}, skipping ($e)');
      continue;
    }

    final relativeFilePath = _relativePath(file.path, libPath);
    final visitor = UnifiedObfuscationVisitor(
      fileMappings,
      relativeFilePath,
      pubName,
    );
    unit.accept(visitor);

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

    file.writeAsStringSync(modified);

    mappingBuilder.addProcessedFile(
      _relativePath(file.path, libPath),
      visitor.stringEncryptCount,
      visitor.importRewriteCount,
    );

    Log.log('  ${_relativePath(file.path, libPath)}: '
        '${visitor.importRewriteCount} imports');
  }

  // ── 5. Physically rename files on disk ───────────────────────────
  // Rename deepest files first so parent dirs are still present.
  final filesToRename = allDartFiles.where((f) {
    final relativeFilePath = _relativePath(f.path, libPath);
    final newRelativeFilePath = fileMappings[relativeFilePath];
    if (newRelativeFilePath == null) return false;
    return p.basename(relativeFilePath) != p.basename(newRelativeFilePath);
  }).toList()
    ..sort((a, b) => -a.path.length.compareTo(b.path.length));

  for (final file in filesToRename) {
    final relativeFilePath = _relativePath(file.path, libPath);
    final newRelativeFilePath = fileMappings[relativeFilePath]!;
    final newName = p.posix.basename(newRelativeFilePath);
    final dir = p.dirname(file.path);
    final newPath = p.join(dir, newName);

    if (file.path != newPath) {
      Log.log('  rename: ${_relativePath(file.path, libPath)} → '
          '${_relativePath(newPath, libPath)}');
      file.renameSync(newPath);
    }
  }

  // ── 6. Fix part-of directives in generated files ──────────────────
  // .g.dart / .freezed.dart files are excluded from AST processing,
  // but their `part of 'parent.dart'` references must be updated when
  // the parent file was renamed.
  final generatedFiles = Directory(p.join(projectPath, 'lib'))
      .listSync(recursive: true)
      .whereType<File>()
      .where(
          (f) => f.path.endsWith('.g.dart') || f.path.endsWith('.freezed.dart'))
      .toList();

  for (final gf in generatedFiles) {
    var content = gf.readAsStringSync();
    var changed = false;
    final generatedDir = p.posix.dirname(_relativePath(gf.path, libPath));
    for (final entry in fileMappings.entries) {
      if (entry.key == entry.value) continue;
      if (p.posix.dirname(entry.key) != generatedDir) continue;

      final oldName = p.posix.basename(entry.key);
      final newName = p.posix.basename(entry.value);
      // Match: part of 'oldName';  or  part of "oldName";
      final singleQuote = "part of '$oldName';";
      final doubleQuote = 'part of "$oldName";';
      if (content.contains(singleQuote)) {
        content = content.replaceFirst(singleQuote, "part of '$newName';");
        changed = true;
      } else if (content.contains(doubleQuote)) {
        content = content.replaceFirst(doubleQuote, 'part of "$newName";');
        changed = true;
      }
    }
    if (changed) {
      gf.writeAsStringSync(content);
      Log.log('  fix part-of: ${_relativePath(gf.path, libPath)}');
    }
  }

  // ── 7. Physically rename directories on disk ─────────────────────
  final dirsToRename = directoryMappings.entries.where((entry) {
    return entry.key != entry.value &&
        p.posix.basename(entry.key) != p.posix.basename(entry.value);
  }).toList()
    ..sort((a, b) => -a.key.length.compareTo(b.key.length));

  for (final entry in dirsToRename) {
    final newSegment = p.posix.basename(entry.value);
    final oldPath = p.joinAll([libPath, ...entry.key.split('/')]);
    final newPath = p.join(p.dirname(oldPath), newSegment);
    if (oldPath != newPath && Directory(oldPath).existsSync()) {
      Log.log('  rename dir: ${entry.key} → ${entry.value}');
      Directory(oldPath).renameSync(newPath);
    }
  }

  // ── 8. Write mapping document ────────────────────────────────────
  final mapping = mappingBuilder.build();
  final mappingPath = writeHtmlFeatureMapping(
    projectPath: projectPath,
    featureId: 'unified_obfuscation',
    featureTitle: '统一混淆',
    mapping: mapping.toJson(),
  );

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
  return rel.replaceAll(p.separator, '/');
}

Map<String, String> _buildDirectoryMappings(Directory libDir) {
  final dirPaths = libDir
      .listSync(recursive: true)
      .whereType<Directory>()
      .map((dir) => _relativePath(dir.path, libDir.path))
      .where((path) => path.isNotEmpty)
      .where(
          (path) => !path.split('/').any((segment) => segment.startsWith('.')))
      .toList()
    ..sort((a, b) {
      final depthCompare = a.split('/').length.compareTo(b.split('/').length);
      if (depthCompare != 0) return depthCompare;
      return a.compareTo(b);
    });

  final obfuscatedNames = genRandomKeys(dirPaths.length).toList();
  final directoryMappings = <String, String>{};
  var idx = 0;
  for (final oldPath in dirPaths) {
    final parent = p.posix.dirname(oldPath);
    final oldParentPath = parent == '.' ? '' : parent;
    final newParentPath =
        oldParentPath.isEmpty ? '' : directoryMappings[oldParentPath]!;
    final newSegment = obfuscatedNames[idx++];
    final newPath = newParentPath.isEmpty
        ? newSegment
        : p.posix.join(newParentPath, newSegment);
    directoryMappings[oldPath] = newPath;
  }

  return directoryMappings;
}

Map<String, String> _buildFileMappings(
  List<File> dartFiles,
  String libPath,
  Map<String, String> directoryMappings,
) {
  final obfuscatedNames = genRandomKeys(dartFiles.length).toList();
  final fileMappings = <String, String>{};
  var idx = 0;

  for (final file in dartFiles) {
    final oldPath = _relativePath(file.path, libPath);
    final oldDir = p.posix.dirname(oldPath);
    final oldDirPath = oldDir == '.' ? '' : oldDir;
    final newDirPath =
        oldDirPath.isEmpty ? '' : directoryMappings[oldDirPath] ?? oldDirPath;

    final oldName = p.posix.basenameWithoutExtension(oldPath);
    final newName = oldName == 'main' ? oldName : obfuscatedNames[idx++];
    final newFileName = '$newName.dart';
    final newPath = newDirPath.isEmpty
        ? newFileName
        : p.posix.join(newDirPath, newFileName);

    fileMappings[oldPath] = newPath;
  }

  return fileMappings;
}
