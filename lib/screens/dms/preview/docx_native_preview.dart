import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'docx_native_preview_stub.dart'
    if (dart.library.io) 'docx_native_preview_io.dart' as impl;

/// Native DOCX-rendering (desktop/mobil) når Office Online ikke er tilgjengelig.
Widget buildDocxNativePreview(Uint8List bytes) {
  return impl.buildDocxNativePreview(bytes);
}
