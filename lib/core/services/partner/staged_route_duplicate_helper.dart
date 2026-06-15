import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../models/partner/partner_links.dart';

class StagedRouteDuplicateGroup {
  final String fingerprint;
  final List<PartnerRouteShare> shares;

  const StagedRouteDuplicateGroup({
    required this.fingerprint,
    required this.shares,
  });

  int get extraCount => shares.length - 1;

  PartnerRouteShare get keeper => StagedRouteDuplicateHelper.pickKeeper(shares);

  String get countLabel => StagedRouteDuplicateHelper.countLabel(shares.length);
}

/// Flere staged-ruter for samme MAVI på samme dag (ulike PDF-er).
class StagedRouteMaviDateGroup {
  final String maviCode;
  final DateTime routeDate;
  final List<PartnerRouteShare> shares;

  const StagedRouteMaviDateGroup({
    required this.maviCode,
    required this.routeDate,
    required this.shares,
  });

  int get extraCount => shares.length - 1;

  PartnerRouteShare get keeper => StagedRouteDuplicateHelper.pickKeeper(shares);

  String get countLabel => StagedRouteDuplicateHelper.countLabel(shares.length);
}

/// Finner 100 % like staged ruter (samme PDF-innhold).
abstract final class StagedRouteDuplicateHelper {
  static String fingerprintFromText(String? pdfSearchText) {
    final text = pdfSearchText?.trim();
    if (text != null && text.length >= 120) {
      return sha256.convert(utf8.encode(text)).toString();
    }
    return '';
  }

  static String fingerprintFromBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';
    return sha256.convert(bytes).toString();
  }

  static String fingerprint(PartnerRouteShare share) {
    final fromText = fingerprintFromText(share.pdfSearchText);
    if (fromText.isNotEmpty) return fromText;
    final identity = routeIdentityFromText(share.pdfSearchText);
    if (identity.isNotEmpty) {
      return sha256.convert(utf8.encode(identity)).toString();
    }
    final title = (share.title ?? '').trim().toLowerCase();
    final path = share.pdfStoragePath.trim().toLowerCase();
    return '$title|$path';
  }

  /// Unik ruteidentitet fra PDF (freight units, vekt, resource) — ikke MAVI+dag alene.
  static String routeIdentityFromText(String? pdfSearchText) {
    final raw = pdfSearchText?.trim();
    if (raw == null || raw.isEmpty) return '';
    final freight = <String>{};
    for (final m in RegExp(r'\b\d{8,12}\b').allMatches(raw)) {
      freight.add(m.group(0)!);
    }
    final sortedFreight = freight.toList()..sort();
    final weight = RegExp(
      r'Consumed\s+Weight[:\s]*([\d.]+)',
      caseSensitive: false,
    ).firstMatch(raw)?.group(1);
    final resource = RegExp(
      r'Resource\s+ID[:\s]*(\S+)',
      caseSensitive: false,
    ).firstMatch(raw)?.group(1)?.trim();
    if (sortedFreight.isEmpty && weight == null && resource == null) return '';
    return 'fu:${sortedFreight.join(",")}|w:${weight ?? ""}|r:${resource ?? ""}';
  }

  /// Finn eksisterende staged-rute med samme PDF-innhold (for import-dedup).
  static PartnerRouteShare? findDuplicateInStaged({
    required List<PartnerRouteShare> staged,
    String? pdfSearchText,
    List<int>? bytes,
    String? contentSha256,
  }) {
    final textFp = fingerprintFromText(pdfSearchText);
    if (textFp.isNotEmpty) {
      for (final s in staged) {
        if (fingerprint(s) == textFp) return s;
      }
    }
    final byteFp = bytes != null && bytes.isNotEmpty ? fingerprintFromBytes(bytes) : '';
    if (byteFp.isNotEmpty) {
      for (final s in staged) {
        if (fingerprint(s) == byteFp) return s;
      }
    }
    if (contentSha256 != null && contentSha256.trim().isNotEmpty) {
      for (final s in staged) {
        if (fingerprint(s) == contentSha256.trim()) return s;
      }
    }
    return null;
  }

  static List<StagedRouteDuplicateGroup> findGroups(List<PartnerRouteShare> staged) {
    final map = <String, List<PartnerRouteShare>>{};
    for (final s in staged) {
      map.putIfAbsent(fingerprint(s), () => []).add(s);
    }
    final groups = <StagedRouteDuplicateGroup>[];
    for (final e in map.entries) {
      if (e.value.length < 2) continue;
      groups.add(StagedRouteDuplicateGroup(fingerprint: e.key, shares: e.value));
    }
    groups.sort((a, b) => b.extraCount.compareTo(a.extraCount));
    return groups;
  }

  static int totalExtraDuplicates(List<StagedRouteDuplicateGroup> groups) {
    var n = 0;
    for (final g in groups) {
      n += g.extraCount;
    }
    return n;
  }

  static Set<String> allDuplicateIds(List<StagedRouteDuplicateGroup> groups) {
    final out = <String>{};
    for (final g in groups) {
      for (final s in g.shares) {
        if (s.id != g.keeper.id) out.add(s.id);
      }
    }
    return out;
  }

  static PartnerRouteShare pickKeeper(List<PartnerRouteShare> shares) {
    final sorted = [...shares]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final s in sorted) {
      if (s.shiftId != null && s.shiftId!.trim().isNotEmpty) return s;
    }
    return sorted.first;
  }

  static List<String> idsToRemove(List<StagedRouteDuplicateGroup> groups) {
    final remove = <String>[];
    for (final g in groups) {
      remove.addAll(idsToRemoveShares(g.shares));
    }
    return remove;
  }

  static List<String> idsToRemoveShares(List<PartnerRouteShare> shares) {
    if (shares.length < 2) return const [];
    final keeperId = pickKeeper(shares).id;
    return [
      for (final s in shares)
        if (s.id != keeperId) s.id,
    ];
  }

  static String countLabel(int n) => switch (n) {
        2 => 'Dobbelt',
        3 => 'Trippel',
        4 => 'Firedobbelt',
        _ => '${n}×',
      };

  static List<StagedRouteMaviDateGroup> findMaviDateGroups({
    required List<PartnerRouteShare> staged,
    required String? Function(PartnerRouteShare share) maviCodeOf,
    required DateTime Function(PartnerRouteShare share) routeDateOf,
  }) {
    final map = <String, List<PartnerRouteShare>>{};
    for (final s in staged) {
      final code = maviCodeOf(s);
      if (code == null || code.isEmpty) continue;
      final day = routeDateOf(s);
      final key = '${code.trim().toUpperCase()}|${day.year}-${day.month}-${day.day}';
      map.putIfAbsent(key, () => []).add(s);
    }
    final groups = <StagedRouteMaviDateGroup>[];
    for (final e in map.entries) {
      if (e.value.length < 2) continue;
      final parts = e.key.split('|');
      final code = parts.first;
      final dateParts = parts[1].split('-');
      groups.add(
        StagedRouteMaviDateGroup(
          maviCode: code,
          routeDate: DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
          ),
          shares: e.value,
        ),
      );
    }
    groups.sort((a, b) => b.extraCount.compareTo(a.extraCount));
    return groups;
  }
}
