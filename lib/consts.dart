import 'dart:io';

const imagesExtNames = ['.png', '.webp', '.jpg'];

const outputExtName = ['.ipa', '.apk'];

String getFileExtName(File file) {
  return '.' + file.path.split('.').last;
}

String getFileDirPath(File file) {
  return file.parent.path;
}
