import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

void main() {
  final rand = Random(42);
  final file = File('bg_details.png');
  final originalBytes = file.readAsBytesSync();

  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) {
    print('Cannot decode');
    return;
  }

  // Read original EXIF
  print('=== ORIGINAL EXIF ===');
  final origExif = decoded.exif;
  if (origExif != null) {
    print(origExif.toString());
  } else {
    print('(none)');
  }

  // Apply fake EXIF
  final exif = img.ExifData();
  final ifd0 = exif.imageIfd;

  const makes = ['Apple', 'Samsung', 'Google'];
  ifd0[0x010F] = img.IfdValueAscii(makes[rand.nextInt(makes.length)]);

  const models = ['iPhone 15 Pro Max', 'Galaxy S24 Ultra'];
  ifd0[0x0110] = img.IfdValueAscii(models[rand.nextInt(models.length)]);

  final dt = DateTime.now().subtract(Duration(days: rand.nextInt(7)));
  final dateStr =
      '${dt.year}:${dt.month.toString().padLeft(2, '0')}:${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  ifd0[0x9003] = img.IfdValueAscii(dateStr);
  ifd0[0x0132] = img.IfdValueAscii(dateStr);
  ifd0[0x0131] = img.IfdValueAscii('obfuscateflutter');

  decoded.exif = exif;

  // Re-encode as PNG and inject eXIf
  var encoded = img.PngEncoder(level: 6).encode(decoded);

  // Inject eXIf chunk
  final buf = img.OutputBuffer(bigEndian: true);
  exif.write(buf);
  final tiffBytes = buf.getBytes();
  const exifPrefix = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00];
  final chunkData = [...exifPrefix, ...tiffBytes];
  final type = [0x65, 0x58, 0x49, 0x66];

  // CRC32
  int crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  final crcInput = [...type, ...chunkData];
  final crcVal = crc32(crcInput);
  final crcBytes = [
    (crcVal >> 24) & 0xFF,
    (crcVal >> 16) & 0xFF,
    (crcVal >> 8) & 0xFF,
    crcVal & 0xFF,
  ];
  final lenBytes = [
    (chunkData.length >> 24) & 0xFF,
    (chunkData.length >> 16) & 0xFF,
    (chunkData.length >> 8) & 0xFF,
    chunkData.length & 0xFF,
  ];
  final chunk = [...lenBytes, ...type, ...chunkData, ...crcBytes];
  const ihdrEnd = 33; // 8(sig) + 4(len) + 4(IHDR) + 13(data) + 4(crc)
  final pngResult =
      [...encoded.sublist(0, ihdrEnd), ...chunk, ...encoded.sublist(ihdrEnd)];

  final outPath = 'bg_details_exif_test.png';
  File(outPath).writeAsBytesSync(pngResult);
  print('Wrote: $outPath (${pngResult.length} bytes, original: ${originalBytes.length})');

  // Read back and verify EXIF
  final verify = img.decodeImage(File(outPath).readAsBytesSync());
  if (verify != null && verify.exif != null) {
    print('\n=== INJECTED EXIF ===');
    print(verify.exif.toString());
  } else {
    print('\nFAILED: No EXIF data found in output');
  }

  // Also test JPEG
  final jpgEncoded = img.JpegEncoder(quality: 92).encode(decoded);
  File('bg_details_exif_test.jpg').writeAsBytesSync(jpgEncoded);
  final jpgVerify = img.decodeImage(jpgEncoded);
  if (jpgVerify != null && jpgVerify.exif != null) {
    print('\n=== JPEG EXIF (via encoder) ===');
    print(jpgVerify.exif.toString());
  } else {
    print('\nJPEG: No EXIF data found');
  }
}
