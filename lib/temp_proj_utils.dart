import 'dart:async';
import 'dart:io';
import 'package:obfuscateflutter/cmd_utils.dart';
import 'package:path/path.dart' as p;

changeToTempDirAndRun(String baseProject, String pubSpaceName,
    Future<void> Function(String projectPath) launcher) async {
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

  await launcher(newProjectPath);
}

transOutputTo(String baseProjectPath, String tempProjectPath,
    String outputFilePath) async {
  File appFile = File(outputFilePath);
  if (outputFilePath.isEmpty || !appFile.existsSync()) {
    print("build output failed!!");
    return;
  }

  String apkName = appFile.path.split(p.separator).last;

  String outputPath = p.join(baseProjectPath, 'output');

  print("app file -> ${appFile.path}");
  print("outpath -> $outputPath");

  sleep(Duration(seconds: 1));

  Directory outputDir = Directory(outputPath);
  if (!outputDir.existsSync()) {
    outputDir.createSync();
  }

  await copy(appFile.path, outputPath);

  print("转移生成的产物至 ${p.join(outputPath, apkName)}");
}

deleteTempProject(String tempProjectPath) async {
  Directory temp = Directory(tempProjectPath);

  print("是否删除临时生成目录? 输入Y/y进行删除,其他跳过");
  var isDelete = stdin.readLineSync();
  if (["Y", "y"].contains(isDelete)) {
    temp.deleteSync(recursive: true);
    print('delete temp dic done');
  }
  print("finished!!!");
}
