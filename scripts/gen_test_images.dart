import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  final rand = Random(42);
  final outputDir = Directory('../obfuscate_test/assets/images');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  for (int i = 0; i < 50; i++) {
    final width = 40 + rand.nextInt(200);
    final height = 40 + rand.nextInt(200);
    final image = img.Image(width: width, height: height);

    final style = rand.nextInt(5); // 0-4 different visual styles
    switch (style) {
      case 0:
        _fillSolid(image, rand);
        break;
      case 1:
        _fillGradient(image, rand);
        break;
      case 2:
        _fillChecker(image, rand);
        break;
      case 3:
        _fillCircles(image, rand);
        break;
      case 4:
        _fillStripes(image, rand);
        break;
    }

    // Add some noise for extra randomness
    _addNoise(image, rand);

    final bytes = img.PngEncoder(level: rand.nextInt(10)).encode(image);
    final name = 'img_${i.toString().padLeft(3, '0')}.png';
    File(p.join(outputDir.path, name)).writeAsBytesSync(bytes);
    print('Generated $name (${width}x$height) style=$style');
  }

  print('\nDone. 50 images created in ${outputDir.path}');
}

void _fillSolid(img.Image image, Random rand) {
  final color = _randomColor(rand);
  img.fill(image, color: color);
}

void _fillGradient(img.Image image, Random rand) {
  final c1 = _randomColor(rand);
  final c2 = _randomColor(rand);
  for (int y = 0; y < image.height; y++) {
    final t = y / image.height;
    final r = (c1.r * (1 - t) + c2.r * t).toInt();
    final g = (c1.g * (1 - t) + c2.g * t).toInt();
    final b = (c1.b * (1 - t) + c2.b * t).toInt();
    for (int x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

void _fillChecker(img.Image image, Random rand) {
  final c1 = _randomColor(rand);
  final c2 = _randomColor(rand);
  final size = 4 + rand.nextInt(20);
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final on = ((x ~/ size) + (y ~/ size)) % 2 == 0;
      final c = on ? c1 : c2;
      image.setPixelRgba(x, y, c.r, c.g, c.b, 255);
    }
  }
}

void _fillCircles(img.Image image, Random rand) {
  final bg = _randomColor(rand);
  img.fill(image, color: bg);
  final count = 1 + rand.nextInt(5);
  for (int k = 0; k < count; k++) {
    final cx = rand.nextInt(image.width);
    final cy = rand.nextInt(image.height);
    final r = 5 + rand.nextInt(min(image.width, image.height) ~/ 3);
    final color = _randomColor(rand);
    img.fillCircle(image, x: cx, y: cy, radius: r, color: color);
  }
}

void _fillStripes(img.Image image, Random rand) {
  final bg = _randomColor(rand);
  img.fill(image, color: bg);
  final c = _randomColor(rand);
  final thick = 3 + rand.nextInt(20);
  final vertical = rand.nextBool();
  for (int i = 0; i < (vertical ? image.width : image.height); i += thick * 2) {
    for (int j = 0; j < thick; j++) {
      final x = vertical ? i + j : 0;
      final y = vertical ? 0 : i + j;
      img.fillRect(image,
        x1: x,
        y1: y,
        x2: vertical ? x : image.width - 1,
        y2: vertical ? image.height - 1 : y,
        color: c);
    }
  }
}

void _addNoise(img.Image image, Random rand) {
  final count = (image.width * image.height * 0.02).toInt();
  for (int i = 0; i < count; i++) {
    final x = rand.nextInt(image.width);
    final y = rand.nextInt(image.height);
    final pixel = image.getPixel(x, y);
    final noise = rand.nextInt(30) - 15;
    image.setPixelRgba(
      x, y,
      (pixel.r + noise).clamp(0, 255),
      (pixel.g + noise).clamp(0, 255),
      (pixel.b + noise).clamp(0, 255),
      255,
    );
  }
}

img.ColorRgba8 _randomColor(Random rand) {
  return img.ColorRgba8(
    rand.nextInt(256),
    rand.nextInt(256),
    rand.nextInt(256),
    255,
  );
}
