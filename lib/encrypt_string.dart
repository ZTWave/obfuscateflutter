import 'dart:io';
import 'dart:math';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:obfuscateflutter/cmd_utils.dart';
import 'package:obfuscateflutter/consts.dart';
import 'package:obfuscateflutter/log.dart';
import 'package:obfuscateflutter/utils/string_ele_visitor.dart';
import 'package:obfuscateflutter/yaml_helper.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';

final String defaultStringFile = p.join('lib', 'common', 'strings.dart');
final String defaultStringKeyStoreFile = p.join('lib', 'stren_arg.dart');

final String defaultStringKeyName = 'SEK';
final String defaultStringPrefixName = 'SEP';

final String obfStringFuncName = 'des';

void encryptStrings(String projectPath) async {
  //Directory libDir = Directory(p.join(projectPath, "lib"));

  File stringFile = File(p.join(projectPath, defaultStringFile));
  if (!stringFile.existsSync()) {
    Log.log('ERROR : string file -> $stringFile not exists');
    exit(-1);
  }
  Log.log('serarch string in this file -> $stringFile');

  /* File stringCryptStoreFile =
      File(p.join(projectPath, defaultStringKeyStoreFile));
  if (!stringCryptStoreFile.existsSync()) {
    Log.log(
        'ERROR : string crypt store file -> $stringCryptStoreFile not exists');
    exit(-1);
  }
  Log.log(
      'serarch string crypt prefix and encrypt key in this file -> $stringCryptStoreFile');

  final sep = _readSep(stringCryptStoreFile);
  final sek = _readSek(stringCryptStoreFile);
  Log.log('string crypt prefix sep -> $sep crypt key -> $sek');

  if (sep.isEmpty || sek.isEmpty) {
    Log.log('string crypt prefix sep -> $sep crypt key -> $sek is empty');
    exit(-1);
  } */

  //format strings file content
  await _formatDartFile(stringFile.path);
}

String _readSep(File stroreFile) {
  final fileLines = stroreFile.readAsLinesSync();
  for (String line in fileLines) {
    if (line.contains(defaultStringPrefixName)) {
      String split;
      if (line.contains('\'')) {
        split = '\'';
      } else {
        split = '"';
      }
      int start = line.indexOf(split);
      int end = line.lastIndexOf(split);
      return line.substring(start + 1, end);
    }
  }
  return '';
}

String _readSek(File stroreFile) {
  final fileLines = stroreFile.readAsLinesSync();
  for (String line in fileLines) {
    if (line.contains(defaultStringKeyName)) {
      RegExp regex = RegExp(r'\d+');
      Match? match = regex.firstMatch(line);
      return match?.group(0) ?? '';
    }
  }
  return '';
}

String _getPubSpecName(String projectPath) {
  final file = File(p.join(projectPath, "pubspec.yaml"));
  final fileContent = file.readAsStringSync();
  final yamlMap = loadYaml(fileContent);

  return yamlMap['name'].toString();
}

_matchAllStrings(String fileContent) {
  RegExp exp = RegExp(r'"([^"\\]*(?:\\.[^"\\]*)*)"');

  Iterable<Match> matches = exp.allMatches(fileContent);

  for (Match match in matches) {
    String extractedString = match.group(1)!;
    print(extractedString);
  }
}

Future<void> _formatDartFile(String filePath) async {
  await dartformatFile(filePath);

  var content = File(filePath).readAsStringSync();

  CompilationUnit ast = parseString(content: content).unit;

  Log.log('ast result --------------------------------');

  final visitor = StringEleVisitor();

  ast.visitChildren(visitor);
}
