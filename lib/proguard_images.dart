import 'dart:io';

import 'package:obfuscateflutter/consts.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:obfuscateflutter/yaml_helper.dart';
import 'package:path/path.dart' as p;

void proguardImages(String projectPath) {
  List<ImageProguardData> imageMapper = List.empty(growable: true);

  List<Directory> assertsDir = YamlHelper.getAssetsDir(projectPath)
      .map((String e) => Directory(p.join(projectPath, e)))
      .toList();

  List<FileSystemEntity> fileEles = [];

  for (final dir in assertsDir) {
    fileEles.addAll(dir.listSync(recursive: true));
  }

  List<File> images = List.empty(growable: true);
  for (var element in fileEles) {
    if (element is File) {
      if (imagesExtNames.contains(getFileExtName(element))) {
        if (images.where((e) => e.path == element.path).isEmpty) {
          images.add(element);
        }
      }
    }
  }

  List<String> proguardKeys = genRandomKeys(images.length).toList();
  for (int j = 0; j < images.length; j++) {
    var element = images[j];
    imageMapper.add(ImageProguardData(element.path.split(p.separator).last,
        proguardKeys[j] + getFileExtName(element), getFileDirPath(element)));
  }

  Directory libDir = Directory(p.join(projectPath, "lib"));
  final List<FileSystemEntity> entities =
      libDir.listSync(recursive: true).toList();

  List<FileSystemEntity> allFiles = entities
      .where((value) => value is File && getFileExtName(value) == ".dart")
      .toList();

  allFiles.forEach((element) {
    if (element is! File) {
      return;
    }

    String codeStr = element.readAsStringSync();
    for (int i = 0; i < imageMapper.length; i++) {
      var imageItem = imageMapper[i];
      if (codeStr.contains("\"${imageItem.originalName}\"")) {
        imageItem.used = true;
        codeStr = codeStr.replaceAll(
            "\"${imageItem.originalName}\"", "\"${imageItem.proguardName}\"");
      }
      if (codeStr.contains("'${imageItem.originalName}'")) {
        imageItem.used = true;
        codeStr = codeStr.replaceAll(
            "'${imageItem.originalName}'", "'${imageItem.proguardName}'");
      }

      final posableUsage = _getPathFromAsserts(
          imageItem.path, assertsDir.map((e) => e.path).toList());

      for (String usage in posableUsage) {
        final doubleUsage = "\"$usage/${imageItem.originalName}\"";
        if (codeStr.contains(doubleUsage)) {
          imageItem.used = true;
          final old = "\"$usage/${imageItem.originalName}\"";
          final nww = "\"$usage/${imageItem.proguardName}\"";
          codeStr = codeStr.replaceAll(old, nww);
        }

        final singleUsage = "'$usage/${imageItem.originalName}'";
        if (codeStr.contains(singleUsage)) {
          imageItem.used = true;
          final old = "'$usage/${imageItem.originalName}'";
          final nww = "'$usage/${imageItem.proguardName}'";
          codeStr = codeStr.replaceAll(old, nww);
        }
      }
    }
    element.writeAsStringSync(codeStr, flush: true, mode: FileMode.write);
  });

  for (int i = 0; i < imageMapper.length; i++) {
    var element = imageMapper[i];
    print('image file => $element');
    File file = File(p.join(element.path, element.originalName));
    if (!element.used) {
      file.deleteSync();
    } else {
      file.renameSync(p.join(element.path, element.proguardName));
    }
  }

  _printMapping(imageMapper);
}

void _printMapping(List<ImageProguardData> imageMapper) {
  for (var element in imageMapper) {
    if (element.used) {
      print("rename image ${element.originalName} to ${element.proguardName}");
    } else {
      print("remove image ${element.originalName}");
    }
  }
}

//all path is abslutate path
List<String> _getPathFromAsserts(
    String imgParentPath, List<String> assertsPaths) {
  final posableImageUsages = <String>[];
  for (String assertsPath in assertsPaths) {
    final assertsFolderName = assertsPath
        .split(p.separator)
        .lastWhere((element) => element.isNotEmpty);

    final imageParentPathArray = imgParentPath.split(p.separator);

    var index = imageParentPathArray.indexOf(assertsFolderName);

    if (index >= 0) {
      final List<String> pathList =
          imageParentPathArray.sublist(index - 1).toList(growable: true);
      //pathList.insert(0, assertsFolderName);
      posableImageUsages.add(pathList.join("/"));
    }
  }

  return posableImageUsages;
}

class ImageProguardData {
  String originalName;
  String proguardName;
  String path;
  bool used = false;

  ImageProguardData(this.originalName, this.proguardName, this.path);

  @override
  String toString() {
    return "ImageProguardData originalName->$originalName proguardName->$proguardName path->$path used->$used";
  }
}
