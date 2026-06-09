import 'dart:io';

import 'package:obfuscateflutter/consts.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:obfuscateflutter/yaml_helper.dart';
import 'package:path/path.dart' as p;

Future<void> proguardImages(String projectPath) async {
  List<ImageProguardData> imageMapper = List.empty(growable: true);

  final assetEntries = YamlHelper.getAssetsDir(projectPath);

  // Collect all asset entities and pre-compute entry metadata in one pass.
  // This avoids repeated FileSystemEntity.typeSync calls later.
  final collection = _collectAssetCollection(projectPath, assetEntries);

  List<File> images = List.empty(growable: true);
  final seenImagePaths = <String>{};
  for (var element in collection.entities) {
    if (element is File) {
      if (imagesExtNames.contains(getFileExtName(element))) {
        if (seenImagePaths.add(element.path)) {
          images.add(element);
        }
      }
    }
  }

  List<String> proguardKeys = genRandomKeys(images.length).toList();
  for (int j = 0; j < images.length; j++) {
    var element = images[j];
    imageMapper.add(ImageProguardData(element.path.split(p.separator).last,
        proguardKeys[j] + getFileExtName(element), getFileDirPath(element)));
  }

  final replacements = _buildImageReplacements(
    imageMapper,
    projectPath,
    collection.entryInfos,
  );

  Directory libDir = Directory(p.join(projectPath, "lib"));
  final List<FileSystemEntity> entities =
      libDir.listSync(recursive: true).toList();

  List<File> allFiles = entities
      .where((value) => value is File && getFileExtName(value) == ".dart")
      .cast<File>()
      .toList();

  // Process Dart files concurrently in batches to maximize I/O throughput.
  final concurrency = Platform.numberOfProcessors.clamp(4, 16);
  for (int i = 0; i < allFiles.length; i += concurrency) {
    final batch = allFiles.sublist(
      i,
      (i + concurrency).clamp(0, allFiles.length),
    );
    await Future.wait(batch.map((element) async {
      final codeStr = await element.readAsString();
      final modifiedCodeStr =
          codeStr.replaceAllMapped(_simpleStringLiteralPattern, (match) {
        final quote = match.group(1)!;
        final value = match.group(2)!;
        final replacement = replacements[value];
        if (replacement == null) {
          return match.group(0)!;
        }
        replacement.image.used = true;
        return '$quote${replacement.value}$quote';
      });
      if (modifiedCodeStr != codeStr) {
        await element.writeAsString(
          modifiedCodeStr,
          flush: true,
          mode: FileMode.write,
        );
      }
    }));
  }

  _updatePubspecAssets(projectPath, imageMapper);

  for (int i = 0; i < imageMapper.length; i++) {
    var element = imageMapper[i];
    print('image file => $element');
    File file = File(p.join(element.path, element.originalName));
    if (!element.used) {
      file.deleteSync();
    } else {
      file.renameSync(p.join(element.path, element.proguardName));
    }
  }

  _printMapping(imageMapper);
}

final RegExp _simpleStringLiteralPattern = RegExp(r'''(['"])([^'"\r\n]*)\1''');

// ---------------------------------------------------------------------------
// Pre-computed asset entry metadata.
// The type-sync is done once per entry during collection and reused across
// all image→replacement mappings.
// ---------------------------------------------------------------------------
class _AssetEntryInfo {
  final String entryUri; // original pubspec asset URI, e.g. "assets/images"
  final bool exists;
  final bool isFile;
  final bool isDirectory;
  final String resolvedPath; // normalized absolute path

  _AssetEntryInfo({
    required this.entryUri,
    required this.exists,
    required this.isFile,
    required this.isDirectory,
    required this.resolvedPath,
  });
}

class _AssetCollection {
  final List<FileSystemEntity> entities;
  final List<_AssetEntryInfo> entryInfos;

  _AssetCollection(this.entities, this.entryInfos);
}

/// Single-pass collection: lists all filesystem entities AND pre-computes
/// per-entry type metadata so later steps never call typeSync again.
_AssetCollection _collectAssetCollection(
  String projectPath,
  List<String> assetEntries,
) {
  final entities = <FileSystemEntity>[];
  final infos = <_AssetEntryInfo>[];
  final seenPaths = <String>{};

  for (final String assetEntry in assetEntries) {
    final String entityPath = p.normalize(p.join(projectPath, assetEntry));

    // typeSync is called exactly once per asset entry.
    final FileSystemEntityType type;
    try {
      type = FileSystemEntity.typeSync(entityPath);
    } on FileSystemException {
      infos.add(_AssetEntryInfo(
        entryUri: assetEntry,
        exists: false,
        isFile: false,
        isDirectory: false,
        resolvedPath: entityPath,
      ));
      print('asset path not found, skip: $assetEntry');
      continue;
    }

    final isFile = type == FileSystemEntityType.file;
    final isDir = type == FileSystemEntityType.directory;

    infos.add(_AssetEntryInfo(
      entryUri: assetEntry,
      exists: true,
      isFile: isFile,
      isDirectory: isDir,
      resolvedPath: entityPath,
    ));

    if (isFile) {
      if (seenPaths.add(entityPath)) {
        entities.add(File(entityPath));
      }
    } else if (isDir) {
      for (final entity in Directory(entityPath).listSync(recursive: true)) {
        if (seenPaths.add(entity.path)) {
          entities.add(entity);
        }
      }
    } else {
      print('asset path not found, skip: $assetEntry');
    }
  }

  return _AssetCollection(entities, infos);
}

Map<String, _ImageReplacement> _buildImageReplacements(
  List<ImageProguardData> imageMapper,
  String projectPath,
  List<_AssetEntryInfo> entryInfos,
) {
  final replacements = <String, _ImageReplacement>{};

  for (final imageItem in imageMapper) {
    replacements.putIfAbsent(
      imageItem.originalName,
      () => _ImageReplacement(imageItem.proguardName, imageItem),
    );

    final posableUsage = _getPathFromAsserts(
      imageItem.path,
      projectPath,
      entryInfos,
    );

    for (final usage in posableUsage) {
      replacements['$usage/${imageItem.originalName}'] =
          _ImageReplacement('$usage/${imageItem.proguardName}', imageItem);
    }
  }

  return replacements;
}

void _printMapping(List<ImageProguardData> imageMapper) {
  for (var element in imageMapper) {
    if (element.used) {
      print("rename image ${element.originalName} to ${element.proguardName}");
    } else {
      print("remove image ${element.originalName}");
    }
  }
}

// imgParentPath is absolute. Uses pre-computed entryInfos (no typeSync calls).
List<String> _getPathFromAsserts(
  String imgParentPath,
  String projectPath,
  List<_AssetEntryInfo> entryInfos,
) {
  final posableImageUsages = <String>[];
  final projectRelativeParent = _toAssetUri(
    p.relative(imgParentPath, from: projectPath),
  );
  if (projectRelativeParent != '.' && projectRelativeParent.isNotEmpty) {
    posableImageUsages.add(projectRelativeParent);
  }

  for (final info in entryInfos) {
    if (!info.exists) continue;

    if (info.isFile &&
        p.equals(p.dirname(info.resolvedPath), imgParentPath)) {
      posableImageUsages.add(_toAssetUri(p.dirname(info.entryUri)));
    } else if (info.isDirectory &&
        p.isWithin(info.resolvedPath, imgParentPath)) {
      posableImageUsages.add(projectRelativeParent);
    }
  }

  return posableImageUsages
      .where((usage) => usage.isNotEmpty && usage != '.')
      .toSet()
      .toList();
}

String _toAssetUri(String value) {
  return p
      .normalize(value)
      .split(p.separator)
      .where((segment) => segment.isNotEmpty && segment != '.')
      .join('/');
}

void _updatePubspecAssets(
  String projectPath,
  List<ImageProguardData> imageMapper,
) {
  final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) return;

  var content = pubspecFile.readAsStringSync();
  for (final imageItem in imageMapper) {
    final oldAssetUri =
        _imageAssetUri(projectPath, imageItem.path, imageItem.originalName);
    final newAssetUri =
        _imageAssetUri(projectPath, imageItem.path, imageItem.proguardName);

    if (imageItem.used) {
      content = content.replaceAll(oldAssetUri, newAssetUri);
    } else {
      content = _removeAssetEntryLine(content, oldAssetUri);
    }
  }

  pubspecFile.writeAsStringSync(content, flush: true, mode: FileMode.write);
}

String _imageAssetUri(
    String projectPath, String imageDirPath, String fileName) {
  return _toAssetUri(
    p.relative(
      p.join(imageDirPath, fileName),
      from: projectPath,
    ),
  );
}

String _removeAssetEntryLine(String content, String assetUri) {
  final escaped = RegExp.escape(assetUri);
  final patternSource =
      '^[ \\t]*-[ \\t]*(?:$escaped|"$escaped"|\'$escaped\')[ \\t]*(?:#.*)?(?:\\r?\\n|\$)';
  final pattern = RegExp(
    patternSource,
    multiLine: true,
  );
  return content.replaceAll(pattern, '');
}

class ImageProguardData {
  String originalName;
  String proguardName;
  String path;
  bool used = false;

  ImageProguardData(this.originalName, this.proguardName, this.path);

  @override
  String toString() {
    return "ImageProguardData originalName->$originalName proguardName->$proguardName path->$path used->$used";
  }
}

class _ImageReplacement {
  final String value;
  final ImageProguardData image;

  _ImageReplacement(this.value, this.image);
}
