import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:obfuscateflutter/utils/string_crypt_utils.dart';
import 'package:obfuscateflutter/utils/string_ele_visitor.dart';
import 'package:obfuscateflutter/yaml_helper.dart';
import 'package:path/path.dart' as p;

final String defaultStringKeyStoreFile = p.join('lib', 'stren_arg.dart');
final String defaultStringKeyName = 'SEK';
final String defaultStringPrefixName = 'SEP';
final String obfStringFuncName = 'des';

void encryptStrings(String projectPath) {
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

  // 1. Setup key store file: read existing or generate new
  final keyFile = File(p.join(projectPath, defaultStringKeyStoreFile));

  String sep;
  int sek;

  if (keyFile.existsSync()) {
    sep = _readSep(keyFile);
    sek = int.tryParse(_readSek(keyFile)) ?? 0;

    if (sep.isEmpty || sek <= 0) {
      Log.log(
          'ERROR: $defaultStringKeyStoreFile exists but SEP/SEK could not be read');
      exit(-1);
    }

    final existingContent = keyFile.readAsStringSync();
    if (!_hasCurrentKeyStoreTemplate(existingContent)) {
      Log.log('$defaultStringKeyStoreFile is outdated, regenerating...');
      _writeKeyStoreFile(keyFile, sep, sek);
    }
  } else {
    sep = _genRandomSep();
    sek = _genRandomSek();
    _writeKeyStoreFile(keyFile, sep, sek);
  }

  Log.log('SEP = $sep, SEK = $sek (store: $defaultStringKeyStoreFile)');

  // 2. Collect all .dart files in lib/
  final dartFiles = _listProcessableDartFiles(projectPath, keyFile.path);

  Log.log('Found ${dartFiles.length} .dart files to process');

  final importLine = "import 'package:$pubName/stren_arg.dart';";

  for (final file in dartFiles) {
    _processFile(file, sep, sek, importLine);
  }

  Log.log('String encryption complete.');
}

void decryptStrings(String projectPath) {
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

  final keyFile = File(p.join(projectPath, defaultStringKeyStoreFile));
  if (!keyFile.existsSync()) {
    Log.log('ERROR: $defaultStringKeyStoreFile not found');
    exit(-1);
  }

  final sep = _readSep(keyFile);
  final sek = int.tryParse(_readSek(keyFile)) ?? 0;
  if (sep.isEmpty || sek <= 0) {
    Log.log(
        'ERROR: $defaultStringKeyStoreFile exists but SEP/SEK could not be read');
    exit(-1);
  }

  final dartFiles = _listProcessableDartFiles(projectPath, keyFile.path);
  final importUri = 'package:$pubName/stren_arg.dart';

  var restoredCount = 0;
  for (final file in dartFiles) {
    restoredCount += _restoreFile(file, sep, sek, importUri);
  }

  final stillReferenced = dartFiles
      .any((file) => file.readAsStringSync().contains('stren_arg.dart'));
  if (!stillReferenced && keyFile.existsSync()) {
    keyFile.deleteSync();
  }

  Log.log('String decryption complete. restored $restoredCount strings');
}

List<File> _listProcessableDartFiles(String projectPath, String keyFilePath) {
  return Directory(p.join(projectPath, 'lib'))
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
      .where((f) => f.path != keyFilePath)
      .toList();
}

void _processFile(File file, String sep, int sek, String importLine) {
  final source = file.readAsStringSync();

  // Skip if import already exists — prevents duplicate imports on re-run
  final hasImport = source.contains('stren_arg.dart');

  CompilationUnit unit;
  try {
    unit = parseString(content: source).unit;
  } catch (e) {
    Log.log('  WARN: cannot parse ${file.path}, skipping ($e)');
    return;
  }

  final visitor = StringEncryptVisitor(sep, sek, obfStringFuncName);
  unit.accept(visitor);

  if (visitor.replacements.isEmpty) return;

  // Apply replacements end-to-start to preserve offsets
  String modified = source;
  final sorted = visitor.replacements
    ..sort((a, b) => b.offset.compareTo(a.offset));
  for (final rep in sorted) {
    modified = modified.replaceRange(rep.offset, rep.end, rep.replacement);
  }

  // Add import if not already present
  if (!hasImport) {
    modified = _insertImport(modified, importLine, unit);
  }

  file.writeAsStringSync(modified);
  Log.log('  ${file.path}: encrypted ${visitor.replacements.length} strings');
}

int _restoreFile(File file, String sep, int sek, String importUri) {
  final source = file.readAsStringSync();

  CompilationUnit unit;
  try {
    unit = parseString(content: source).unit;
  } catch (e) {
    Log.log('  WARN: cannot parse ${file.path}, skipping ($e)');
    return 0;
  }

  final visitor = StringDecryptVisitor(sep, sek, obfStringFuncName);
  unit.accept(visitor);
  if (visitor.replacements.isEmpty) return 0;

  var modified = source;
  final sorted = visitor.replacements
    ..sort((a, b) => b.offset.compareTo(a.offset));
  for (final rep in sorted) {
    modified = modified.replaceRange(rep.offset, rep.end, rep.replacement);
  }

  modified = _removeStringImportIfUnused(modified, importUri);

  file.writeAsStringSync(modified);
  Log.log('  ${file.path}: restored ${visitor.replacements.length} strings');
  return visitor.replacements.length;
}

String _removeStringImportIfUnused(String source, String importUri) {
  CompilationUnit unit;
  try {
    unit = parseString(content: source).unit;
  } catch (_) {
    return source;
  }

  final visitor = _MethodInvocationNameVisitor(obfStringFuncName);
  unit.accept(visitor);
  if (visitor.found) return source;

  final matchingImports = unit.directives
      .whereType<ImportDirective>()
      .where((directive) => directive.uri.stringValue == importUri)
      .toList();
  if (matchingImports.isEmpty) return source;

  final importDirective = matchingImports.first;
  final lineEnd = source.indexOf('\n', importDirective.end);
  final end = lineEnd == -1 ? importDirective.end : lineEnd + 1;
  return source.replaceRange(importDirective.offset, end, '');
}

String _insertImport(String source, String importLine, CompilationUnit unit) {
  final directives = unit.directives;
  if (directives.isEmpty) return '$importLine\n$source';

  final firstPartIdx = directives.indexWhere((d) => d is PartDirective);
  if (firstPartIdx >= 0) {
    final insertPos = directives[firstPartIdx].offset;
    return '${source.substring(0, insertPos)}$importLine\n'
        '${source.substring(insertPos)}';
  }

  final insertPos = directives.last.end;
  return '${source.substring(0, insertPos)}\n$importLine'
      '${source.substring(insertPos)}';
}

String _readSep(File storeFile) {
  final content = storeFile.readAsStringSync();
  // Match single-quoted
  final m1 = RegExp(r"const String SEP\s*=\s*'([^']*)'").firstMatch(content);
  if (m1 != null) return m1.group(1)!;
  // Match double-quoted
  final m2 = RegExp(r'const String SEP\s*=\s*"([^"]*)"').firstMatch(content);
  return m2?.group(1) ?? '';
}

String _readSek(File storeFile) {
  final content = storeFile.readAsStringSync();
  final match = RegExp(r'const int SEK\s*=\s*(\d+)').firstMatch(content);
  return match?.group(1) ?? '';
}

bool _hasCurrentKeyStoreTemplate(String content) {
  return content.contains('String $obfStringFuncName(') &&
      content.contains('_DES_CACHE_LIMIT') &&
      content.contains('LinkedHashMap<String, String>');
}

void _writeKeyStoreFile(File file, String sep, int sek) {
  file.writeAsStringSync('''
// Auto-generated by obfuscateflutter -- do not edit manually.
import 'dart:collection';
import 'dart:convert';

const String $defaultStringPrefixName = '$sep';
const int $defaultStringKeyName = $sek;
const int _DES_CACHE_LIMIT = 512;

final _desCache = LinkedHashMap<String, String>();

String $obfStringFuncName(String s) {
  if (!s.startsWith($defaultStringPrefixName)) return s;
  final cached = _desCache.remove(s);
  if (cached != null) {
    _desCache[s] = cached;
    return cached;
  }
  try {
    final encoded = s.substring($defaultStringPrefixName.length);
    final shifted = base64.decode(encoded);
    final bytes = shifted.map((b) => (b - $defaultStringKeyName + 256) % 256).toList();
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

class StringDecryptVisitor extends RecursiveAstVisitor<void> {
  final String sep;
  final int sek;
  final String funcName;

  final List<StringReplacementData> replacements = [];

  StringDecryptVisitor(this.sep, this.sek, this.funcName);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != funcName || node.target != null) {
      super.visitMethodInvocation(node);
      return;
    }

    final arguments = node.argumentList.arguments;
    if (arguments.length != 1 || arguments.first is! SimpleStringLiteral) {
      super.visitMethodInvocation(node);
      return;
    }

    final encryptedLiteral = arguments.first as SimpleStringLiteral;
    final encrypted = encryptedLiteral.value;
    if (!encrypted.startsWith(sep)) {
      super.visitMethodInvocation(node);
      return;
    }

    try {
      final decrypted = StringCryptUtils.decrypt(
        encrypted.substring(sep.length),
        sek,
      );
      replacements.add(
        StringReplacementData(
          node.offset,
          node.end,
          _toDartSingleQuotedString(decrypted),
        ),
      );
    } catch (_) {
      // Leave malformed encrypted calls unchanged.
    }

    super.visitMethodInvocation(node);
  }
}

class _MethodInvocationNameVisitor extends RecursiveAstVisitor<void> {
  final String name;
  var found = false;

  _MethodInvocationNameVisitor(this.name);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == name) {
      found = true;
      return;
    }
    super.visitMethodInvocation(node);
  }
}

String _toDartSingleQuotedString(String value) {
  final buffer = StringBuffer("'");
  for (final rune in value.runes) {
    switch (rune) {
      case 0x08:
        buffer.write(r'\b');
        break;
      case 0x09:
        buffer.write(r'\t');
        break;
      case 0x0A:
        buffer.write(r'\n');
        break;
      case 0x0C:
        buffer.write(r'\f');
        break;
      case 0x0D:
        buffer.write(r'\r');
        break;
      case 0x24:
        buffer.write(r'\$');
        break;
      case 0x27:
        buffer.write(r"\'");
        break;
      case 0x5C:
        buffer.write(r'\\');
        break;
      default:
        if (rune < 0x20 || rune == 0x7F) {
          buffer.write(r'\u{');
          buffer.write(rune.toRadixString(16));
          buffer.write('}');
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  buffer.write("'");
  return buffer.toString();
}
