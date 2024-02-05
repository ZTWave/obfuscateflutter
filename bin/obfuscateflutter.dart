import 'dart:convert';
import 'dart:core';
import 'dart:io';

import 'package:args/args.dart';
import 'package:obfuscateflutter/build_apk.dart';
import 'package:obfuscateflutter/gen_android_proguard_dicr.dart';
import 'package:obfuscateflutter/img_change_md5.dart';
import 'package:obfuscateflutter/reame_libs_dir_names.dart';
import 'package:obfuscateflutter/rename_files_name.dart';
import 'package:yaml/yaml.dart';

void main(List<String> arguments) async {
  print('Hello, Creeper!');
  print(
      'brfore you start this project change all relative import to start with package import!');

  String projectPath = '';
  var argPath = getArgsPath(arguments);
  if (argPath.isNotEmpty) {
    projectPath = argPath;
  } else {
    projectPath = await getCurrentPathByShell();
  }

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

  final yamlMap = loadYaml(pubFile.readAsStringSync());
  pubSpaceName = yamlMap['name'].toString();

  print('flutter project pubspec name is $pubSpaceName');

  _readTaskAndDo(project, pubSpaceName);
}

void _readTaskAndDo(Directory project, String pubSpaceName) {
  print(
      'please select task to run\n1.修改图片MD5\n2.生成Android Proguard混淆字典\n3.重命名lib下的目录名称\n4.重命名所有文件名\n5.打包ReleaseApk');
  print('输入要运行的任务：');
  var task = stdin.readLineSync();

  switch (task) {
    case "1":
      {
        print('change asserts images name');
        changeImageMd5(project.path);
        print('change asserts images name finished!!');
        break;
      }
    case "2":
      {
        sleep(Duration(seconds: 3));
        print("start gen android obfuscate dictory");
        genAndroidProguardDict(project.path);
        break;
      }
    case "3":
      {
        sleep(Duration(seconds: 3));
        print("start rename lib's child folders name and refresh code import");
        reNameAllDictorysAndRefresh(project, pubSpaceName);
        break;
      }
    case "4":
      {
        sleep(Duration(seconds: 3));
        print("start rename lib's child file name and refresh code import");
        renameAllFileNames(project);
        break;
      }
    case "5":
      {
        print("build apk start...");
        sleep(Duration(seconds: 3));
        buildReleaseApk(project.path);
        break;
      }
    default:
      {
        _readTaskAndDo(project, pubSpaceName);
      }
  }
}

Future<String> getCurrentPathByShell() async {
  final process = await Process.start(
    'chdir',
    [],
    runInShell: true,
  );
  print('out');
  var out = await process.stdout.transform(utf8.decoder).join();
  process.kill();

  return out.replaceAll('\n', '').trim();
}

String getArgsPath(List<String> arguments) {
  final parser = ArgParser()..addOption("dir", abbr: 'd');
  ArgResults argResults = parser.parse(arguments);
  return argResults["dir"].toString();
}
