import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/services/partner/partner_search.dart';
import 'package:driftpro/models/partner/partner.dart';
import 'package:driftpro/models/partner/partner_links.dart';

void main() {
  Partner partner(String id, String name) => Partner(
        id: id,
        companyId: 'c1',
        name: name,
        createdAt: DateTime(2026),
      );

  PartnerVehicle vehicle({
    required String id,
    required String partnerId,
    required String unitCode,
    String registrationNumber = '',
  }) =>
      PartnerVehicle(
        id: id,
        companyId: 'c1',
        partnerId: partnerId,
        unitCode: unitCode,
        registrationNumber: registrationNumber,
        createdAt: DateTime(2026),
      );

  test('MAVI M0068 finds partner with NO_O_M0068', () {
    final p = partner('p1', 'Test AS');
    final v = vehicle(
      id: 'v1',
      partnerId: 'p1',
      unitCode: 'NO_O_M0068',
      registrationNumber: 'AB12345',
    );
    final hits = PartnerSearch.filterAll(
      partners: [p],
      vehiclesByPartnerId: {
        'p1': [v],
      },
      query: 'M0068',
    );
    expect(hits, hasLength(1));
    expect(hits.first.partner.id, 'p1');
    expect(hits.first.primaryMatchHint, contains('MAVI'));
  });

  test('short MAVI M68 matches padded unit', () {
    final p = partner('p1', 'Test AS');
    final hits = PartnerSearch.filterAll(
      partners: [p],
      vehiclesByPartnerId: {
        'p1': [
          vehicle(id: 'v1', partnerId: 'p1', unitCode: 'NO_O_M0068'),
        ],
      },
      query: 'M68',
    );
    expect(hits, hasLength(1));
  });

  test('name-only still works without vehicles', () {
    final p = partner('p1', 'Nord Logistikk');
    final hits = PartnerSearch.filterAll(
      partners: [p],
      vehiclesByPartnerId: const {},
      query: 'nord',
    );
    expect(hits, hasLength(1));
  });
}
