import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/services/partner/vehicle_inspection_pdf.dart';
import 'package:driftpro/models/partner/partner.dart';
import 'package:driftpro/models/partner/vehicle_inspection.dart';

void main() {
  final partner = Partner(
    id: 'p1',
    companyId: 'c1',
    name: 'Test Transport AS',
    tradeName: 'Test Transport',
    orgNumber: '123456789',
    ownerName: 'Ola Nordmann',
    createdAt: DateTime(2026, 1, 1),
  );

  final inspection = PartnerVehicleInspection(
    id: 'abcdef12-3456-7890-abcd-ef1234567890',
    partnerId: 'p1',
    companyId: 'c1',
    registrationNumber: 'AB12345',
    unitCode: 'NO_MAVI_1',
    inspectedAt: DateTime(2026, 7, 21, 14, 30),
    inspectedByName: 'Karwan Lian',
    checklist: {
      'repp': 'ok',
      'lastestopp': 'avvik',
      'dekk_foran_mm': '2.5',
      'dekk_bak_mm': '4.0',
      'bremser': 'ok',
      'lys': 'ok',
      'refleks': 'not_checked',
      'spennreim': 'ok',
      'lofteinnretning': 'ok',
      'karosseri': 'ok',
      'annet': 'Sprekk i repp',
    },
    hasDeviation: true,
    deviationNotes: 'Repp skadet, dekk foran under 3 mm',
    followUpDueAt: DateTime(2026, 8, 4),
    nextInspectionAt: DateTime(2026, 10, 21),
    createdAt: DateTime(2026, 7, 21, 14, 30),
  );

  test('fileNameFor includes plate and stamp', () {
    final name = VehicleInspectionPdf.fileNameFor(inspection);
    expect(name, contains('Bilkontroll_'));
    expect(name, contains('AB12345'));
    expect(name, contains('20260721_1430'));
  });

  test('generate produces non-empty PDF bytes', () async {
    final bytes = await VehicleInspectionPdf.generate(
      inspection: inspection,
      partner: partner,
      inspectorName: 'Karwan Lian',
    );
    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
