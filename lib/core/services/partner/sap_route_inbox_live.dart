import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

/// Abonnerer på endringer i [sap_route_inbox] for live badge på rute-planlegger.
class SapRouteInboxLive {
  SapRouteInboxLive._();

  static bool get _ok =>
      !SupabaseConfig.url.startsWith('YOUR_') &&
      !SupabaseConfig.anonKey.startsWith('YOUR_');

  static RealtimeChannel? subscribe({
    required String companyId,
    required VoidCallback onChanged,
  }) {
    if (!_ok) return null;

    final channel = Supabase.instance.client.channel(
      'sap_route_inbox_$companyId',
    );

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sap_route_inbox',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: companyId,
          ),
          callback: (_) => onChanged(),
        )
        .subscribe();

    return channel;
  }

  static void unsubscribe(RealtimeChannel? channel) {
    if (channel == null) return;
    Supabase.instance.client.removeChannel(channel);
  }
}
