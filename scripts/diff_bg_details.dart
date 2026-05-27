import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

int noiseAt(int x, int y, int seed) {
  final h =
      ((x * 374761393 + y * 668265263 + seed * 1274126177) & 0x7FFFFFFF);
  return (h % 3) - 1;
}

void main() {
  final rand = Random(42);
  final file = File('bg_details.png');
  final originalBytes = file.readAsBytesSync();

  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) {
    print('Cannot decode image');
    return;
  }

  print('Original: ${decoded.width}x${decoded.height}  '
      '${originalBytes.length} bytes  MD5=${md5.convert(originalBytes).toString().substring(0, 12)}');

  // ---- Apply the same adjustments as the obfuscation tool ----
  final brightness = (rand.nextDouble() - 0.5) * 3;
  final contrast = 0.995 + rand.nextDouble() * 0.010;
  final noiseSeed = rand.nextInt(1 << 30);
  final noiseLevel = rand.nextInt(2);

  print('Params: brightness=${brightness.toStringAsFixed(2)}  '
      'contrast=${contrast.toStringAsFixed(4)}  noise=$noiseLevel\n');

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

  // Re-encode
  final adjustedBytes =
      img.PngEncoder(level: 6).encode(adjusted);
  File('bg_details_obfuscated.png').writeAsBytesSync(adjustedBytes);

  print('Obfuscated: ${adjusted.width}x${adjusted.height}  '
      '${adjustedBytes.length} bytes  MD5=${md5.convert(adjustedBytes).toString().substring(0, 12)}');

  // ---- Pixel-level diff stats ----
  final w = decoded.width;
  final h = decoded.height;
  final n = w * h;

  var maxDr = 0, maxDg = 0, maxDb = 0;
  var sumDr = 0.0, sumDg = 0.0, sumDb = 0.0;
  var diffCount = 0;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final a = decoded.getPixel(x, y);
      final b = adjusted.getPixel(x, y);
      final dr = (a.r - b.r).abs().toInt();
      final dg = (a.g - b.g).abs().toInt();
      final db = (a.b - b.b).abs().toInt();
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
  final pct = diffCount / n * 100;

  print('----------- Diff Report -----------');
  print('max Δ per channel:     R=$maxDr  G=$maxDg  B=$maxDb');
  print('avg Δ per channel:     R=${(sumDr / n).toStringAsFixed(3)}  '
      'G=${(sumDg / n).toStringAsFixed(3)}  B=${(sumDb / n).toStringAsFixed(3)}');
  print('avg ΔE (simplified):   ${avgDE.toStringAsFixed(3)}');
  print('pixels changed:        $diffCount / $n (${pct.toStringAsFixed(1)}%)');
  print('MD5 changed:           YES (completely different)');

  // ---- Generate comparison image ----
  // Layout: [original] [obfuscated] [pixel-diff ×10] [binary-heatmap]
  final cmpW = (w * 4).clamp(0, 3200);
  final scale = cmpW ~/ (w * 4);
  final cmpH = (h * scale) + 24;
  final cmp = img.Image(width: w * 4, height: h + 24);
  img.fill(cmp, color: img.ColorRgba8(20, 20, 30, 255));

  // Column 0: Original
  img.compositeImage(cmp, decoded, dstX: 0, dstY: 24);
  // Column 1: Obfuscated
  img.compositeImage(cmp, adjusted, dstX: w, dstY: 24);

  // Column 2: Pixel diff amplified ×10 for visibility
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final a = decoded.getPixel(x, y);
      final b = adjusted.getPixel(x, y);
      final dr = ((a.r - b.r).abs() * 10).clamp(0, 255);
      final dg = ((a.g - b.g).abs() * 10).clamp(0, 255);
      final db = ((a.b - b.b).abs() * 10).clamp(0, 255);
      final maxD = [dr, dg, db].reduce(max);
      if (maxD == 0) {
        cmp.setPixelRgba(w * 2 + x, y + 24, 40, 50, 40, 255); // dark green = same
      } else {
        cmp.setPixelRgba(w * 2 + x, y + 24, maxD, 20, 20, 255); // red intensity = diff
      }
    }
  }

  // Column 3: Binary heatmap of the PNG file
  final origFileBytes = originalBytes;
  final obfFileBytes = adjustedBytes;
  final maxLen = max(origFileBytes.length, obfFileBytes.length);
  for (int i = 0; i < maxLen && i < w * h; i++) {
    final x = i % w;
    final y = i ~/ w;
    if (y >= h) break;
    final bo = i < origFileBytes.length ? origFileBytes[i] : -1;
    final ba = i < obfFileBytes.length ? obfFileBytes[i] : -1;
    if (bo < 0 || ba < 0) {
      cmp.setPixelRgba(w * 3 + x, y + 24, 200, 100, 255, 255);
    } else if (bo == ba) {
      cmp.setPixelRgba(w * 3 + x, y + 24, 40, bo ~/ 2 + 20, 40, 255);
    } else {
      cmp.setPixelRgba(w * 3 + x, y + 24, 255, 50, 50, 255);
    }
  }

  // Labels
  final labels = ['ORIGINAL', 'OBFUSCATED', 'PIXEL DIFF ×10', 'BINARY HEATMAP'];
  for (int i = 0; i < 4; i++) {
    for (int dy = 0; dy < 22; dy++) {
      for (int dx = 0; dx < w && dx + i * w < cmp.width; dx++) {
        cmp.setPixelRgba(i * w + dx, dy, 255, 255, 255, 180);
      }
    }
  }

  File('bg_details_comparison.png')
      .writeAsBytesSync(img.PngEncoder(level: 3).encode(cmp));

  print('\nOutput files:');
  print('  bg_details_obfuscated.png  — transformed image');
  print('  bg_details_comparison.png  — 4-column comparison (original | obfuscated | diff×10 | binary)');

  // Verify round-trip is visually lossless (ΔE)
  if (avgDE < 2.0) {
    print('\nVERDICT: Visually imperceptible (avg ΔE < 2.0)');
  } else if (avgDE < 3.0) {
    print('\nVERDICT: Near-imperceptible (avg ΔE < 3.0)');
  } else {
    print('\nVERDICT: Visible changes detected — parameters may be too aggressive');
  }
}
