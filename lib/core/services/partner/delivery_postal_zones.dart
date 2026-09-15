/// MAVI leveringsområder (Norge) — postnummer fra–til inklusive, med sone 1–4.
///
/// Kilde: Prices_Mavi / leveringssoner (Excel). Brukes av CCC-chat og
/// intern Spør DriftPro, slik at «leverer dere til XXXX?» får fasitsvar.
abstract final class DeliveryPostalZones {
  /// Inklusive intervaller (fra, til, sone).
  static const ranges = <({int from, int to, int zone})>[
    (from: 1, to: 2283, zone: 1),
    (from: 2711, to: 2770, zone: 1),
    (from: 3001, to: 3077, zone: 1),
    (from: 3300, to: 3342, zone: 4),
    (from: 3350, to: 3359, zone: 1),
    (from: 3360, to: 3521, zone: 4),
    (from: 3522, to: 3528, zone: 1),
    (from: 3529, to: 3533, zone: 4),
    (from: 3534, to: 3539, zone: 1),
    (from: 3601, to: 3625, zone: 1),
    (from: 3626, to: 3648, zone: 4),
  ];

  static String pad(int code) => code.toString().padLeft(4, '0');

  static int? parseCode(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 4) return null;
    return int.tryParse(digits);
  }

  /// Første treff: sone for postnummer, ellers null (utenfor leveringsområde).
  static int? zoneFor(String postalCode) {
    final n = parseCode(postalCode);
    if (n == null) return null;
    for (final r in ranges) {
      if (n >= r.from && n <= r.to) return r.zone;
    }
    return null;
  }

  static bool deliversTo(String postalCode) => zoneFor(postalCode) != null;

  /// Finn 4-sifrede postnummer i fri tekst (unngår lange tall).
  static List<String> extractCodes(String text) {
    final found = <String>{};
    for (final m in RegExp(r'\b(\d{4})\b').allMatches(text)) {
      final code = m.group(1)!;
      if (_embeddedInLongerNumber(text, m.start, m.end)) continue;
      found.add(code);
    }
    return found.toList()..sort();
  }

  static bool _embeddedInLongerNumber(String text, int start, int end) {
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

  static bool looksLikeDeliveryQuestion(String query) {
    final q = query.toLowerCase();
    final hasCode = extractCodes(query).isNotEmpty;
    final keywords = [
      'postnummer',
      'postkode',
      'post nr',
      'leverer',
      'levering',
      'leveringsområde',
      'leveringsomrade',
      'dekker',
      'sone',
      'zone',
      'kjører til',
      'kjorer til',
      'utkjøring',
      'utkjøring',
      'utkjoring',
    ];
    final hitKw = keywords.any(q.contains);
    // «Leverer dere til 3015?» / bare «3015»
    if (hasCode && (hitKw || q.trim().length <= 12 || q.contains('til '))) {
      return true;
    }
    if (hitKw &&
        (q.contains('hvilke') ||
            q.contains('hvor') ||
            q.contains('område') ||
            q.contains('omrade') ||
            q.contains('liste') ||
            q.contains('oversikt'))) {
      return true;
    }
    return false;
  }

  /// Fasitsvar for CCC eller ansatte. [audience]: `ccc` | `internal`.
  static String? tryAnswer(String query, {String audience = 'ccc'}) {
    if (!looksLikeDeliveryQuestion(query)) return null;

    final codes = extractCodes(query);
    if (codes.isNotEmpty) {
      final lines = <String>[];
      for (final code in codes) {
        final zone = zoneFor(code);
        if (zone != null) {
          lines.add(
            'Ja — vi leverer til $code (sone $zone).',
          );
        } else {
          lines.add(
            'Nei — $code er utenfor våre registrerte leveringsområder.',
          );
        }
      }
      if (codes.length == 1) {
        final code = codes.first;
        final zone = zoneFor(code);
        if (zone != null) {
          return audience == 'internal'
              ? 'Ja, MAVI leverer til postnummer $code (leveringssone $zone).'
              : 'Ja, vi leverer til postnummer $code (sone $zone).';
        }
        return audience == 'internal'
            ? 'Nei — postnummer $code ligger utenfor MAVI sine registrerte leveringsområder '
                '(fra–til i soneoversikten).'
            : 'Nei — postnummer $code ligger utenfor våre leveringsområder. '
                'Velg annen leveringsadresse eller sjekk om kunden kan ta imot innenfor dekning.';
      }
      return '${lines.join('\n')}\n\n'
          'Kun postnummer innenfor de registrerte fra–til-intervallene er dekket.';
    }

    // Oversikt uten konkret postnummer
    return overviewAnswer(audience: audience);
  }

  static String overviewAnswer({String audience = 'ccc'}) {
    final buf = StringBuffer();
    if (audience == 'internal') {
      buf.writeln(
        'MAVI leverer til disse norske postnummer-intervallene (fra og med – til og med):',
      );
    } else {
      buf.writeln(
        'Vi leverer til disse postnummer-intervallene i Norge (fra og med – til og med):',
      );
    }
    buf.writeln();
    for (final r in ranges) {
      buf.writeln('• ${pad(r.from)}–${pad(r.to)} → sone ${r.zone}');
    }
    buf.writeln();
    buf.writeln(
      'Spør med et konkret postnummer (f.eks. «leverer dere til 3015?») '
      'for ja/nei + sone.',
    );
    return buf.toString().trim();
  }

  /// Kunnskapsbit til begge chatter.
  static String knowledgeBody({required bool forCcc}) {
    final who = forCcc ? 'CCC/butikk' : 'ansatte';
    return '''
Leveringsområder Norge (MAVI) — fasit for $who.

Regel: Hvis kundens postnummer ligger innenfor ett av intervallene under
(fra og med – til og med), leverer vi dit. Ellers gjør vi det ikke
(ifølge denne soneoversikten).

Intervaller:
${ranges.map((r) => '• ${pad(r.from)}–${pad(r.to)} = sone ${r.zone}').join('\n')}

Eksempel: 3015 → ja, sone 1. 9990 → nei (utenfor).
Svar kort med ja/nei + sone når noen spør om et konkret postnummer.
''';
  }
}
