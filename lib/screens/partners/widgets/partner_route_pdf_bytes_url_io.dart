import 'dart:io';
import 'dart:typed_data';

Future<String?> pdfBytesToViewUrl(Uint8List bytes) async {
  final f = File(
    '${Directory.systemTemp.path}/driftpro_preview_${DateTime.now().microsecondsSinceEpoch}.pdf',
  );
  await f.writeAsBytes(bytes, flush: true);
  return f.uri.toString();
}
