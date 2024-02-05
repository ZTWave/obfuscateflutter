import 'dart:core';
import 'dart:io';

import 'package:args/args.dart';
import 'package:obfuscateflutter/build_apk.dart';
import 'package:obfuscateflutter/cmd_utils.dart';
import 'package:obfuscateflutter/gen_android_proguard_dicr.dart';
import 'package:obfuscateflutter/img_change_md5.dart';
import 'package:obfuscateflutter/reame_libs_dir_names.dart';
import 'package:obfuscateflutter/rename_files_name.dart';
import 'package:obfuscateflutter/temp_proj_utils.dart';
import 'package:path/path.dart' as p;
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
  if (projectPath.isEmpty == true) {
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

  var pubFile = File(p.join(project.path, "pubspec.yaml"));
  var pubSpaceName = '';

  final yamlMap = loadYaml(pubFile.readAsStringSync());
  pubSpaceName = yamlMap['name'].toString();

  print('flutter project pubspec name is $pubSpaceName');

  _readTaskAndDo(project.path, pubSpaceName);
}

void _readTaskAndDo(String projectPath, String pubSpaceName) {
  print(
      'please select task to run\n1.修改图片MD5\n2.生成Android Proguard混淆字典\n3.重命名lib下的目录名称\n4.重命名所有文件名\n5.打包ReleaseApk\n9.按顺序执行上述所有任务');
  print('输入要运行的任务：');
  var task = stdin.readLineSync();

  switch (task) {
    case "1":
      {
        _runChangeImageMd5(projectPath);
        break;
      }
    case "2":
      {
        _runGenAndroidProguardDict(projectPath);
        break;
      }
    case "3":
      {
        _runObfuscateAllLibsDirs(projectPath, pubSpaceName);
        break;
      }
    case "4":
      {
        _runObfuscateAllFileNames(projectPath);
        break;
      }
    case "5":
      {
        _runBuildReleaseArmV8Apk(projectPath);
        break;
      }
    case "9":
      {
        changeToTempDirAndRun(projectPath, pubSpaceName, (projectPathNew) {
          _runChangeImageMd5(projectPathNew);
          _runGenAndroidProguardDict(projectPathNew);
          _runObfuscateAllLibsDirs(projectPathNew, pubSpaceName);
          _runObfuscateAllFileNames(projectPathNew);
          return _runBuildReleaseArmV8Apk(projectPathNew);
        });
        break;
      }
    default:
      {
        _readTaskAndDo(projectPath, pubSpaceName);
      }
  }
}

_runChangeImageMd5(String projectPath) {
  print('change asserts images name');
  changeImageMd5(projectPath);
  print('change asserts images name finished!!');
}

_runGenAndroidProguardDict(String projectPath) {
  sleep(Duration(seconds: 3));
  print("start gen android obfuscate dictory");
  genAndroidProguardDict(projectPath);
}

_runObfuscateAllLibsDirs(String projectPath, String pubSpaceName) {
  sleep(Duration(seconds: 3));
  print("start rename lib's child folders name and refresh code import");
  reNameAllDictorysAndRefresh(projectPath, pubSpaceName);
}

_runObfuscateAllFileNames(String projectPath) {
  sleep(Duration(seconds: 3));
  print("start rename lib's child file name and refresh code import");
  renameAllFileNames(projectPath);
}

Future<String> _runBuildReleaseArmV8Apk(String projectPath) async {
  print("build apk start...");
  sleep(Duration(seconds: 3));
  return await buildReleaseApk(projectPath);
}

String getArgsPath(List<String> arguments) {
  final parser = ArgParser()..addOption("dir", abbr: 'd');
  ArgResults argResults = parser.parse(arguments);
  return argResults["dir"].toString();
}
