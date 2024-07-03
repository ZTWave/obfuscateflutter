import 'dart:io';
import 'package:path/path.dart' as p;

class Log {
  static IOSink? _writer;

  static final String logFileName = 'log';
  static String _projectPath = '';

  static init(projectPath) {
    _projectPath = projectPath;
  }

  static log(String msg) {
    // _writer ??= _createLog(_projectPath)?.openWrite();
    // _writer?.writeln(msg);

    print(msg);
  }

  static File? _createLog(String logPath) {
    final String logFilePath =
        p.join(logPath, '${logFileName}_${DateTime.now().millisecond}.txt');
    try {
      final logFile = File(logFilePath);
      if (!logFile.existsSync()) {
        logFile.createSync();
      }
      return logFile;
    } catch (e) {
      print("create log file failed: $e");
      return null;
    }
  }

  static close() {
    _writer?.close();
  }
}
