class StringCryptUtils {
  final String SEP;
  final String SEK;
  
  StringCryptUtils.init(this.SEP, this.SEK);

  static final Map<String, String> _cryptCache = {};

  String encrypt(String text, int key) {
    String encryptedText = '';
    for (int i = 0; i < text.length; i++) {
      int charCode = text.codeUnitAt(i);
      int encryptedCharCode = (charCode + key) % 256;
      encryptedText += String.fromCharCode(encryptedCharCode);
    }
    return encryptedText;
  }

  String decrypt(String encryptedText, int key) {
    if (!encryptedText.startsWith(SEP)) {
      return encryptedText;
    }

    String decryptedText = '';

    final catchDecryptText = _cryptCache[encryptedText] ?? '';

    if (_cryptCache.containsKey(encryptedText) &&
        catchDecryptText.isNotEmpty == true) {
      decryptedText = catchDecryptText;
    } else {
      for (int i = 0; i < encryptedText.length; i++) {
        int charCode = encryptedText.codeUnitAt(i);
        int decryptedCharCode = (charCode - key + 256) % 256;
        decryptedText += String.fromCharCode(decryptedCharCode);
      }
      _cryptCache[encryptedText] = decryptedText;
    }

    return decryptedText;
  }
}
