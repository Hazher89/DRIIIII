import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_links.dart';
import '../../../models/partner/partner_summary_meta.dart';

class PartnerSummaryMatch {
  const PartnerSummaryMatch({
    required this.partner,
    required this.score,
    required this.reason,
  });

  final Partner partner;
  final int score;
  final String reason;
}

/// Matcher oppsummering til riktig bedrift (navn + MAVI-nummer).
class PartnerSummaryMatcher {
  PartnerSummaryMatcher._();

  static String normalizeName(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-ZÆØÅ0-9]'), '');

  static PartnerSummaryMatch? bestMatch({
    required PartnerSummaryMeta summary,
    required List<Partner> partners,
    required Map<String, List<PartnerVehicle>> vehiclesByPartner,
  }) {
    PartnerSummaryMatch? best;
    for (final partner in partners) {
      final score = _score(partner, summary, vehiclesByPartner[partner.id] ?? const []);
      if (score <= 0) continue;
      final reason = _reason(partner, summary, vehiclesByPartner[partner.id] ?? const []);
      if (best == null || score > best.score) {
        best = PartnerSummaryMatch(partner: partner, score: score, reason: reason);
      }
    }
    return best;
  }

  static int _score(Partner partner, PartnerSummaryMeta summary, List<PartnerVehicle> vehicles) {
    var score = 0;
    final partnerKey = normalizeName(partner.name);
    final summaryKey = normalizeName(summary.companyNameRaw);
    if (partnerKey.isNotEmpty && summaryKey.isNotEmpty) {
      if (partnerKey == summaryKey) {
        score += 100;
      } else if (partnerKey.contains(summaryKey) || summaryKey.contains(partnerKey)) {
        score += 70;
      } else {
        final partnerTokens = partnerKey.replaceAll('AS', '');
        final summaryTokens = summaryKey.replaceAll('AS', '');
        if (partnerTokens.contains(summaryTokens) || summaryTokens.contains(partnerTokens)) {
          score += 45;
        }
      }
    }

    if (summary.vehicles.isEmpty) return score;

    final partnerUnits = vehicles
        .map((v) => v.unitCode.trim().toUpperCase())
        .where((u) => u.isNotEmpty)
        .toSet();
    var maviHits = 0;
    for (final line in summary.vehicles) {
      if (partnerUnits.contains(line.unitCode.toUpperCase())) maviHits++;
    }
    if (maviHits > 0) {
      score += 40 * maviHits;
      if (maviHits == summary.vehicles.length) score += 30;
    }
    return score;
  }

  static String _reason(Partner partner, PartnerSummaryMeta summary, List<PartnerVehicle> vehicles) {
    final parts = <String>['Navn: ${partner.name}'];
    final units = vehicles.map((v) => v.unitCode).where((u) => u.isNotEmpty).take(4).join(', ');
    if (units.isNotEmpty) parts.add('MAVI: $units');
    if (summary.companyNameRaw.isNotEmpty) {
      parts.add('PDF: ${summary.companyNameRaw}');
    }
    return parts.join(' · ');
  }
}
