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

  await copyProjectToTemp(baseProject, tempPath);

  String newProjectPath = tempPath;

  await launcher(newProjectPath);
}

Future<void> copyProjectToTemp(String baseProject, String tempPath) async {
  print("run project copy from $baseProject to $tempPath");
  final source = Directory(baseProject);
  final target = Directory(tempPath);
  if (!source.existsSync()) {
    throw StateError('Source project does not exist: $baseProject');
  }
  if (!target.existsSync()) {
    target.createSync(recursive: true);
  }

  for (final entity in source.listSync(followLinks: false)) {
    await _copyEntityToTemp(
        entity, p.join(target.path, p.basename(entity.path)));
  }
  print("project copy finished.");
}

Future<void> _copyEntityToTemp(
    FileSystemEntity entity, String targetPath) async {
  if (p.basename(entity.path) == '.git') {
    return;
  }

  if (entity is Directory) {
    final targetDir = Directory(targetPath);
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    for (final child in entity.listSync(followLinks: false)) {
      await _copyEntityToTemp(
          child, p.join(targetDir.path, p.basename(child.path)));
    }
    return;
  }

  if (entity is File) {
    final parent = Directory(p.dirname(targetPath));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    await entity.copy(targetPath);
    return;
  }

  if (entity is Link) {
    final parent = Directory(p.dirname(targetPath));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    await Link(targetPath).create(entity.targetSync());
  }
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
