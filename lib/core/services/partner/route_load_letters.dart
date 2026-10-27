import '../../../models/partner/partner_links.dart';
import 'route_pdf_text_service.dart';

/// Tildeler Last A/B/C når samme bil (eller partner) har 2+ ruter samme dag.
abstract final class RouteLoadLetters {
  /// Kun bokstaven (`A`, `B`, …) eller null hvis ikke multi-last.
  static String? letterFor(
    PartnerRouteShare current,
    List<PartnerRouteShare> candidates,
  ) {
    final group = groupFor(current, candidates);
    if (group.length < 2) return null;
    final letters = _lettersPreferringStowing(group);
    return letters[current.id];
  }

  /// F.eks. `Last A`, eller null.
  static String? badgeFor(
    PartnerRouteShare current,
    List<PartnerRouteShare> candidates,
  ) {
    final letter = letterFor(current, candidates);
    if (letter == null) return null;
    return 'Last $letter';
  }

  /// Når gruppen allerede er filtrert (f.eks. Auto masse med lokal dato).
  /// Rekkefølgen brukes til A/B/C når stowing-bokstav mangler.
  static String? letterInOrderedGroup(
    PartnerRouteShare current,
    List<PartnerRouteShare> group,
  ) {
    if (group.length < 2) return null;
    final letters = _lettersPreferringStowing(group);
    return letters[current.id];
  }

  static String? badgeInOrderedGroup(
    PartnerRouteShare current,
    List<PartnerRouteShare> group,
  ) {
    final letter = letterInOrderedGroup(current, group);
    if (letter == null) return null;
    return 'Last $letter';
  }

  /// shareId → `Last A` for alle multi-last i [routes].
  static Map<String, String> badgesForRoutes(List<PartnerRouteShare> routes) {
    final out = <String, String>{};
    final seen = <String>{};
    for (final r in routes) {
      final key = '${_groupKey(r)}|${_dayKey(r)}';
      if (!seen.add(key)) continue;
      final group = groupFor(r, routes);
      if (group.length < 2) continue;
      final letters = _lettersPreferringStowing(group);
      for (final e in letters.entries) {
        out[e.key] = 'Last ${e.value}';
      }
    }
    return out;
  }

  /// Samme bil/partner + samme kalenderdag, sortert for stabil A/B/C.
  static List<PartnerRouteShare> groupFor(
    PartnerRouteShare current,
    List<PartnerRouteShare> candidates,
  ) {
    final key = _groupKey(current);
    final day = _dayKey(current);
    final group = candidates
        .where((s) => _groupKey(s) == key && _dayKey(s) == day)
        .toList()
      ..sort(_compareForLetter);
    return group;
  }

  static String _groupKey(PartnerRouteShare s) {
    final vid = s.partnerVehicleId?.trim();
    if (vid != null && vid.isNotEmpty) return 'v:$vid';
    return 'p:${s.partnerId}';
  }

  static String _dayKey(PartnerRouteShare s) {
    final d = calendarDay(s);
    return '${d.year}-${d.month}-${d.day}';
  }

  static DateTime calendarDay(PartnerRouteShare s) {
    final start = s.routeStartAt?.toLocal();
    if (start != null) return DateTime(start.year, start.month, start.day);
    final d = s.shareDate.toLocal();
    return DateTime(d.year, d.month, d.day);
  }

  /// Trailing letter from stowing lane (`17B` → `B`, `1A` → `A`, `17` → null).
  static String? stowingLetter(PartnerRouteShare share) {
    final lane = RoutePdfTextService.parseStowingLaneFromNotes(share.notes) ??
        RoutePdfTextService.parseStowingLane(share.pdfSearchText ?? '');
    if (lane == null || lane.isEmpty) return null;
    final m = RegExp(r'([A-Z])$').firstMatch(lane);
    return m?.group(1);
  }

  static Map<String, String> _lettersPreferringStowing(
    List<PartnerRouteShare> group,
  ) {
    final byStowing = <String, String>{};
    final used = <String>{};
    var allDistinct = true;
    for (final s in group) {
      final letter = stowingLetter(s);
      if (letter == null || used.contains(letter)) {
        allDistinct = false;
        break;
      }
      used.add(letter);
      byStowing[s.id] = letter;
    }
    if (allDistinct && byStowing.length == group.length) {
      return byStowing;
    }
    final out = <String, String>{};
    for (var i = 0; i < group.length; i++) {
      out[group[i].id] = _indexToLetter(i);
    }
    return out;
  }

  static String _indexToLetter(int index) {
    if (index < 0) return 'A';
    if (index < 26) return String.fromCharCode(65 + index);
    return 'A${index - 25}';
  }

  static int _compareForLetter(PartnerRouteShare a, PartnerRouteShare b) {
    final aStart = a.routeStartAt?.millisecondsSinceEpoch ??
        a.shareDate.millisecondsSinceEpoch;
    final bStart = b.routeStartAt?.millisecondsSinceEpoch ??
        b.shareDate.millisecondsSinceEpoch;
    final c = aStart.compareTo(bStart);
    if (c != 0) return c;
    final laneA = RoutePdfTextService.parseStowingLaneFromNotes(a.notes) ?? '';
    final laneB = RoutePdfTextService.parseStowingLaneFromNotes(b.notes) ?? '';
    final lc = laneA.compareTo(laneB);
    if (lc != 0) return lc;
    return a.id.compareTo(b.id);
  }
}
