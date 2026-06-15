import 'package:driftpro/core/services/partner/staged_route_duplicate_helper.dart';
import 'package:driftpro/models/partner/partner_links.dart';
import 'package:flutter_test/flutter_test.dart';

PartnerRouteShare _share({
  required String id,
  String? pdfSearchText,
  String title = 'Rute NO_O_M0024',
}) {
  return PartnerRouteShare(
    id: id,
    partnerId: 'p1',
    companyId: 'c1',
    title: title,
    pdfStoragePath: '/routes/$id.pdf',
    shareDate: DateTime(2026, 6, 14),
    pdfSearchText: pdfSearchText,
    createdAt: DateTime(2026, 6, 14),
    dispatchStatus: 'staged',
  );
}

void main() {
  group('routeIdentityFromText', () {
    test('skiller ulike freight units for samme MAVI', () {
      final a = StagedRouteDuplicateHelper.routeIdentityFromText(
        'Resource ID NO_O_M0024 Consumed Weight 419.53 KG Freight Unit 4106066284',
      );
      final b = StagedRouteDuplicateHelper.routeIdentityFromText(
        'Resource ID NO_O_M0024 Consumed Weight 394.81 KG Freight Unit 4106065367, 4106065368',
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('findGroups', () {
    test('grupperer ikke ulike M24-ruter samme dag', () {
      final staged = [
        _share(
          id: 'a',
          pdfSearchText:
              'Resource ID NO_O_M0024 Consumed Weight 419.53 KG 4106066284 Emma Sør',
        ),
        _share(
          id: 'b',
          pdfSearchText:
              'Resource ID NO_O_M0024 Consumed Weight 394.81 KG 4106065367 4106065368 Thomas',
        ),
      ];
      expect(StagedRouteDuplicateHelper.findGroups(staged), isEmpty);
    });

    test('finner identisk PDF-innhold', () {
      final text = 'A' * 150;
      final staged = [
        _share(id: 'a', pdfSearchText: text),
        _share(id: 'b', pdfSearchText: text),
      ];
      final groups = StagedRouteDuplicateHelper.findGroups(staged);
      expect(groups, hasLength(1));
      expect(groups.first.extraCount, 1);
    });
  });

  group('findMaviDateGroups', () {
    test('flere ruter samme MAVI samme dag er ikke duplikat-grupper i UI', () {
      final staged = [
        _share(
          id: 'a',
          pdfSearchText: 'Resource ID NO_O_M0024 4106066284 weight 419',
        ),
        _share(
          id: 'b',
          pdfSearchText: 'Resource ID NO_O_M0024 4106065367 weight 394',
        ),
      ];
      final groups = StagedRouteDuplicateHelper.findMaviDateGroups(
        staged: staged,
        maviCodeOf: (s) => 'NO_O_M0024',
        routeDateOf: (_) => DateTime(2026, 6, 14),
      );
      expect(groups, hasLength(1));
      expect(groups.first.shares, hasLength(2));
      expect(StagedRouteDuplicateHelper.findGroups(staged), isEmpty);
    });
  });
}
