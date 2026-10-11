import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/partner/partner_service.dart';

void main() {
  test('SAP foreign-key errors become a short Norwegian reason', () {
    const raw = 'PostgrestException(message: insert or update on table '
        '"sap_route_inbox" violates foreign key constraint '
        '"sap_route_inbox_imported_route_share_id_fkey", code: 23503, '
        'details: Key is not present in table "partner_route_shares".)';
    expect(
      PartnerService.friendlySapFailure(raw),
      'Ruten ble ikke koblet til PDF-en. Prøv hent på nytt.',
    );
    expect(PartnerService.sapRejectIsStaleLink('MANUAL:$raw'), isTrue);
    expect(
      PartnerService.friendlySapFailure('Fant ikke MAVI-nummer i PDF'),
      'Fant ikke MAVI-nummer i PDF',
    );
  });
}
