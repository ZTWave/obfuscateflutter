import 'dart:convert';
import 'dart:io';

flutterClean(String projectPath) async {
  print("run flutter clean");
  final process = await Process.start(
    'flutter',
    ['clean'],
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
    workingDirectory: projectPath,
  );
  final result = await process.exitCode;
  if (result != 0) {
    stdout.write('flutter clean failed!');
    return;
  }
  process.kill();
  print("run flutter clean finish.");
}

flutterPubGet(String projectPath) async {
  print("run flutter pub get");
  final process = await Process.start('flutter pub get', [],
      mode: ProcessStartMode.inheritStdio,
      runInShell: true,
      workingDirectory: projectPath);
  final result = await process.exitCode;
  if (result != 0) {
    stdout.write('flutter pub get failed!');
    return;
  }
  process.kill();
  print("run flutter pub get clean finished.");
}

copy(String oldPath, String newPath) async {
  print("run cmd copy from $oldPath to $newPath");

  String cmd;
  String arg;
  if (Platform.isWindows) {
    cmd = 'xcopy';
    arg = '/S';
  } else {
    cmd = 'cp';
    arg = '-r';
  }

  final process = await Process.start(
    cmd,
    [oldPath, newPath, arg],
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  final result = await process.exitCode;
  if (result != 0) {
    stdout.write('cmd copy failed!');
    return;
  }
  process.kill();
  print("cmd copy finished.");
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
