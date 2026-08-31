import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/driftpro_client.dart';
import 'push_notification_service.dart';
import '../native_permissions_service.dart';

  /// Realtime + lokal push når rute tildeles sjåfør, bil-eier eller ansatt.
abstract final class PartnerRoutePushListener {
  static RealtimeChannel? _channel;
  static String? _partnerId;
  static Set<String>? _allowedVehicleIds;
  static bool _askedNotifications = false;

  /// [partnerVehicleId]: sjåfør — kun den bilen. Null: eier/ansatt — partner scope.
  /// [allowedVehicleIds]: ansatt — kun valgte biler (tom = ingen varsler).
  static void start({
    required String partnerId,
    String? partnerVehicleId,
    Set<String>? allowedVehicleIds,
  }) {
    if (!DriftProClient.isMobile) return;
    stop();
    _partnerId = partnerId;
    _allowedVehicleIds = allowedVehicleIds;
    _askedNotifications = false;

    unawaited(_ensureNotificationsOnce());

    final client = Supabase.instance.client;
    final channelName = partnerVehicleId != null
        ? 'driver_routes_$partnerVehicleId'
        : 'owner_routes_$partnerId';

    var channel = client.channel(channelName);

    if (partnerVehicleId != null) {
      channel = channel
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
          );
    } else {
      channel = channel
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'partner_route_shares',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'partner_id',
              value: partnerId,
            ),
            callback: (payload) => _maybeNotify(payload.newRecord),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'partner_route_shares',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'partner_id',
              value: partnerId,
            ),
            callback: (payload) => _maybeNotify(payload.newRecord),
          );
    }

    _channel = channel.subscribe();
  }

  static Future<void> _ensureNotificationsOnce() async {
    if (_askedNotifications) return;
    _askedNotifications = true;
    await NativePermissionsService.ensureNotifications();
  }

  static void stop() {
    _partnerId = null;
    _allowedVehicleIds = null;
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
    final vehicleId = row['partner_vehicle_id']?.toString();
    final allowed = _allowedVehicleIds;
    if (allowed != null) {
      if (vehicleId == null || !allowed.contains(vehicleId)) return;
    }
    final title = row['title']?.toString();
    unawaited(PushNotificationService.showRouteAssigned(
      title: 'Ny rute i DriftPro',
      body: title != null && title.isNotEmpty
          ? 'Ny rute: $title — åpne for å se og akseptere.'
          : 'En ny rute er klar — åpne appen for å se og akseptere.',
      routeShareId: row['id']?.toString(),
    ));
  }
}
