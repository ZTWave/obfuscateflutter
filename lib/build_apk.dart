import 'dart:io';

import 'package:intl/intl.dart';
import 'package:yaml/yaml.dart';

void buildReleaseApk(String path) async {
  // 控制台打印项目目录
  print('项目目录：$path 开始编译\n');

  final process = await Process.start(
    'flutter',
    [
      'build',
      'apk',
      '--verbose',
      '--obfuscate',
      '--split-debug-info=./ob_trace',
      '--split-per-abi'
    ],
    runInShell: true,
    workingDirectory: path,
    mode: ProcessStartMode.inheritStdio,
  );
  final buildResult = await process.exitCode;
  if (buildResult != 0) {
    stdout.write('打包失败，请查看日志');
    return;
  }
  process.kill();

  //开始重命名
  final file = File('$path/pubspec.yaml');
  final fileContent = file.readAsStringSync();
  final yamlMap = loadYaml(fileContent);

  //获取当前版本号
  final version = (yamlMap['version'].toString()).replaceAll(
    '+',
    '_',
  );
  final appName = yamlMap['name'].toString();

  // apk 的输出目录
  final apkDirectory = '$path/build/app/outputs/flutter-apk/';
  const buildAppName = 'app-arm64-v8a-release.apk';
  final timeStr = DateFormat('yyyyMMddHHmm').format(
    DateTime.now(),
  );

  final resultNameList = [
    appName,
    version,
    timeStr,
  ].where((element) => element.isNotEmpty).toList();

  final resultAppName = '${resultNameList.join('_')}.apk';
  final appPath = apkDirectory + resultAppName;

  //重命名apk文件
  final apkFile = File(apkDirectory + buildAppName);
  await apkFile.rename(appPath);
  stdout.write('apk 打包成功 >>>>> $appPath \n');
}
