import 'package:flutter_test/flutter_test.dart';
import 'package:driftpro/core/services/partner/fleet_analytics_service.dart';
import 'package:driftpro/models/partner/partner_links.dart';
import 'package:driftpro/screens/partners/owner_portal/owner_portal_route_history.dart';

PartnerRouteShare _share({
  required DateTime day,
  int? customers,
  String notes = '',
}) {
  return PartnerRouteShare(
    id: 'r-${day.toIso8601String()}',
    partnerId: 'p1',
    companyId: 'c1',
    pdfStoragePath: 'pdfs/x.pdf',
    shareDate: day,
    notes: notes,
    customerCount: customers,
    dispatchStatus: 'sent',
    createdAt: day,
  );
}

void main() {
  test('ownerRouteCustomerCount prefers stored then notes', () {
    expect(
      ownerRouteCustomerCount(_share(day: DateTime(2026, 10, 1), customers: 8)),
      8,
    );
    expect(
      ownerRouteCustomerCount(
        _share(day: DateTime(2026, 10, 1), notes: 'FO: 1\nKunder: 11\n'),
      ),
      11,
    );
    expect(
      ownerRouteCustomerCount(_share(day: DateTime(2026, 10, 1))),
      0,
    );
  });

  test('ownerHistoryAnchorForPeriod jumps to latest non-empty period', () {
    final past = [
      _share(day: DateTime(2026, 10, 28), customers: 8),
      _share(day: DateTime(2026, 10, 23), customers: 12),
    ];
    final now = DateTime(2026, 11, 2);

    final weekAnchor = ownerHistoryAnchorForPeriod(
      pastRoutes: past,
      period: FleetCalendarPeriod.week,
      now: now,
    );
    expect(weekAnchor, DateTime(2026, 10, 28));

    final monthAnchor = ownerHistoryAnchorForPeriod(
      pastRoutes: past,
      period: FleetCalendarPeriod.month,
      now: now,
    );
    expect(monthAnchor, DateTime(2026, 10, 28));

    final filtered = filterOwnerHistoryRoutes(
      partnerId: 'p1',
      pastRoutes: past,
      period: FleetCalendarPeriod.week,
      anchor: weekAnchor,
    );
    expect(filtered.map((r) => r.shareDate.day).toList(), [28]);
  });
}
