import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/core/services/notification/push_navigation_target.dart';

void main() {
  test('parses partner route push', () {
    final t = PushNavigationTarget.fromMap({
      'type': 'partner_route',
      'route_share_id': 'abc-123',
    });
    expect(t?.kind, PushNavKind.partnerRoute);
    expect(t?.id, 'abc-123');
    expect(t?.portalTab, 'ruter');
  });

  test('parses partner deduction push', () {
    final t = PushNavigationTarget.fromMap({
      'type': 'partner_deduction',
      'case_id': 'case-1',
    });
    expect(t?.kind, PushNavKind.partnerDeduction);
    expect(t?.maviPath, '/partners?tab=bot-trekk');
  });

  test('parses HMS ticket reference', () {
    final t = PushNavigationTarget.fromMap({
      'reference_type': 'tickets',
      'reference_id': 't-1',
      'category': 'hms_ticket_new',
    });
    expect(t?.kind, PushNavKind.hmsTicket);
    expect(t?.maviPath, '/avvik');
  });
}
