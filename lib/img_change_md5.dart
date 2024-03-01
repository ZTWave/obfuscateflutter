import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:obfuscateflutter/consts.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:path/path.dart' as p;

void changeImageMd5(String path) {
  Directory assertsDir = Directory(p.join(path, "asserts"));

  var fileEles = assertsDir.listSync(recursive: true);
  List<File> images = List.empty(growable: true);
  for (var element in fileEles) {
    if (element is File) {
      if (imagesExtNames.contains(getFileExtName(element))) {
        images.add(element);
      }
    }
  }

  for (var imgFile in images) {
    print('file -> $imgFile');
    _printMd5(imgFile);
    _changeMd5(imgFile);
    sleep(Duration(microseconds: 10));
    _printMd5(imgFile);
  }
}

void _changeMd5(File element) {
  var content = element.readAsBytesSync().toList(growable: true);
  var endRandomStr = genRandomKey(Random().nextInt(2) + 1);
  content.addAll(utf8.encode(endRandomStr));
  element.writeAsBytesSync(content);
}

_printMd5(File file) {
  var bytes = file.readAsBytesSync();
  var md5Str = md5.convert(bytes).toString();
  print(md5Str);
}
