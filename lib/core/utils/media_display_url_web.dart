import 'dart:html' as html;
import 'dart:typed_data';

Future<String> bytesToMediaUrl(
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
}) async {
  final blob = html.Blob([bytes], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}
