import 'dart:convert';

import 'package:http/http.dart' as http;

class NrkHeadline {
  final String title;
  final String? link;

  const NrkHeadline({required this.title, this.link});
}

class NrkNewsFeedService {
  static const _feedUrl = 'https://www.nrk.no/toppsaker.rss';

  static Future<List<NrkHeadline>> fetch({int maxItems = 12}) async {
    final res = await http
        .get(
          Uri.parse(_feedUrl),
          headers: const {
            'Accept': 'application/rss+xml, application/xml, text/xml, */*',
            'User-Agent': 'DriftPro-Infoskjerm/1.0',
          },
        )
        .timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) return [];

    // NRK leverer UTF-8; noen plattformer tolker feil charset uten eksplisitt dekoding.
    final body = utf8.decode(res.bodyBytes);
    final items = body.split('<item>');
    if (items.length <= 1) return [];

    final out = <NrkHeadline>[];
    for (var i = 1; i < items.length && out.length < maxItems; i++) {
      final chunk = items[i];
      final title = _tag(chunk, 'title');
      if (title == null || title.isEmpty || title == 'NRK') continue;
      out.add(NrkHeadline(title: title, link: _tag(chunk, 'link')));
    }
    return out;
  }

  static String? _tag(String xml, String tag) {
    final cdata = RegExp(
      '<$tag><!\\[CDATA\\[(.*?)\\]\\]></$tag>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(xml);
    if (cdata != null) return _decode(cdata.group(1)!.trim());

    final open = '<$tag>';
    final close = '</$tag>';
    final start = xml.indexOf(open);
    if (start < 0) return null;
    final from = start + open.length;
    final end = xml.indexOf(close, from);
    if (end < 0) return null;
    return _decode(xml.substring(from, end).trim());
  }

  static String _decode(String s) {
    var out = _fixMojibake(s);
    out = out
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&aring;', 'å')
        .replaceAll('&Aring;', 'Å')
        .replaceAll('&oslash;', 'ø')
        .replaceAll('&Oslash;', 'Ø')
        .replaceAll('&aelig;', 'æ')
        .replaceAll('&AElig;', 'Æ')
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—')
        .replaceAll('&hellip;', '…');

    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });
    out = out.replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });
    return out;
  }

  /// Reparerer feilaktig Latin-1-tolkning av UTF-8 (f.eks. Ã¥ → å).
  static String _fixMojibake(String s) {
    if (!s.contains('Ã') && !s.contains('â') && !s.contains('ï¿½')) return s;
    try {
      return utf8.decode(latin1.encode(s), allowMalformed: true);
    } catch (_) {
      return s;
    }
  }
}
