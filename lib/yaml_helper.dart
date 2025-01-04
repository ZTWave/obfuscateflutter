import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class YamlHelper {
  static String _getYamlContent(String projectPath) {
    final file = File(p.join(projectPath, "pubspec.yaml"));
    return file.readAsStringSync();
  }

  static String getPubSpecName(String projectPath) {
    final yamlMap = loadYaml(_getYamlContent(projectPath));
    return yamlMap['name'].toString();
  }

  //获取配置的资源目录
  static List<String> getAssetsDir(String projectPath) {
    final yamlMap = loadYaml(_getYamlContent(projectPath));
    return (yamlMap['flutter']['assets'] as YamlList)
        .nodes
        .map((element) => p.joinAll(element.value.toString().split('/')))
        .toList();
  }
}
