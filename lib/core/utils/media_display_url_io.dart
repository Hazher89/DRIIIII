import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> bytesToMediaUrl(
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
}) async {
  final dir = await getTemporaryDirectory();
  final ext = mimeType.contains('webm')
      ? 'webm'
      : mimeType.contains('quicktime')
          ? 'mov'
          : 'mp4';
  final file = File(
    '${dir.path}/driftpro_feed_${DateTime.now().microsecondsSinceEpoch}.$ext',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
