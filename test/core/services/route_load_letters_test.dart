import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/partner/route_load_letters.dart';
import 'package:driftpro/models/partner/partner_links.dart';

PartnerRouteShare _share({
  required String id,
  String partnerId = 'p1',
  String? vehicleId,
  DateTime? start,
  DateTime? shareDate,
  String? notes,
  String? pdfSearchText,
}) {
  final day = shareDate ?? DateTime(2026, 10, 28);
  return PartnerRouteShare(
    id: id,
    partnerId: partnerId,
    companyId: 'c1',
    title: 'Rute $id',
    pdfStoragePath: 'routes/$id.pdf',
    shareDate: day,
    partnerVehicleId: vehicleId,
    routeStartAt: start,
    notes: notes,
    pdfSearchText: pdfSearchText,
    createdAt: day,
  );
}

void main() {
  test('én rute → ingen Last-badge', () {
    final a = _share(
      id: 'a',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 7),
    );
    expect(RouteLoadLetters.badgeFor(a, [a]), isNull);
    expect(RouteLoadLetters.badgesForRoutes([a]), isEmpty);
  });

  test('to ruter samme bil+dag → Last A/B etter starttid', () {
    final a = _share(
      id: 'a',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 7),
    );
    final b = _share(
      id: 'b',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 8),
    );
    expect(RouteLoadLetters.badgeFor(a, [a, b]), 'Last A');
    expect(RouteLoadLetters.badgeFor(b, [a, b]), 'Last B');
    expect(
      RouteLoadLetters.badgesForRoutes([a, b]),
      {'a': 'Last A', 'b': 'Last B'},
    );
  });

  test('ulike dager → ingen badge', () {
    final a = _share(
      id: 'a',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 7),
    );
    final b = _share(
      id: 'b',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 29, 7),
    );
    expect(RouteLoadLetters.badgeFor(a, [a, b]), isNull);
    expect(RouteLoadLetters.badgeFor(b, [a, b]), isNull);
  });

  test('ulike biler samme dag → ingen badge', () {
    final a = _share(
      id: 'a',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 7),
    );
    final b = _share(
      id: 'b',
      vehicleId: 'v2',
      start: DateTime(2026, 10, 28, 8),
    );
    expect(RouteLoadLetters.badgeFor(a, [a, b]), isNull);
  });

  test('stowing-bokstav prioriteres når den skiller lastene', () {
    final a = _share(
      id: 'a',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 8),
      notes: 'Stowing Lane: 17B',
    );
    final b = _share(
      id: 'b',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 7),
      notes: 'Stowing Lane: 17A',
    );
    expect(RouteLoadLetters.letterFor(a, [a, b]), 'B');
    expect(RouteLoadLetters.letterFor(b, [a, b]), 'A');
    expect(RouteLoadLetters.badgeFor(a, [a, b]), 'Last B');
    expect(RouteLoadLetters.badgeFor(b, [a, b]), 'Last A');
  });

  test('stowing uten bokstav faller tilbake til A/B etter start', () {
    final a = _share(
      id: 'a',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 7),
      notes: 'Stowing Lane: 17',
    );
    final b = _share(
      id: 'b',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 9),
      notes: 'Stowing Lane: 18',
    );
    expect(RouteLoadLetters.badgeFor(a, [a, b]), 'Last A');
    expect(RouteLoadLetters.badgeFor(b, [a, b]), 'Last B');
  });

  test('letterInOrderedGroup respekterer gitt rekkefølge', () {
    final late = _share(
      id: 'late',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 10),
    );
    final early = _share(
      id: 'early',
      vehicleId: 'v1',
      start: DateTime(2026, 10, 28, 6),
    );
    // Explicit order: late first → Last A
    expect(
      RouteLoadLetters.badgeInOrderedGroup(late, [late, early]),
      'Last A',
    );
    expect(
      RouteLoadLetters.badgeInOrderedGroup(early, [late, early]),
      'Last B',
    );
  });
}
