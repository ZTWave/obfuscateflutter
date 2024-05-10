import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<String> buildReleaseAab(String path) async {
  // 控制台打印项目目录
  print('项目目录：$path 开始编译 AAB\n');

  final process = await Process.start(
    'flutter',
    [
      'build',
      'appbundle',
      //'--verbose',
      '--obfuscate',
      '--split-debug-info=./ob_trace',
    ],
    runInShell: true,
    workingDirectory: path,
    mode: ProcessStartMode.inheritStdio,
  );
  final buildResult = await process.exitCode;
  if (buildResult != 0) {
    stdout.write('打包失败，请查看日志');
    return '';
  }
  process.kill();

  //开始重命名
  final file = File(p.join(path, "pubspec.yaml"));
  final fileContent = file.readAsStringSync();
  final yamlMap = loadYaml(fileContent);

  //获取当前版本号
  final version = (yamlMap['version'].toString()).replaceAll(
    '+',
    '_',
  );
  final appName = yamlMap['name'].toString();

  // aab 的输出目录
  final apkDirectory =
      p.join(path, 'build', 'app', 'outputs', 'bundle', 'release');
  const buildAppName = 'app-release.aab';
  final timeStr = DateFormat('yyyyMMddHHmm').format(
    DateTime.now(),
  );

  final resultNameList = [
    appName,
    version,
    timeStr,
  ].where((element) => element.isNotEmpty).toList();

  final resultAppName = '${resultNameList.join('_')}.aab';
  final appPath = p.join(apkDirectory, resultAppName);

  //重命名apk文件
  final apkFile = File(p.join(apkDirectory, buildAppName));
  await apkFile.rename(appPath);
  stdout.write('aab 打包成功 >>>>> $appPath \n');

  return appPath;
}
