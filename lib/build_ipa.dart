import 'dart:io';

import 'package:intl/intl.dart';
import 'package:obfuscateflutter/consts.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

Future<String> buildIPA(String path, bool isDev, String dartDefineArg) async {
  // 控制台打印项目目录
  print('项目目录：$path 开始编译 IPA isDev -> $isDev \n');

  //flutter build ipa --release --export-method development
  List<String> args = [
    'build',
    'ipa',
    '--release',
  ];
  if (isDev) {
    args += ['--export-method', 'development'];
  } else {
    args += [
      '--obfuscate',
      '--split-debug-info=./ob_trace/',
    ];
  }
  if (dartDefineArg.isNotEmpty) {
    args += ['--dart-define-from-file=$dartDefineArg'];
  }

  print('build args -> $args');

  final process = await Process.start(
    'flutter',
    args,
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

  // ipa 的输出目录
  final ipaDirectory = p.join(path, 'build', 'ios', 'ipa');

  Directory directory = Directory(ipaDirectory);
  List<FileSystemEntity> dirList = directory.listSync(recursive: true);
  late File buildAppFile;
  dirList.forEach((element) {
    if (element is File && getFileExtName(element) == '.ipa') {
      buildAppFile = element;
    }
  });
  final timeStr = DateFormat('yyyyMMddHHmm').format(
    DateTime.now(),
  );

  final resultNameList = [
    appName,
    version,
    isDev ? 'dev' : 'dis',
    timeStr,
  ].where((element) => element.isNotEmpty).toList();

  final resultAppName = '${resultNameList.join('_')}.ipa';
  final appPath = p.join(ipaDirectory, resultAppName);

  //重命名ipa文件
  final appFile = File(buildAppFile.path);
  await appFile.rename(appPath);
  stdout.write('isDev ->$isDev ipa 打包成功 >>>>> $appPath \n');

  return appPath;
}
