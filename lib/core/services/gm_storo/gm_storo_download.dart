import 'dart:typed_data';

import 'gm_storo_download_stub.dart'
    if (dart.library.html) 'gm_storo_download_web.dart' as impl;

void downloadGmStoroExcel(Uint8List bytes, String filename) {
  impl.downloadGmStoroBytes(bytes, filename);
}
