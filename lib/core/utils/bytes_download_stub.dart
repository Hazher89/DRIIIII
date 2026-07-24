import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<void> downloadBytesImpl(
  Uint8List bytes,
  String filename, {
  String mime = 'application/octet-stream',
}) async {
  // On native, open the system share sheet (works for PDF and ZIP).
  await Printing.sharePdf(bytes: bytes, filename: filename);
}
