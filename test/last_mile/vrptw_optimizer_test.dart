import 'package:driftpro/last_mile/models/lm_order.dart';
import 'package:driftpro/last_mile/services/vrptw_optimizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VRPTW fordeler ordre på bil med kapasitet', () {
    final orders = [
      LmOrder(
        id: 'a',
        companyId: 'c',
        source: 'test',
        customerName: 'A',
        addressLine: 'x',
        lat: 59.95,
        lng: 10.75,
        weightKg: 30,
        createdAt: DateTime.now(),
      ),
      LmOrder(
        id: 'b',
        companyId: 'c',
        source: 'test',
        customerName: 'B',
        addressLine: 'y',
        lat: 59.96,
        lng: 10.80,
        weightKg: 40,
        createdAt: DateTime.now(),
      ),
    ];
    final vehicles = [
      const VrptwVehicle(vehicleId: 'v1', partnerId: 'p1', payloadKg: 500),
    ];
    final plans = VrptwOptimizer.optimize(
      orders: orders,
      vehicles: vehicles,
      routeDate: DateTime(2026, 5, 24),
    );
    expect(plans.length, 1);
    expect(plans.first.orderIds.length, 2);
  });
}
