import 'dart:convert';

class StringCryptUtils {
  /// Caesar shift each UTF-8 byte, base64 encode.
  /// Returns a string safe to embed in Dart source code.
  static String encrypt(String text, int key) {
    final bytes = utf8.encode(text);
    final shifted = bytes.map((b) => (b + key) % 256).toList();
    return base64.encode(shifted);
  }

  /// Reverse: base64 decode, Caesar unshift each byte, UTF-8 decode.
  static String decrypt(String base64Text, int key) {
    final shifted = base64.decode(base64Text);
    final bytes = shifted.map((b) => (b - key + 256) % 256).toList();
    return utf8.decode(bytes);
  }
}
