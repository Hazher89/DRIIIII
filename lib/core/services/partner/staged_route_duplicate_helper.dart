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
}

/// Finner 100 % like staged ruter (samme PDF-innhold).
abstract final class StagedRouteDuplicateHelper {
  static String fingerprint(PartnerRouteShare share) {
    final text = share.pdfSearchText?.trim();
    if (text != null && text.length >= 120) {
      return sha256.convert(utf8.encode(text)).toString();
    }
    final title = (share.title ?? '').trim().toLowerCase();
    final path = share.pdfStoragePath.trim().toLowerCase();
    return '$title|$path';
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
      final keeperId = g.keeper.id;
      for (final s in g.shares) {
        if (s.id != keeperId) remove.add(s.id);
      }
    }
    return remove;
  }
}
