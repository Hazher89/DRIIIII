import 'dart:typed_data';

import 'media_display_url_stub.dart'
    if (dart.library.html) 'media_display_url_web.dart'
    if (dart.library.io) 'media_display_url_io.dart' as impl;

/// Konverter nedlastede bytes til URL/sti som `<video>` / `<img>` kan spille av.
Future<String> bytesToMediaUrl(
  Uint8List bytes, {
  String mimeType = 'application/octet-stream',
}) {
  return impl.bytesToMediaUrl(bytes, mimeType: mimeType);
}

String guessVideoMimeType(String? fileName, String? mimeType) {
  final m = mimeType?.toLowerCase().trim();
  if (m != null && m.startsWith('video/')) return m;
  final lower = (fileName ?? '').toLowerCase();
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.m4v')) return 'video/x-m4v';
  return 'video/mp4';
}

String guessMediaMimeType(String? fileName, String? mimeType) {
  final m = mimeType?.toLowerCase().trim();
  if (m != null && m.isNotEmpty) return m;
  final lower = (fileName ?? '').toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.m4v')) return 'video/x-m4v';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  return 'application/octet-stream';
}
