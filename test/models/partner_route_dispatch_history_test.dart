import 'package:flutter_test/flutter_test.dart';

import 'package:driftpro/models/partner/partner_route_dispatch_history.dart';

void main() {
  test('PartnerRouteDispatchHistoryRow.fromJson maps history fields', () {
    final row = PartnerRouteDispatchHistoryRow.fromJson({
      'share_id': 's1',
      'partner_id': 'p1',
      'partner_name': 'Partner AS',
      'unit_code': 'MAVI12',
      'registration_number': 'AB12345',
      'title': 'Rute',
      'share_date': '2026-08-20',
      'dispatch_status': 'sent',
      'shift_name': 'Oslo',
      'route_start_at': '2026-08-20T06:00:00Z',
      'sent_at': '2026-08-19T14:30:00Z',
      'sent_by': 'u1',
      'sent_by_name': 'Karwan',
      'ack_status': 'accepted',
      'ack_at': '2026-08-19T15:00:00Z',
      'pdf_opened_at': '2026-08-19T15:05:00Z',
      'pdf_opened_by': 'u2',
      'pdf_opened_by_name': 'Sjåfør',
      'pdf_open_count': 2,
      'notify_channels': ['app', 'sms'],
      'customer_count': 40,
    });

    expect(row.shareId, 's1');
    expect(row.maviLabel, 'MAVI12');
    expect(row.wasNotified, isTrue);
    expect(row.pdfWasOpened, isTrue);
    expect(row.pdfOpenCount, 2);
    expect(row.sentByName, 'Karwan');
    expect(row.notifyChannels, ['app', 'sms']);
  });
}
