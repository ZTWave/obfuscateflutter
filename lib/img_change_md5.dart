import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:obfuscateflutter/consts.dart';
import 'package:obfuscateflutter/random_key.dart';
import 'package:obfuscateflutter/yaml_helper.dart';
import 'package:path/path.dart' as p;

void changeImageMd5(String path) {
  final rand = Random(DateTime.now().millisecondsSinceEpoch);

  final fileEles = <FileSystemEntity>[];
  for (final asset in YamlHelper.getAssetsDir(path)) {
    fileEles.addAll(_resolveAssetEntities(path, asset));
  }

  List<File> images = fileEles
      .whereType<File>()
      .where((e) => imagesExtNames.contains(getFileExtName(e)))
      .toList();

  for (var imgFile in images) {
    _printMd5(imgFile, prefixStr: "before");
    _adjustPixels(imgFile, rand);
    _printMd5(imgFile, prefixStr: "after");
  }
}

List<FileSystemEntity> _resolveAssetEntities(String projectPath, String asset) {
  final assetPath = p.join(projectPath, asset);
  final type = FileSystemEntity.typeSync(assetPath, followLinks: false);
  if (type == FileSystemEntityType.file) {
    return [File(assetPath)];
  }
  if (type == FileSystemEntityType.directory) {
    return Directory(assetPath).listSync(recursive: true, followLinks: false);
  }
  print('asset path not found, skip: $asset');
  return [];
}

/// Apply subtle pixel adjustments + inject fake EXIF metadata.
/// Pixel changes are invisible to the eye but defeat perceptual hashing.
/// Fake EXIF diversifies the metadata fingerprint.
void _adjustPixels(File file, Random rand) {
  final ext = getFileExtName(file).toLowerCase();
  final bytes = file.readAsBytesSync();

  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object catch (e) {
    print(
        'decode image failed, append random bytes instead: ${file.path} ($e)');
    _appendRandomBytes(file, rand);
    return;
  }
  if (decoded == null) {
    _appendRandomBytes(file, rand);
    return;
  }

  // --- Pixel-level adjustments ---
  final brightness = (rand.nextDouble() - 0.5) * 3; // [-1.5, 1.5]
  final contrast = 0.995 + rand.nextDouble() * 0.010; // [0.995, 1.005]
  final noiseSeed = rand.nextInt(1 << 30);
  final noiseLevel = rand.nextInt(2);

  for (int y = 0; y < decoded.height; y++) {
    for (int x = 0; x < decoded.width; x++) {
      final px = decoded.getPixel(x, y);

      int r = px.r.toInt();
      int g = px.g.toInt();
      int b = px.b.toInt();

      r = (r + brightness).round().clamp(0, 255);
      g = (g + brightness).round().clamp(0, 255);
      b = (b + brightness).round().clamp(0, 255);

      r = (((r - 128) * contrast) + 128).round().clamp(0, 255);
      g = (((g - 128) * contrast) + 128).round().clamp(0, 255);
      b = (((b - 128) * contrast) + 128).round().clamp(0, 255);

      if (noiseLevel > 0) {
        r = (r + _noiseAt(x, y, noiseSeed)).clamp(0, 255);
        g = (g + _noiseAt(x, y, noiseSeed + 1)).clamp(0, 255);
        b = (b + _noiseAt(x, y, noiseSeed + 2)).clamp(0, 255);
      }

      decoded.setPixelRgba(x, y, r, g, b, px.a);
    }
  }

  // --- Re-encode ---
  List<int>? encoded;
  switch (ext) {
    case '.png':
      encoded = img.PngEncoder(level: 6).encode(decoded);
      break;
    case '.jpg':
    case '.jpeg':
      encoded = img.JpegEncoder(quality: 92).encode(decoded);
      break;
    case '.webp':
      break;
  }

  if (encoded != null) {
    file.writeAsBytesSync(encoded);
  } else {
    _appendRandomBytes(file, rand);
  }
}

// 一个纯数学的整数哈希，输入 (x, y, seed) 三个整数，输出一个伪随机但确定的值。这样：

//   - 零 Random 调用 — 纯整数运算，每像素只是几次乘法和位操作
//   - 确定性 — 相同的 (x, y, seed) 总是产生相同结果，这对可复现性有好处（虽然当前每次重新生成 seed，但逻辑上是确定性的）
//   - 视觉上像随机噪声 — 相邻像素的输出值没有明显规律，人眼看不出模式
//   三个乘数是随意选取的大质数（类似 LCG 的参数选择思路）：
//   - 374761393 — 质数
//   - 668265263 — 质数
//   - 1274126177 — 质数
//   & 0x7FFFFFFF 取低 31 位（去掉符号位），% 3 映射到 {0, 1, 2}，- 1 映射到 {-1, 0, 1}。每个通道使用不同的 seed 偏移（noiseSeed, noiseSeed + 1, noiseSeed +
//   2），确保三个通道的噪声彼此独立。
int _noiseAt(int x, int y, int seed) {
  final h = ((x * 374761393 + y * 668265263 + seed * 1274126177) & 0x7FFFFFFF);
  return (h % 3) - 1;
}

void _appendRandomBytes(File file, Random rand) {
  var content = file.readAsBytesSync().toList(growable: true);
  var endRandomStr = genRandomKey(rand.nextInt(2) + 1);
  content.addAll(endRandomStr.codeUnits);
  file.writeAsBytesSync(content);
}

void _printMd5(File file, {String prefixStr = ""}) {
  var bytes = file.readAsBytesSync();
  var md5Str = md5.convert(bytes).toString();
  print("$prefixStr -> $md5Str");
}
