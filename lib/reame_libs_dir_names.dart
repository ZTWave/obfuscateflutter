import 'dart:io';
import 'dart:math';

import 'package:obfuscateflutter/pair.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:path/path.dart' as p;

///更新目录名称并更新到代码中
void reNameAllDictorysAndRefresh(String projectPath, String pubSpaceName) {
  print("");

  Directory libDir = Directory(p.join(projectPath, "lib"));
  final List<FileSystemEntity> entities =
      libDir.listSync(recursive: true).toList();
  var dirNamesSet = <String>{};

  var childDirs = <Directory>[];
  entities.forEach((element) {
    if (element is Directory) {
      childDirs.add(element);
      print(element.toString());
      var relativePath = element.path.replaceAll(libDir.path, '');
      var dirNames = relativePath.split(p.separator);
      dirNames.removeWhere((element) => element.isEmpty);
      dirNamesSet.addAll(dirNames);
    }
  });
  print("dir names set length -> ${dirNamesSet.length}");
  print(dirNamesSet.toString());
  var dirObfuscateName = <String>{};
  while (dirObfuscateName.length < dirNamesSet.length) {
    var keyCharLength = Random().nextInt(10) + 2;
    dirObfuscateName.add(genRandomKey(keyCharLength));
  }
  print("dir obfuscate names set length -> ${dirObfuscateName.length}");
  print(dirObfuscateName.toString());

  var obMap = <String, String>{};

  var dirNameList = dirNamesSet.toList();
  var dirObfuscateNameList = dirObfuscateName.toList();
  for (int i = 0; i < dirNamesSet.length; i++) {
    obMap[dirNameList[i]] = dirObfuscateNameList[i];
  }

  List<Pair<String, String>> needReplaceImport = <Pair<String, String>>[];
  childDirs.sort((a, b) {
    return -a.path.length.compareTo(b.path.length);
  });

  childDirs.forEach((dir) {
    var libRelativePath = dir.path.replaceAll(libDir.path, '');
    var obfuscatePath = libRelativePath.obfuscae(obMap);

    needReplaceImport.add(Pair(libRelativePath, obfuscatePath));

    String newPath = libDir.path + obfuscatePath;
    dir.renameSync(newPath);
    sleep(const Duration(microseconds: 50));
    print('rename $dir -> $newPath');
  });
  print("dir rename finished");

  needReplaceImport.sort((a, b) {
    return -a.a.length.compareTo(b.a.length);
  });

  print("replace import start...");
  needReplaceImport.forEach((e) {
    print("${e.a} ==> ${e.b}");
  });

  print("do dart file import refresh");

  final List<FileSystemEntity> entitiesChanged =
      libDir.listSync(recursive: true).toList();
  var childDartFiles = <File>[];
  entitiesChanged.forEach((element) {
    if (element is File) {
      childDartFiles.add(element);
    }
  });

  ///do replace import...
  childDartFiles.forEach((element) {
    element.obfuscate(needReplaceImport, pubSpaceName);
    sleep(const Duration(microseconds: 50));
  });
  print("refresh finished");
}

extension Obfuscate on String {
  String obfuscae(Map<String, String> obMap) {
    String originStr = this;
    List originSplited = originStr.split(p.separator);
    var matchIndex = originSplited.indexOf(originSplited.last);
    if (matchIndex > 0) {
      originSplited[matchIndex] = obMap[originSplited.last];
    }

    return originSplited.join(p.separator);
  }
}

extension ObfuscateFile on File {
  File obfuscate(List<Pair<String, String>> map, String pubSpaceName) {
    final importPrefix = "import 'package:$pubSpaceName";
    final importPrefixQuotedTwo = "export 'package:$pubSpaceName";
    var lines = readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line.startsWith(importPrefix) &&
          !line.startsWith(importPrefixQuotedTwo)) {
        continue;
      }
      print('line -> $line');
      map.forEach((obEntity) {
        var old = '$importPrefix${obEntity.a.replaceAll(p.separator, "/")}/';
        var old2 =
            '$importPrefixQuotedTwo${obEntity.a.replaceAll(p.separator, "/")}/';
        if (line.startsWith(old)) {
          var nen = '$importPrefix${obEntity.b.replaceAll(p.separator, "/")}/';
          print('replace $old -> $nen');
          line = line.replaceAll(old, nen);
        }
        if (line.startsWith(old2)) {
          var nen =
              '$importPrefixQuotedTwo${obEntity.b.replaceAll(p.separator, "/")}/';
          print('replace $old2 -> $nen');
          line = line.replaceAll(old2, nen);
        }
      });
      lines[i] = line;
    }
    writeAsStringSync(lines.join("\n"));
    return this;
  }
}
