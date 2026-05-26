import 'dart:convert';

import 'package:flutter/services.dart';

/// Postnummer → stedsnavn (fra POSTKODE.xlsx / assets).
class PostalCodeRegistry {
  PostalCodeRegistry._();

  static Map<String, String>? _byCode;
  static bool _loading = false;

  static Future<void> ensureLoaded() async {
    if (_byCode != null || _loading) return;
    _loading = true;
    try {
      final raw = await rootBundle.loadString('assets/data/norway_postal_codes.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final map = json['postal_codes'] as Map<String, dynamic>? ?? {};
      _byCode = {
        for (final e in map.entries)
          e.key.toString().padLeft(4, '0'): e.value.toString().trim(),
      };
    } catch (_) {
      _byCode = {};
    } finally {
      _loading = false;
    }
  }

  static String? lookupSted(String postalCode) {
    final code = postalCode.replaceAll(RegExp(r'\D'), '').padLeft(4, '0');
    if (code.length != 4) return null;
    return _byCode?[code];
  }

  static bool isKnown(String postalCode) => lookupSted(postalCode) != null;

  /// Oslo-hub / avsender — ikke leveringsområde.
  static bool isHubPostalCode(String code) {
    if (code.length != 4) return false;
    if (code == '0180' || code == '0181') return true;
    if (code.startsWith('048')) return true;
    return false;
  }

  /// Unike postnummer i tekst som finnes i registeret.
  static List<String> extractKnownFromText(String raw) {
    if (_byCode == null || _byCode!.isEmpty) return const [];
    final text = raw.replaceAll('\uFF3F', '_');
    final found = <String>{};
    for (final m in RegExp(r'\b(\d{4})\b').allMatches(text)) {
      final code = m.group(1)!;
      if (isHubPostalCode(code)) continue;
      if (_isEmbeddedInLongNumber(text, m.start, m.end)) continue;
      if (_byCode!.containsKey(code)) found.add(code);
    }
    for (final m in RegExp(r'NO[\s-]*(\d{4})', caseSensitive: false).allMatches(text)) {
      final code = m.group(1)!;
      if (isHubPostalCode(code)) continue;
      if (_byCode!.containsKey(code)) found.add(code);
    }
    return found.toList()..sort();
  }

  /// Unngår f.eks. «0268» inne i lange strekkoder / ordrenummer.
  static bool _isEmbeddedInLongNumber(String text, int start, int end) {
    if (start > 0) {
      final b = text.codeUnitAt(start - 1);
      if (b >= 0x30 && b <= 0x39) return true;
    }
    if (end < text.length) {
      final a = text.codeUnitAt(end);
      if (a >= 0x30 && a <= 0x39) return true;
    }
    return false;
  }
}
