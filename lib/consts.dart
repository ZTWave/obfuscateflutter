import 'dart:io';

const imagesExtNames = ['.png', '.webp', '.jpg'];

String getFileExtName(File file) {
  return '.' + file.path.split('.').last;
}

String getFileDirPath(File file) {
  return file.parent.path;
}
