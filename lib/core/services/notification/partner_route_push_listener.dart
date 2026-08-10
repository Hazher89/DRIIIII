import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/driftpro_client.dart';
import 'push_notification_service.dart';
import '../native_permissions_service.dart';

/// Realtime-fallback: vis lokalt varsel når ny rute sendes mens appen kjører.
abstract final class PartnerRoutePushListener {
  static RealtimeChannel? _channel;
  static String? _partnerId;
  static bool _askedNotifications = false;

  static void start({
    required String partnerId,
    required String? partnerVehicleId,
  }) {
    if (!DriftProClient.isMobile || partnerVehicleId == null) return;
    stop();
    _partnerId = partnerId;
    _askedNotifications = false;

    // Varsler trengs for rute-tildeling — be kun når sjåførportal brukes.
    unawaited(_ensureNotificationsOnce());

    final client = Supabase.instance.client;
    _channel = client
        .channel('driver_routes_$partnerVehicleId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'partner_route_shares',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'partner_vehicle_id',
            value: partnerVehicleId,
          ),
          callback: (payload) => _maybeNotify(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'partner_route_shares',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'partner_vehicle_id',
            value: partnerVehicleId,
          ),
          callback: (payload) => _maybeNotify(payload.newRecord),
        )
        .subscribe();
  }

  static Future<void> _ensureNotificationsOnce() async {
    if (_askedNotifications) return;
    _askedNotifications = true;
    await NativePermissionsService.ensureNotifications();
  }

  static void stop() {
    _partnerId = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      Supabase.instance.client.removeChannel(ch);
    }
  }

  static void _maybeNotify(Map<String, dynamic> row) {
    final pid = _partnerId;
    if (pid != null && row['partner_id']?.toString() != pid) return;
    if (row['dispatch_status']?.toString() != 'sent') return;
    final title = row['title']?.toString();
    unawaited(PushNotificationService.showRouteAssigned(
      title: 'Ny rute i DriftPro',
      body: title != null && title.isNotEmpty
          ? 'Ny rute: $title — åpne for PDF og godkjenning.'
          : 'En ny rute er klar — åpne appen for PDF og godkjenning.',
      routeShareId: row['id']?.toString(),
    ));
  }
}
