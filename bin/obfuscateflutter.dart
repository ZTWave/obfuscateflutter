import 'dart:core';
import 'dart:io';

import 'package:args/args.dart';
import 'package:obfuscateflutter/build_aab.dart';
import 'package:obfuscateflutter/build_apk.dart';
import 'package:obfuscateflutter/build_ipa.dart';
import 'package:obfuscateflutter/cmd_utils.dart';
import 'package:obfuscateflutter/gen_android_proguard_dicr.dart';
import 'package:obfuscateflutter/img_change_md5.dart';
import 'package:obfuscateflutter/proguard_images.dart';
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
  print(r'''
  please select task to run
  1.修改图片MD5
  2.混淆图片名称并清理
  3.生成Android Proguard混淆字典
  4.重命名lib下的目录名称
  5.重命名所有文件名
  6.打包Android Apk
  7.打包Android AAB
  8.打包IOS IPA测试包

  x.在临时生成目录中进行执行上述混淆任务并打包''');
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
        _proguadImageNameAndClean(projectPath);
        break;
      }
    case "3":
      {
        _runGenAndroidProguardDict(projectPath);
        break;
      }
    case "4":
      {
        _runObfuscateAllLibsDirs(projectPath, pubSpaceName);
        break;
      }
    case "5":
      {
        _runObfuscateAllFileNames(projectPath);
        break;
      }
    case "6":
      {
        _runBuildApk(projectPath);
        break;
      }
    case "7":
      {
        _runBuildAab(projectPath);
        break;
      }
    case "8":
      {
        _runBuildIpa(projectPath, true);
        break;
      }
    case "x":
      {
        changeToTempDirAndRun(projectPath, pubSpaceName,
            (projectPathNew) async {
          _runChangeImageMd5(projectPathNew);
          _proguadImageNameAndClean(projectPathNew);
          _runGenAndroidProguardDict(projectPathNew);
          _runObfuscateAllLibsDirs(projectPathNew, pubSpaceName);
          _runObfuscateAllFileNames(projectPathNew);
          print('!!!混淆任务已经完成!!!');
          List<bool> tasks = await _askWhichToBuild();
          await _runBuild(projectPath, projectPathNew, tasks[0], tasks[1],
              tasks[2], tasks[3]);
          deleteTempProject(projectPathNew);
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

void _proguadImageNameAndClean(String projectPath) {
  print('proguard images name and clean');
  sleep(Duration(seconds: 3));
  proguardImages(projectPath);
  print('proguard images name and clean!!');
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

Future<List<bool>> _askWhichToBuild() async {
  print(
      '\n输入想要打包类型( 1->apk 2->aab 3->ipaDev 4->ipaDis )\nwindows只支持APK!,支持打多个包,(例如:12,将打包apk和aab)');
  String tasks = stdin.readLineSync() ?? '';
  if (Platform.isMacOS) {
    print(
        "will build apk -> ${tasks.contains('1')} will build aab -> ${tasks.contains('2')} ipadev -> ${tasks.contains('3')} iparelease -> ${tasks.contains('4')}");
    return [
      tasks.contains('1'),
      tasks.contains('2'),
      tasks.contains('3'),
      tasks.contains('4')
    ];
  }
  print("will build apk -> ${tasks.contains('1')}");
  sleep(Duration(seconds: 3));
  return [tasks.contains('1'), tasks.contains('2'), false, false];
}

_runBuild(String projectPath, String projectPathTemp, bool buildApk,
    bool buildAab, bool buildIpaDev, bool buildIpaRelease) async {
  if (buildApk) {
    String apkPath = await _runBuildApk(projectPathTemp);
    await transOutputTo(projectPath, projectPathTemp, apkPath);
  }
  if (buildAab) {
    String aabPath = await _runBuildAab(projectPathTemp);
    await transOutputTo(projectPath, projectPathTemp, aabPath);
  }
  if (buildIpaDev) {
    String ipaPath = await _runBuildIpa(projectPathTemp, true);
    await transOutputTo(projectPath, projectPathTemp, ipaPath);
  }
  if (buildIpaRelease) {
    String ipaPath = await _runBuildIpa(projectPathTemp, false);
    await transOutputTo(projectPath, projectPathTemp, ipaPath);
  }
}

Future<String> _runBuildApk(String projectPath) async {
  print("build apk start...");
  sleep(Duration(seconds: 3));
  return buildReleaseApk(projectPath);
}

Future<String> _runBuildAab(String projectPath) async {
  print("build aab start...");
  sleep(Duration(seconds: 3));
  return buildReleaseAab(projectPath);
}

Future<String> _runBuildIpa(String projectPath, bool isDev) async {
  print("build ipa ${isDev ? "dev" : "release"} start...");
  sleep(Duration(seconds: 3));
  return buildIPA(projectPath, isDev);
}

String getArgsPath(List<String> arguments) {
  final parser = ArgParser()..addOption("dir", abbr: 'd');
  ArgResults argResults = parser.parse(arguments);
  return argResults["dir"].toString();
}
