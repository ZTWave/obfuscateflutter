import 'dart:io';

import 'package:obfuscateflutter/pair.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:path/path.dart' as p;

renameAllFileNames(String projectPath) {
  Directory libDir = Directory(p.join(projectPath, "lib"));
  final List<FileSystemEntity> entities =
      libDir.listSync(recursive: true).toList();

  List<FileSystemEntity> allFiles =
      entities.where((value) => value is File).toList();
  var fileNameSet = <String>[];
  var fileObfuscateNameSet = <String>[];
  allFiles.forEach((element) {
    if (element is! File) {
      return;
    }

    ///a.dart
    fileNameSet
        .add(element.path.split(p.separator).last.replaceAll(".dart", ""));
  });
  fileObfuscateNameSet = genRandomKeys(fileNameSet.length).toList();
  List<Pair<String, String>> obMap =
      toPairList(fileNameSet, fileObfuscateNameSet);

  print('file name ob map:');
  obMap.forEach((element) {
    print(element);
  });

  File replaceNameLog = File(p.join(projectPath, "replace_name.log"));
  replaceNameLog.writeAsStringSync(obMap.map((e) => e.toString()).join("\n"));

  print("replaceing file ...");
  allFiles.forEach((file) {
    if (file is! File) {
      return;
    }
    var originContent = file.readAsLinesSync();
    List<String> obfuscateContent = List.empty(growable: true);

    for (String codeLine in originContent) {
      String obCodeLine = codeLine;
      if (obCodeLine.startsWith("import") || obCodeLine.startsWith("export")) {
        obMap.forEach((obFileNameMap) {
          if (obCodeLine.contains("/" + obFileNameMap.a + '.dart') ||
              obCodeLine.contains("\'" + obFileNameMap.a + '.dart') ||
              obCodeLine.contains("\"" + obFileNameMap.a + '.dart')) {
            print("replacing code => ${obCodeLine}");
            print(
                'replace file $file content ${obFileNameMap.a + '.dart'} => ${obFileNameMap.b + '.dart'}');
            obCodeLine = obCodeLine.replaceAll(
                obFileNameMap.a + '.dart', obFileNameMap.b + '.dart');
          }
        });
      }
      obfuscateContent.add(obCodeLine);
    }

    file.writeAsStringSync(obfuscateContent.join("\n"));
    String newPath = file.path;
    //skip main.dart
    if (!newPath.contains("${p.separator}main.dart")) {
      obMap.forEach((obFileNameMap) {
        if (newPath.contains('${p.separator}${obFileNameMap.a}.dart')) {
          print(
              "old path -> $newPath new ob-path replace ${obFileNameMap.a + '.dart'} to ${obFileNameMap.b + '.dart'}");
          newPath = newPath.replaceAll(
              '${obFileNameMap.a}.dart', '${obFileNameMap.b}.dart');
        }
      });
      file.renameSync(newPath);
    }
  });
}
