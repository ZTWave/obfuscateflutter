import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

int noiseAt(int x, int y, int seed) {
  final h = ((x * 374761393 + y * 668265263 + seed * 1274126177) & 0x7FFFFFFF);
  return (h % 3) - 1;
}

void main() {
  final rand = Random(42);
  final files = Directory('../obfuscate_test/assets/images')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.png'))
      .take(5)
      .toList();

  for (final file in files) {
    final original = file.readAsBytesSync();
    final decoded = img.decodeImage(original);
    if (decoded == null) continue;

    final brightness = (rand.nextDouble() - 0.5) * 4;
    final contrast = 0.99 + rand.nextDouble() * 0.02;
    final noiseSeed = rand.nextInt(1 << 30);
    final noiseLevel = rand.nextInt(2);

    final adjusted = img.Image.from(decoded);

    for (int y = 0; y < adjusted.height; y++) {
      for (int x = 0; x < adjusted.width; x++) {
        final px = adjusted.getPixel(x, y);
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
          r = (r + noiseAt(x, y, noiseSeed)).clamp(0, 255);
          g = (g + noiseAt(x, y, noiseSeed + 1)).clamp(0, 255);
          b = (b + noiseAt(x, y, noiseSeed + 2)).clamp(0, 255);
        }

        adjusted.setPixelRgba(x, y, r, g, b, px.a);
      }
    }

    // Stats
    double maxDr = 0, maxDg = 0, maxDb = 0;
    double sumDr = 0, sumDg = 0, sumDb = 0;
    var diffCount = 0;
    final n = decoded.width * decoded.height;

    for (int y = 0; y < decoded.height; y++) {
      for (int x = 0; x < decoded.width; x++) {
        final a = decoded.getPixel(x, y);
        final b = adjusted.getPixel(x, y);
        final dr = (a.r - b.r).abs().toDouble();
        final dg = (a.g - b.g).abs().toDouble();
        final db = (a.b - b.b).abs().toDouble();
        if (dr > maxDr) maxDr = dr;
        if (dg > maxDg) maxDg = dg;
        if (db > maxDb) maxDb = db;
        sumDr += dr;
        sumDg += dg;
        sumDb += db;
        if (dr > 0 || dg > 0 || db > 0) diffCount++;
      }
    }

    final avgDE = (sumDr + sumDg + sumDb) / (n * 3);

    print('${file.path.split("/").last}');
    print('  params: Δb=${brightness.toStringAsFixed(1)}  c=${contrast.toStringAsFixed(3)}  noise=$noiseLevel');
    print('  max Δ/ch:  R=${maxDr.toInt()} G=${maxDg.toInt()} B=${maxDb.toInt()}');
    print('  avg Δ/ch:  R=${(sumDr/n).toStringAsFixed(2)} G=${(sumDg/n).toStringAsFixed(2)} B=${(sumDb/n).toStringAsFixed(2)}');
    print('  pixels changed: $diffCount / $n (${(diffCount/n*100).toStringAsFixed(1)}%)');
    print('');
  }
}
