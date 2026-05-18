/// Gjenkjenner filtype fra navn, sti, Content-Type og filinnhold (magic bytes).
enum FilePreviewKind { pdf, image, text, office, video, audio, universal }

class FileTypeResolver {
  FileTypeResolver._();

  /// Ekte filendelse fra filnavn (ikke hele navnet uten punktum).
  static String? extensionFromName(String name) {
    final trimmed = name.trim();
    final dot = trimmed.lastIndexOf('.');
    if (dot <= 0 || dot >= trimmed.length - 1) return null;
    final ext = trimmed.substring(dot + 1).toLowerCase();
    if (ext.isEmpty || ext.length > 10) return null;
    if (ext.contains(' ') || ext.contains('/')) return null;
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(ext)) return null;
    return ext;
  }

  /// Henter endelse fra lagringssti (f.eks. `12345_rapport.pdf`).
  static String? extensionFromStoragePath(String path) {
    final segment = path.split('/').last;
    final underscore = segment.indexOf('_');
    final name = underscore > 0 && underscore < 24
        ? segment.substring(underscore + 1)
        : segment;
    return extensionFromName(name);
  }

  static FilePreviewKind? fromMagicBytes(List<int> bytes) {
    if (bytes.length < 4) return null;
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return FilePreviewKind.pdf;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return FilePreviewKind.image;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return FilePreviewKind.image;
    }
    if (bytes.length >= 6) {
      final h = String.fromCharCodes(bytes.take(6));
      if (h.startsWith('GIF87a') || h.startsWith('GIF89a')) {
        return FilePreviewKind.image;
      }
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return FilePreviewKind.image;
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07)) {
      return FilePreviewKind.office;
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0) {
      return FilePreviewKind.office;
    }
    if (bytes.length >= 12) {
      final riff = String.fromCharCodes(bytes.take(4));
      if (riff == 'RIFF') {
        final form = String.fromCharCodes(bytes.sublist(8, 12));
        if (form == 'WEBP') return FilePreviewKind.image;
        if (form == 'AVI ') return FilePreviewKind.video;
      }
    }
    if (bytes.length >= 4) {
      final ftyp = String.fromCharCodes(bytes.sublist(4, 8));
      if (ftyp == 'ftyp') return FilePreviewKind.video;
    }
    return null;
  }

  static FilePreviewKind? fromContentType(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final ct = raw.split(';').first.trim().toLowerCase();
    if (ct == 'application/pdf') return FilePreviewKind.pdf;
    if (ct.startsWith('image/')) return FilePreviewKind.image;
    if (ct.startsWith('text/')) return FilePreviewKind.text;
    if (ct.startsWith('video/')) return FilePreviewKind.video;
    if (ct.startsWith('audio/')) return FilePreviewKind.audio;
    if (ct.contains('json') || ct.contains('xml') || ct.contains('csv')) {
      return FilePreviewKind.text;
    }
    const officeTypes = {
      'application/msword',
      'application/vnd.openxmlformats-officedocument',
      'application/vnd.ms-excel',
      'application/vnd.ms-powerpoint',
    };
    for (final o in officeTypes) {
      if (ct.contains(o) || ct.startsWith(o)) return FilePreviewKind.office;
    }
    if (ct.contains('officedocument') ||
        ct.contains('msword') ||
        ct.contains('spreadsheet') ||
        ct.contains('presentation')) {
      return FilePreviewKind.office;
    }
    return null;
  }

  static FilePreviewKind? fromExtension(String? ext) {
    if (ext == null || ext.isEmpty) return null;
    const images = {
      'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'ico', 'heic', 'heif',
    };
    const texts = {
      'txt', 'md', 'csv', 'json', 'log', 'xml', 'html', 'htm', 'yaml', 'yml',
      'ini', 'cfg', 'env', 'sql', 'dart', 'js', 'ts', 'css',
    };
    const office = {
      'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'rtf',
    };
    const video = {'mp4', 'webm', 'mov', 'avi', 'mkv', 'm4v'};
    const audio = {'mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac'};

    if (ext == 'pdf') return FilePreviewKind.pdf;
    if (images.contains(ext)) return FilePreviewKind.image;
    if (texts.contains(ext)) return FilePreviewKind.text;
    if (office.contains(ext)) return FilePreviewKind.office;
    if (video.contains(ext)) return FilePreviewKind.video;
    if (audio.contains(ext)) return FilePreviewKind.audio;
    return null;
  }

  /// Kombinerer alle signaler – ukjent → [FilePreviewKind.universal] (nettleser-visning).
  static FilePreviewKind resolve({
    required String fileName,
    required String storagePath,
    String? storedExtension,
    String? contentType,
    List<int>? magicBytes,
  }) {
    final fromMagic = magicBytes != null ? fromMagicBytes(magicBytes) : null;
    if (fromMagic != null) return fromMagic;

    final fromCt = fromContentType(contentType);
    if (fromCt != null) return fromCt;

    final ext = _normalizeExt(storedExtension) ??
        extensionFromName(fileName) ??
        extensionFromStoragePath(storagePath);

    final fromExt = fromExtension(ext);
    if (fromExt != null) return fromExt;

    return FilePreviewKind.universal;
  }

  static String? _normalizeExt(String? ext) {
    if (ext == null || ext.isEmpty) return null;
    final e = ext.toLowerCase().trim();
    if (e.contains(' ') || e.length > 10) return null;
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(e)) return null;
    return e;
  }

  static bool isLikelyText(List<int> bytes) {
    if (bytes.isEmpty) return false;
    var printable = 0;
    final n = bytes.length > 512 ? 512 : bytes.length;
    for (var i = 0; i < n; i++) {
      final b = bytes[i];
      if (b == 9 || b == 10 || b == 13 || (b >= 32 && b < 127)) printable++;
    }
    return printable / n > 0.92;
  }
}
