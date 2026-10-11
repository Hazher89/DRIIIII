import 'package:driftpro/core/permissions/partner_portal_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing portal keys stay on and explicit false hides the page', () {
    expect(PartnerPortalPages.isOn(const {}, PartnerPortalPages.ruter), isTrue);
    expect(PartnerPortalPages.isOn(null, PartnerPortalPages.avvik), isTrue);
    expect(
      PartnerPortalPages.isOn(
        const {'ruter': false, 'avvik': true},
        PartnerPortalPages.ruter,
      ),
      isFalse,
    );
    expect(
      PartnerPortalPages.isOn(const {'mer': 'false'}, PartnerPortalPages.mer),
      isFalse,
    );
  });
}
