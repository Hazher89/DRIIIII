// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<String?> pdfBytesToViewUrl(Uint8List bytes) async {
  final blob = html.Blob([bytes], 'application/pdf');
  return html.Url.createObjectUrlFromBlob(blob);
}
