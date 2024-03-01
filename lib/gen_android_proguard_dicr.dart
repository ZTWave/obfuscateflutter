import 'dart:io';
import 'dart:developer' as dev;

import 'package:obfuscateflutter/random_key.dart';
import 'package:path/path.dart' as p;

genAndroidProguardDict(String flutterProjectPath) {
  //new dict.txt for android project
  String androidProjectPath = p.join(flutterProjectPath, "android");
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

  String porgardDictPath = p.join(androidProjectPath, "app", "dict.txt");

  File progardDict = File(porgardDictPath);

  var keys = genRandomKeys(10000);
  progardDict.writeAsStringSync(keys.join("\n"),
      flush: true, mode: FileMode.write);

  print("android proguard dict create finished! path -> $porgardDictPath");
}
