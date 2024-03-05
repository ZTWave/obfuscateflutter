import 'dart:async';
import 'dart:io';
import 'package:obfuscateflutter/cmd_utils.dart';
import 'package:path/path.dart' as p;

changeToTempDirAndRun(String baseProject, String pubSpaceName,
    Future<String> Function(String projectPath) launcher) async {
  await flutterClean(baseProject);
  String tempDirName = "temp_$pubSpaceName";

  Directory baseProDir = Directory(baseProject);

  if (!baseProDir.existsSync()) {
    print("!!! base flutter project $baseProject isn't exit!!!");
    return;
  }

  var tempPath = p.join(baseProDir.parent.path, tempDirName);

  Directory temp = Directory(tempPath);
  if (temp.existsSync()) {
    temp.deleteSync(recursive: true);
  }
  sleep(Duration(microseconds: 10));
  temp.createSync();

  print("temp ${temp.path} created!");
  print("statrt copy project to temp path...");

  await copy(baseProject, tempPath);

  String newProjectPath = tempPath;

  String apkPath = await launcher(newProjectPath);

  File apkFile = File(apkPath);
  if (apkPath.isEmpty || !apkFile.existsSync()) {
    print("build apk failed!!");
    return;
  }

  String apkName = apkFile.path.split(p.separator).last;

  String outputPath = p.join(baseProject, 'apk_output');

  print("apkfile -> ${apkFile.path}");
  print("outpath -> $outputPath");

  sleep(Duration(seconds: 1));

  Directory outputDir = Directory(outputPath);
  if (!outputDir.existsSync()) {
    outputDir.createSync();
  }

  await copy(apkFile.path, outputPath);

  print("转移生成的apk至 ${p.join(outputPath, apkName)}");

  print("是否删除临时生成目录? 输入Y进行删除");
  var isDelete = stdin.readLineSync();
  if (isDelete == "Y") {
    temp.deleteSync(recursive: true);
    print('delete temp dic done');
  }
  print("finished!!!");
}
