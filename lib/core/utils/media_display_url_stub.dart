import 'dart:convert';
import 'dart:typed_data';

Future<String> bytesToMediaUrl(
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
}) async {
  final b64 = base64Encode(bytes);
  return 'data:$mimeType;base64,$b64';
}
