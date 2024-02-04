import 'dart:convert';
import 'dart:core';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

import 'package:obfuscateflutter/build_apk.dart';

void main() async {
  print('Hello, Creeper!');
  print(
      'brfore you start this project change all relative import to start with package import!');
  print('please input flutter project:');

  final process = await Process.start(
    'chdir',
    [],
    runInShell: true,
  );
  print('out');
  var out = await process.stdout.transform(utf8.decoder).join();
  process.kill();

  final String projectPath = out.replaceAll('\n', '').trim();

  print('project path : $projectPath');
  if (projectPath == null || projectPath.isEmpty == true) {
    print('flutter project is empty!!!');
    return;
  }

  Directory? project;
  try {
    project = Directory(projectPath);
  } on Exception catch (e) {
    print(e.toString());
  }
  if (project == null || !project.existsSync()) {
    print('flutter project isn\'t exit!!!');
    return;
  }

  var pubFile = File(project.path + "\\pubspec.yaml");
  var pubSpaceName = '';

  pubFile.readAsLinesSync().forEach((line) {
    if (line.startsWith("name:")) {
      pubSpaceName = line.replaceAll("name:", '').trim();
    }
  });
  print('flutter project pubspec name is $pubSpaceName');
  print("start gen android obfuscate dictory");
  _genAndroidProguardDict(project.path);

  sleep(Duration(seconds: 3));
  print("start rename lib's child folders name and refresh code import");
  _reNameAllDictorysAndRefresh(project, pubSpaceName);

  sleep(Duration(seconds: 3));
  print("start rename lib's child file name and refresh code import");
  _renameAllFileNames(project);

  print("build apk start...");
  sleep(Duration(seconds: 1));
  buildReleaseApk(projectPath);
}

_renameAllFileNames(Directory project) {
  Directory libDir = Directory(project.path + "\\lib");
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
    fileNameSet.add(element.path.split("\\").last.replaceAll(".dart", ""));
  });
  fileObfuscateNameSet = _genRandomKeys(fileNameSet.length).toList();
  List<Pair<String, String>> obMap =
      toPairList(fileNameSet, fileObfuscateNameSet);

  print('file name ob map:');
  obMap.forEach((element) {
    print(element);
  });

  File replaceNameLog = File(project.path + "\\replace_name.log");
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
    if (!newPath.contains("\\main.dart")) {
      obMap.forEach((obFileNameMap) {
        if (newPath.contains("\\" + obFileNameMap.a + '.dart')) {
          print(
              "old path -> $newPath new ob-path replace ${obFileNameMap.a + '.dart'} to ${obFileNameMap.b + '.dart'}");
          newPath = newPath.replaceAll(
              obFileNameMap.a + '.dart', obFileNameMap.b + '.dart');
        }
      });
      file.renameSync(newPath);
    }
  });
}

List<Pair<String, String>> toPairList(
  List<String> a,
  List<String> b,
) {
  List<Pair<String, String>> result = List.empty(growable: true);
  for (int i = 0; i < a.length; i++) {
    result.add(Pair(a[i], b.elementAtOrNull(i) ?? ''));
  }
  return result;
}

///更新目录名称并更新到代码中
void _reNameAllDictorysAndRefresh(Directory project, String pubSpaceName) {
  print("");

  Directory libDir = Directory(project.path + "\\lib");
  final List<FileSystemEntity> entities =
      libDir.listSync(recursive: true).toList();
  var dirNamesSet = Set<String>();

  var childDirs = <Directory>[];
  entities.forEach((element) {
    if (element is Directory) {
      childDirs.add(element);
      print(element.toString());
      var relativePath = element.path.replaceAll(libDir.path, '');
      var dirNames = relativePath.split("\\");
      dirNames.removeWhere((element) => element.isEmpty);
      dirNamesSet.addAll(dirNames);
    }
  });
  print("dir names set length -> ${dirNamesSet.length}");
  print(dirNamesSet.toString());
  var dirObfuscateName = <String>{};
  while (dirObfuscateName.length < dirNamesSet.length) {
    var keyCharLength = Random().nextInt(10) + 2;
    dirObfuscateName.add(_genRandomKey(keyCharLength));
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
    List originSplited = originStr.split('\\');
    var matchIndex = originSplited.indexOf(originSplited.last);
    if (matchIndex > 0) {
      originSplited[matchIndex] = obMap[originSplited.last];
    }

    return originSplited.join("\\");
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
        var old = importPrefix + obEntity.a.replaceAll("\\", "/") + '/';
        var old2 =
            importPrefixQuotedTwo + obEntity.a.replaceAll("\\", "/") + '/';
        if (line.startsWith(old)) {
          var nen = importPrefix + obEntity.b.replaceAll("\\", "/") + '/';
          print('replace $old -> $nen');
          line = line.replaceAll(old, nen);
        }
        if (line.startsWith(old2)) {
          var nen =
              importPrefixQuotedTwo + obEntity.b.replaceAll("\\", "/") + '/';
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

_genAndroidProguardDict(String flutterProjectPath) {
  //new dict.txt for android project
  String androidProjectPath = flutterProjectPath + "\\android";
  Directory? androidProject;
  try {
    androidProject = Directory(androidProjectPath);
  } on Exception catch (e) {
    dev.log(e.toString());
  }
  if (androidProject == null || !androidProject.existsSync()) {
    print('flutter project isn\'t exit!!!');
    return;
  }
  print("android project path -> $androidProjectPath");

  String porgardDictPath = androidProjectPath + "\\app\\dict.txt";

  File progardDict = File(porgardDictPath);

  var keys = _genRandomKeys(10000);
  progardDict.writeAsStringSync(keys.join("\n"),
      flush: true, mode: FileMode.write);

  print("android proguard dict create finished! path -> $porgardDictPath");
}

const _chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
const _firstChars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz';
Set<String> _genRandomKeys(int keysLength) {
  var keys = <String>{};

  for (int i = 0; keys.length < keysLength; i++) {
    var keyCharLength = Random().nextInt(12) + 3;
    String randomKey = _genRandomKey(keyCharLength);

    keys.add(randomKey);
  }

  return keys;
}

String _genRandomKey(int keyCharLength) {
  String randomKey = '';
  randomKey += _firstChars[Random().nextInt(_firstChars.length)];
  for (int j = 1; j < keyCharLength; j++) {
    randomKey += _chars[Random().nextInt(_chars.length)];
  }
  return randomKey;
}

class Pair<A, B> {
  A a;
  B b;

  Pair(this.a, this.b);

  @override
  String toString() {
    return "${a.toString()} -> ${b.toString()}";
  }
}
