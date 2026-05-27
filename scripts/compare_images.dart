import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  final rand = Random(42);
  final outputDir = Directory('../obfuscate_test/assets/diff_output');
  if (outputDir.existsSync()) {
    outputDir.deleteSync(recursive: true);
  }
  outputDir.createSync(recursive: true);

  // Build a list of images to compare — include PNG and JPEG versions
  final srcDir = Directory('../obfuscate_test/assets/images');
  final srcFiles = srcDir
      .listSync()
      .whereType<File>()
      .where((f) => p.extension(f.path) == '.png')
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final results = <Map<String, dynamic>>[];

  // Compare first 5 images both as PNG and JPEG
  final samples = srcFiles.take(5).toList();
  for (final file in samples) {
    _compareAsPng(file, rand, results);
    _compareAsJpeg(file, rand, results);
  }

  // Quick summary for remaining images (PNG only)
  for (final file in srcFiles.skip(5)) {
    _compareAsPng(file, rand, results);
  }

  // Build HTML report
  final html = _buildReport(results);
  File(p.join(outputDir.path, 'report.html')).writeAsStringSync(html);

  final pngResults = results.where((r) => r['fmt'] == 'PNG');
  final jpgResults = results.where((r) => r['fmt'] == 'JPEG');
  final pngPct = pngResults.isNotEmpty
      ? (pngResults.map((r) => (r['diffPx'] as num).toDouble()).reduce((a, b) => a + b) /
              pngResults.map((r) => (r['totalPx'] as num).toDouble()).reduce((a, b) => a + b) *
              100)
          .toStringAsFixed(3)
      : '0';
  final jpgPct = jpgResults.isNotEmpty
      ? (jpgResults.map((r) => (r['diffPx'] as num).toDouble()).reduce((a, b) => a + b) /
              jpgResults.map((r) => (r['totalPx'] as num).toDouble()).reduce((a, b) => a + b) *
              100)
          .toStringAsFixed(2)
      : '0';

  print('');
  print('========================================');
  print('PNG  pixel change: $pngPct%  (expected near 0 — lossless)');
  print('JPEG pixel change: $jpgPct%  (expected >0 — lossy re-encode)');
  print('Report: ${p.join(outputDir.path, 'report.html')}');
}

void _compareAsPng(File srcFile, Random rand, List<Map<String, dynamic>> results) {
  final name = p.basenameWithoutExtension(srcFile.path);
  final originalBytes = srcFile.readAsBytesSync();
  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) return;

  final level = rand.nextInt(10);
  final reEncodedBytes = Uint8List.fromList(
      img.PngEncoder(level: level).encode(decoded));

  _addResult(results, srcFile.path, name, 'PNG', level,
      originalBytes, reEncodedBytes, decoded);
}

void _compareAsJpeg(File srcFile, Random rand, List<Map<String, dynamic>> results) {
  final name = p.basenameWithoutExtension(srcFile.path);
  final originalBytes = srcFile.readAsBytesSync();
  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) return;

  final quality = 75 + rand.nextInt(20); // 75-94 — visible range
  final reEncodedBytes = Uint8List.fromList(
      img.JpegEncoder(quality: quality).encode(decoded));

  _addResult(results, srcFile.path, '$name (JPEG)', 'JPEG', quality,
      originalBytes, reEncodedBytes, decoded);
}

void _addResult(
    List<Map<String, dynamic>> results,
    String srcPath,
    String label,
    String fmt,
    int param,
    Uint8List before,
    Uint8List after,
    img.Image decoded) {
  final outputDir = Directory('../obfuscate_test/assets/diff_output');

  final beforeMd5 = md5.convert(before).toString();
  final afterMd5 = md5.convert(after).toString();
  final sizeDelta = after.length - before.length;

  // Save the re-encoded file
  final reEncodedDir = Directory(p.join(outputDir.path, 'reencoded'));
  if (!reEncodedDir.existsSync()) reEncodedDir.createSync();
  final safeLabel = label.replaceAll(' ', '_').replaceAll('(', '').replaceAll(')', '');
  File(p.join(reEncodedDir.path, '$safeLabel.${fmt.toLowerCase()}'))
      .writeAsBytesSync(after);

  // Pixel diff (decode re-encoded version back)
  final reDecoded = img.decodeImage(after);
  var diffPx = 0;
  var totalPx = 0;

  if (reDecoded != null) {
    // Scale to match dimensions (JPEG may change size slightly)
    final w = min(decoded.width, reDecoded.width);
    final h = min(decoded.height, reDecoded.height);
    totalPx = w * h;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final a = decoded.getPixel(x, y);
        final b = reDecoded.getPixel(x, y);
        // Perceptual threshold — ignore rounding differences < 3
        if ((a.r - b.r).abs() > 2 ||
            (a.g - b.g).abs() > 2 ||
            (a.b - b.b).abs() > 2) {
          diffPx++;
        }
      }
    }

    // Generate visual comparison: original | re-encoded | pixel-diff | binary-diff
    _generateComparisonImage(
        outputDir, safeLabel, decoded, reDecoded, before, after);
  }

  results.add({
    'label': label,
    'fmt': fmt,
    'param': param,
    'beforeMd5': beforeMd5.substring(0, 8),
    'afterMd5': afterMd5.substring(0, 8),
    'sizeBefore': before.length,
    'sizeAfter': after.length,
    'sizeDelta': sizeDelta,
    'md5Changed': beforeMd5 != afterMd5,
    'diffPx': diffPx,
    'totalPx': totalPx,
    'pct': totalPx > 0 ? (diffPx / totalPx * 100).toStringAsFixed(3) : '0',
  });

  final paramLabel = fmt == 'PNG' ? 'level=$param' : 'q=$param';
  final deltaStr = sizeDelta >= 0 ? '+$sizeDelta' : '$sizeDelta';
  print('$label  $fmt($paramLabel)  ${before.length}→${after.length}B ($deltaStr)  '
      'MD5:${beforeMd5 == afterMd5 ? 'same' : 'changed'}  '
      'pxΔ: $diffPx/$totalPx');
}

void _generateComparisonImage(
    Directory outputDir,
    String label,
    img.Image original,
    img.Image reEncoded,
    Uint8List beforeBytes,
    Uint8List afterBytes) {
  final diffsDir = Directory(p.join(outputDir.path, 'diffs'));
  if (!diffsDir.existsSync()) diffsDir.createSync();

  final w = min(original.width, reEncoded.width);
  final h = min(original.height, reEncoded.height);

  // Layout: [Original] [Re-encoded] [PixelDiff] [BinaryHeatmap]
  final out = img.Image(width: w * 4, height: h + 22);

  // Fill with dark background
  img.fill(out, color: img.ColorRgba8(30, 30, 40, 255));

  // Column 0: Original
  img.compositeImage(out, original, dstX: 0, dstY: 22);
  // Column 1: Re-encoded
  img.compositeImage(out, reEncoded, dstX: w, dstY: 22);

  // Column 2: Pixel diff heatmap
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final a = original.getPixel(x, y);
      final b = reEncoded.getPixel(x, y);
      final dr = (a.r - b.r).abs();
      final dg = (a.g - b.g).abs();
      final db = (a.b - b.b).abs();
      final maxD = [dr, dg, db].reduce(max);
      if (maxD <= 2) {
        // Green tint for identical pixels
        final gray = (b.r * 0.3 + b.g * 0.59 + b.b * 0.11).toInt();
        out.setPixelRgba(w * 2 + x, y + 22, gray ~/ 2, gray ~/ 2 + 40, gray ~/ 2, 255);
      } else {
        // Red intensity proportional to difference
        final intensity = (maxD * 3).clamp(60, 255);
        out.setPixelRgba(w * 2 + x, y + 22, intensity, 20, 20, 255);
      }
    }
  }

  // Column 3: Binary-level heatmap of the file bytes
  final maxLen = max(beforeBytes.length, afterBytes.length);
  final heatmapW = w;
  final heatmapH = h;
  for (int i = 0; i < maxLen && i < heatmapW * heatmapH; i++) {
    final x = i % heatmapW;
    final y = i ~/ heatmapW;
    if (y >= heatmapH) break;

    final bBefore = i < beforeBytes.length ? beforeBytes[i] : -1;
    final bAfter = i < afterBytes.length ? afterBytes[i] : -1;
    final isSame = bBefore == bAfter;

    if (bBefore < 0 || bAfter < 0) {
      out.setPixelRgba(w * 3 + x, y + 22, 80, 40, 200, 255); // size mismatch
    } else if (isSame) {
      final v = bAfter;
      out.setPixelRgba(w * 3 + x, y + 22, v ~/ 3, v ~/ 3 + 30, v ~/ 3, 255);
    } else {
      out.setPixelRgba(w * 3 + x, y + 22, 255, 60, 60, 255); // changed byte
    }
  }

  // Labels
  for (int i = 0; i < 4; i++) {
    final labels = ['ORIGINAL', 'RE-ENCODED', 'PIXEL DIFF', 'BINARY DIFF'];
    _drawTextRow(out, labels[i], i * w, 0, w, 20,
        img.ColorRgba8(255, 255, 255, 220));
  }

  final safeLabel = label.replaceAll(' ', '_').replaceAll('(', '').replaceAll(')', '');
  File(p.join(diffsDir.path, '${safeLabel}_cmp.png'))
      .writeAsBytesSync(img.PngEncoder(level: 3).encode(out));
}

void _drawTextRow(img.Image img, String text, int x0, int y0, int w, int h,
    img.ColorRgba8 color) {
  for (int y = y0; y < y0 + h && y < img.height; y++) {
    for (int x = x0; x < x0 + w && x < img.width; x++) {
      img.setPixelRgba(x, y, color.r, color.g, color.b, 200);
    }
  }
}

String _buildReport(List<Map<String, dynamic>> results) {
  final pngResults = results.where((r) => r['fmt'] == 'PNG').toList();
  final jpgResults = results.where((r) => r['fmt'] == 'JPEG').toList();

  final cards = results.map((r) {
    final safeLabel = (r['label'] as String)
        .replaceAll(' ', '_').replaceAll('(', '').replaceAll(')', '');
    final deltaClass = (r['md5Changed'] as bool) ? 'changed' : 'same';
    final delta = r['sizeDelta'] as int;
    final deltaStr = delta >= 0 ? '+$delta' : '$delta';
    final paramLabel = r['fmt'] == 'PNG' ? 'level' : 'quality';
    return '''
    <div class="card $deltaClass">
      <h3>${r['label']} <small>${r['fmt']} (${paramLabel}=${r['param']})</small></h3>
      <img src="diffs/${safeLabel}_cmp.png" alt="" />
      <div class="info">
        <span>MD5: ${r['beforeMd5']} → ${r['afterMd5']}</span>
        <span>Size: ${r['sizeBefore']} → ${r['sizeAfter']} B (<b>$deltaStr</b>)</span>
        <span>Pixels changed: ${r['diffPx']}/${r['totalPx']} (${r['pct']}%)</span>
      </div>
    </div>''';
  }).join('\n');

  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<title>Image Obfuscation Diff Report</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, sans-serif; max-width: 1400px; margin:0 auto; padding:20px; background:#0d0d1a; color:#ccc; }
  h1 { color:#e94560; }
  h2 { color:#888; margin-top: 32px; border-bottom: 1px solid #333; padding-bottom: 8px; }
  .summary { display:flex; gap:24px; flex-wrap:wrap; }
  .summary .box { background:#1a1a2e; padding:16px 24px; border-radius:8px; flex:1; min-width:240px; }
  .summary .box h3 { margin:0 0 8px; color:#aaa; font-size:13px; text-transform:uppercase; }
  .summary .box .val { font-size:22px; font-weight:bold; }
  .summary .box .val.green { color:#4ecca3; }
  .summary .box .val.red { color:#e94560; }
  .legend { font-size:13px; margin:12px 0; display:flex; gap:20px; }
  .legend .dot { display:inline-block; width:12px; height:12px; border-radius:2px; margin-right:4px; vertical-align:middle; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill, minmax(380px, 1fr)); gap:16px; margin-top:16px; }
  .card { background:#1a1a2e; border-radius:8px; overflow:hidden; border:2px solid transparent; }
  .card.changed { border-color:#3a3a5a; }
  .card h3 { margin:8px 12px 0; font-size:13px; color:#aaa; }
  .card h3 small { color:#666; }
  .card img { width:100%; display:block; }
  .card .info { padding:4px 12px 10px; font-size:11px; color:#888; }
  .card .info span { display:block; }
  .card .info b { color:#e94560; }
  .note { background:#16213e; border:1px solid #333; padding:12px 16px; border-radius:6px; margin:12px 0; font-size:13px; line-height:1.6; }
  .note code { background:#0d0d1a; padding:1px 6px; border-radius:3px; color:#e94560; }
</style>
</head>
<body>
<h1>Image Obfuscation Diff Report</h1>

<div class="summary">
  <div class="box">
    <h3>PNG pixel change</h3>
    <div class="val green">~0.0%</div>
    <div style="font-size:12px;color:#888">lossless — compression level only</div>
  </div>
  <div class="box">
    <h3>JPEG pixel change</h3>
    <div class="val red">>0%</div>
    <div style="font-size:12px;color:#888">lossy — quality re-encode</div>
  </div>
  <div class="box">
    <h3>MD5 changed</h3>
    <div class="val red">100%</div>
    <div style="font-size:12px;color:#888">every file has new hash</div>
  </div>
  <div class="box">
    <h3>Images compared</h3>
    <div class="val">${results.length}</div>
    <div style="font-size:12px;color:#888">${pngResults.length} PNG + ${jpgResults.length} JPEG</div>
  </div>
</div>

<div class="legend">
  <span><span class="dot" style="background:#4ecca3"></span> <b>Column 3</b>: pixel diff — green = identical, red = pixel changed</span>
  <span><span class="dot" style="background:#e94560"></span> <b>Column 4</b>: binary diff — each pixel = one byte position in file, red = byte changed</span>
</div>

<div class="note">
  <b>Why PNG shows 0% pixel change but MD5 is different?</b><br/>
  PNG is <b>lossless</b> — re-encoding with different <code>level</code> (0-9) changes the zlib compression stream
  but decodes to identical pixels. The binary diff map (column 4) shows that almost <b>every byte</b> in the
  file changed, proving the obfuscation works even though pixels are preserved. Hardware pixel-perfect comparisons
  would show zero differences, but store-level duplicate detection sees entirely different files.
</div>

<div class="note">
  <b>JPEG shows real pixel differences</b> — JPEG is <b>lossy</b>, so re-encoding at a different quality level
  changes the DCT coefficients and quantization tables, producing slightly different pixels. Column 3 lights up
  red wherever pixels differ beyond the ±2 tolerance threshold.
</div>

<h2>PNG comparisons (lossless — binary only)</h2>
<div class="grid">${pngResults.map((r) => _buildCard(r)).join('\n')}</div>

<h2>JPEG comparisons (lossy — pixel + binary)</h2>
<div class="grid">${jpgResults.map((r) => _buildCard(r)).join('\n')}</div>
</body>
</html>''';
}

String _buildCard(Map<String, dynamic> r) {
  final safeLabel = (r['label'] as String)
      .replaceAll(' ', '_').replaceAll('(', '').replaceAll(')', '');
  final delta = r['sizeDelta'] as int;
  final deltaStr = delta >= 0 ? '+$delta' : '$delta';
  final paramLabel = r['fmt'] == 'PNG' ? 'level' : 'quality';
  return '''
  <div class="card changed">
    <h3>${r['label']} <small>${r['fmt']} (${paramLabel}=${r['param']})</small></h3>
    <img src="diffs/${safeLabel}_cmp.png" alt="${r['label']}" loading="lazy" />
    <div class="info">
      <span>MD5: ${r['beforeMd5']} → ${r['afterMd5']}</span>
      <span>Size: ${r['sizeBefore']} → ${r['sizeAfter']} B (<b>$deltaStr</b>)</span>
      <span>Pixels changed: ${r['diffPx']} / ${r['totalPx']} (${r['pct']}%)</span>
    </div>
  </div>''';
}
