import 'dart:io';
import 'package:obfuscateflutter/consts.dart';
import 'package:obfuscateflutter/yaml_helper.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void encryptStrings(String projectPath) {
  Directory libDir = Directory(p.join(projectPath, "lib"));
  final List<File> dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((element) => getFileExtName(element) == '.dart')
      .toList();
  print('all files find done size -> ${dartFiles.length}');

  print(YamlHelper.getAssetsDir(projectPath));
}

String _getPubSpecName(String projectPath) {
  final file = File(p.join(projectPath, "pubspec.yaml"));
  final fileContent = file.readAsStringSync();
  final yamlMap = loadYaml(fileContent);

  return yamlMap['name'].toString();
}

_matchAllStrings(String fileContent) {}
