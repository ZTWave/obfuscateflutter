import 'dart:convert';
import 'dart:io';

class ObfuscationMapping {
  final String projectName;
  final String createdAt;
  final Map<String, String> fileRenames; // original basename → obfuscated basename
  final List<ProcessedFileEntry> processedFiles;
  final String? keyStoreFile;
  final String? sep;
  final int? sek;
  final Map<String, String> directoryRenames; // original → obfuscated

  ObfuscationMapping({
    required this.projectName,
    required this.createdAt,
    this.fileRenames = const {},
    this.processedFiles = const [],
    this.keyStoreFile,
    this.sep,
    this.sek,
    this.directoryRenames = const {},
  });

  Map<String, dynamic> toJson() => {
        'version': '1.0',
        'created_at': createdAt,
        'project_name': projectName,
        if (fileRenames.isNotEmpty) 'file_renames': fileRenames,
        if (directoryRenames.isNotEmpty) 'directory_renames': directoryRenames,
        if (keyStoreFile != null)
          'string_encryption': {
            'key_store_file': keyStoreFile,
            'sep': sep,
            'sek': sek,
          },
        'processed_files': processedFiles.map((f) => f.toJson()).toList(),
        'summary': _buildSummary(),
      };

  Map<String, dynamic> _buildSummary() {
    var totalStrings = 0;
    var totalImports = 0;
    for (final f in processedFiles) {
      totalStrings += f.stringsEncrypted;
      totalImports += f.importsRewritten;
    }
    return {
      'total_files_processed': processedFiles.length,
      'total_files_renamed': fileRenames.length,
      'total_dirs_renamed': directoryRenames.length,
      'total_strings_encrypted': totalStrings,
      'total_imports_rewritten': totalImports,
    };
  }

  void writeToFile(String outputPath) {
    final encoder = JsonEncoder.withIndent('  ');
    File(outputPath).writeAsStringSync(encoder.convert(toJson()));
  }
}

class ProcessedFileEntry {
  final String path;
  final int stringsEncrypted;
  final int importsRewritten;

  ProcessedFileEntry({
    required this.path,
    this.stringsEncrypted = 0,
    this.importsRewritten = 0,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'strings_encrypted': stringsEncrypted,
        'imports_rewritten': importsRewritten,
      };
}

class MappingBuilder {
  final String projectName;
  final String createdAt;
  final Map<String, String> _fileRenames = {};
  final Map<String, String> _directoryRenames = {};
  final List<ProcessedFileEntry> _processedFiles = [];
  String? _keyStoreFile;
  String? _sep;
  int? _sek;

  MappingBuilder(this.projectName) : createdAt = DateTime.now().toIso8601String();

  void addFileRename(String original, String obfuscated) {
    _fileRenames[original] = obfuscated;
  }

  void addDirectoryRename(String original, String obfuscated) {
    _directoryRenames[original] = obfuscated;
  }

  void addProcessedFile(String path, int stringsEncrypted, int importsRewritten) {
    _processedFiles.add(ProcessedFileEntry(
      path: path,
      stringsEncrypted: stringsEncrypted,
      importsRewritten: importsRewritten,
    ));
  }

  void setStringEncryption(String keyStoreFile, String sep, int sek) {
    _keyStoreFile = keyStoreFile;
    _sep = sep;
    _sek = sek;
  }

  ObfuscationMapping build() {
    // Sort processed files alphabetically for consistent output
    _processedFiles.sort((a, b) => a.path.compareTo(b.path));
    return ObfuscationMapping(
      projectName: projectName,
      createdAt: createdAt,
      fileRenames: Map.unmodifiable(_fileRenames),
      directoryRenames: Map.unmodifiable(_directoryRenames),
      processedFiles: List.unmodifiable(_processedFiles),
      keyStoreFile: _keyStoreFile,
      sep: _sep,
      sek: _sek,
    );
  }
}
