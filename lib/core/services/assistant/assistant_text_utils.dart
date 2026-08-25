/// Tekstrensing for kunnskapsbasen (assistent / RAG).
class AssistantTextUtils {
  AssistantTextUtils._();

  static bool looksLikeHtml(String text) {
    final t = text.trim().toLowerCase();
    return t.startsWith('<!doctype') ||
        t.startsWith('<html') ||
        t.contains('<head>') ||
        t.contains('<body>') ||
        t.contains('<script') ||
        t.contains('<meta ');
  }

  static bool looksLikeLoadError(String text) {
    final t = text.trim();
    return t.startsWith('Unable to load asset') ||
        t.startsWith('Kunne ikke laste') ||
        t.contains('FormatException') ||
        t.contains('StateError');
  }

  static String stripHtml(String text) {
    var t = text.trim();
    if (!t.contains('<')) return t;
    t = t.replaceAll(RegExp(r'<[^>]+>'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static String cleanTitle(String title) {
    final t = stripHtml(title).trim();
    if (t.isEmpty || looksLikeHtml(title)) return 'Dokumentasjon';
    if (t.length > 80) return '${t.substring(0, 77)}…';
    return t;
  }

  static String cleanBody(String body) {
    final t = stripHtml(body).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return t;
  }

  static bool isUsefulChunk({
    required String id,
    required String title,
    required String body,
  }) {
    if (id.contains('_err')) return false;
    if (looksLikeHtml(title) || looksLikeHtml(body)) return false;
    if (looksLikeLoadError(body) || looksLikeLoadError(title)) return false;
    if (title.trim() == 'Kunne ikke laste dokument') return false;
    return cleanBody(body).length >= 24;
  }
}
