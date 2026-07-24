import 'dart:typed_data';

import 'bytes_download_stub.dart'
    if (dart.library.html) 'bytes_download_web.dart' as impl;

/// Trigger a browser download (web) or share sheet (native).
Future<void> downloadBytes(
  Uint8List bytes,
  String filename, {
  String mime = 'application/octet-stream',
}) {
  return impl.downloadBytesImpl(bytes, filename, mime: mime);
}
