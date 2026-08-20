import 'package:flutter/material.dart';

import '../../../../models/partner/route_notify_prefs.dart';

/// Avhukinger for App / SMS / E-post ved ruteutsendelse.
class RouteNotifyChannelToggles extends StatelessWidget {
  const RouteNotifyChannelToggles({
    super.key,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  final RouteNotifyPrefs value;
  final ValueChanged<RouteNotifyPrefs> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    Widget chip({
      required String label,
      required IconData icon,
      required bool selected,
      required ValueChanged<bool> onTap,
    }) {
      return FilterChip(
        selected: selected,
        showCheckmark: false,
        avatar: Icon(icon, size: dense ? 16 : 18),
        label: Text(label, style: TextStyle(fontSize: dense ? 12 : 13, fontWeight: FontWeight.w700)),
        onSelected: onTap,
        visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Varsel:',
          style: TextStyle(
            fontSize: dense ? 12 : 13,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade800,
          ),
        ),
        chip(
          label: 'App',
          icon: Icons.phone_iphone_outlined,
          selected: value.app,
          onTap: (v) => onChanged(value.copyWith(app: v)),
        ),
        chip(
          label: 'SMS',
          icon: Icons.sms_outlined,
          selected: value.sms,
          onTap: (v) => onChanged(value.copyWith(sms: v)),
        ),
        chip(
          label: 'E-post',
          icon: Icons.email_outlined,
          selected: value.email,
          onTap: (v) => onChanged(value.copyWith(email: v)),
        ),
      ],
    );
  }
}

/// Kompakt badge for leveringsstatus.
class RouteNotifyDeliveryBadge extends StatelessWidget {
  const RouteNotifyDeliveryBadge({
    super.key,
    required this.delivery,
    this.driverAppReady,
  });

  final RouteNotifyDelivery? delivery;
  final bool? driverAppReady;

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final appReady = driverAppReady ?? d?.driverHasAppToken ?? false;
    final label = d?.badgeLabel ?? (appReady ? 'App-klar' : 'Ingen app-token');
    final attention = d?.needsAttention == true;
    final color = attention
        ? Colors.orange.shade800
        : (d?.dispatchStatus == 'sent' ? Colors.green.shade800 : Colors.blueGrey.shade700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}
