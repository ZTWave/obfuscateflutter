import 'dart:io';

import 'package:obfuscateflutter/consts.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:path/path.dart' as p;

void proguardImages(String projectPath) {
  List<ImageProguardData> imageMapper = List.empty(growable: true);

  Directory assertsDir = Directory(p.join(projectPath, "asserts"));

  var fileEles = assertsDir.listSync(recursive: true);
  List<File> images = List.empty(growable: true);
  for (var element in fileEles) {
    if (element is File) {
      if (imagesExtNames.contains(getFileExtName(element))) {
        images.add(element);
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
    }
    element.writeAsStringSync(codeStr, flush: true, mode: FileMode.write);
  });

  for (int i = 0; i < imageMapper.length; i++) {
    var element = imageMapper[i];
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
