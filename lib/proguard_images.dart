import 'dart:io';

import 'package:obfuscateflutter/consts.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:obfuscateflutter/yaml_helper.dart';
import 'package:path/path.dart' as p;

void proguardImages(String projectPath) {
  List<ImageProguardData> imageMapper = List.empty(growable: true);

  final assetEntries = YamlHelper.getAssetsDir(projectPath);
  final fileEles = _collectAssetEntities(projectPath, assetEntries);

  List<File> images = List.empty(growable: true);
  final seenImagePaths = <String>{};
  for (var element in fileEles) {
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
    assetEntries,
  );

  Directory libDir = Directory(p.join(projectPath, "lib"));
  final List<FileSystemEntity> entities =
      libDir.listSync(recursive: true).toList();

  List<FileSystemEntity> allFiles = entities
      .where((value) => value is File && getFileExtName(value) == ".dart")
      .toList();

  for (final element in allFiles) {
    if (element is! File) {
      continue;
    }

    final codeStr = element.readAsStringSync();
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
      element.writeAsStringSync(
        modifiedCodeStr,
        flush: true,
        mode: FileMode.write,
      );
    }
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

Map<String, _ImageReplacement> _buildImageReplacements(
  List<ImageProguardData> imageMapper,
  String projectPath,
  List<String> assetEntries,
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
      assetEntries,
    );

    for (final usage in posableUsage) {
      replacements['$usage/${imageItem.originalName}'] =
          _ImageReplacement('$usage/${imageItem.proguardName}', imageItem);
    }
  }

  return replacements;
}

List<FileSystemEntity> _collectAssetEntities(
  String projectPath,
  List<String> assetEntries,
) {
  final entities = <FileSystemEntity>[];
  final seenPaths = <String>{};

  for (final String assetEntry in assetEntries) {
    final String entityPath = p.normalize(p.join(projectPath, assetEntry));
    final FileSystemEntityType type = FileSystemEntity.typeSync(entityPath);

    if (type == FileSystemEntityType.file) {
      if (seenPaths.add(entityPath)) {
        entities.add(File(entityPath));
      }
      continue;
    }

    if (type == FileSystemEntityType.directory) {
      for (final entity in Directory(entityPath).listSync(recursive: true)) {
        if (seenPaths.add(entity.path)) {
          entities.add(entity);
        }
      }
      continue;
    }

    print('asset path not found, skip: $assetEntry');
  }

  return entities;
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

// imgParentPath is absolute. Returned paths use Flutter asset URI separators.
List<String> _getPathFromAsserts(
  String imgParentPath,
  String projectPath,
  List<String> assetEntries,
) {
  final posableImageUsages = <String>[];
  final projectRelativeParent = _toAssetUri(
    p.relative(imgParentPath, from: projectPath),
  );
  if (projectRelativeParent != '.' && projectRelativeParent.isNotEmpty) {
    posableImageUsages.add(projectRelativeParent);
  }

  for (final assetEntry in assetEntries) {
    final entryPath = p.normalize(p.join(projectPath, assetEntry));
    final entryType = FileSystemEntity.typeSync(entryPath);
    if (entryType == FileSystemEntityType.file &&
        p.equals(p.dirname(entryPath), imgParentPath)) {
      posableImageUsages.add(_toAssetUri(p.dirname(assetEntry)));
    } else if (entryType == FileSystemEntityType.directory &&
        p.isWithin(entryPath, imgParentPath)) {
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
