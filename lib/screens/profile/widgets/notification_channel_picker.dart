import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/notification_channel.dart';

/// Velg SMS / e-post / begge / av for én varseltype.
class NotificationChannelPicker extends StatelessWidget {
  const NotificationChannelPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final NotificationChannel value;
  final ValueChanged<NotificationChannel> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final options = NotificationChannel.values;
    if (compact) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: options.map((ch) {
          final selected = ch == value;
          return ChoiceChip(
            label: Text(ch.shortLabel, style: const TextStyle(fontSize: 12)),
            selected: selected,
            onSelected: (_) => onChanged(ch),
            selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
          );
        }).toList(),
      );
    }

    return SegmentedButton<NotificationChannel>(
      segments: options
          .map(
            (ch) => ButtonSegment(
              value: ch,
              label: Text(ch.shortLabel, style: const TextStyle(fontSize: 11)),
              icon: Icon(_icon(ch), size: 16),
            ),
          )
          .toList(),
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  IconData _icon(NotificationChannel ch) {
    switch (ch) {
      case NotificationChannel.sms:
        return Icons.sms_outlined;
      case NotificationChannel.email:
        return Icons.email_outlined;
      case NotificationChannel.both:
        return Icons.notifications_active_outlined;
      case NotificationChannel.none:
        return Icons.notifications_off_outlined;
    }
  }
}

class NotificationChannelTile extends StatelessWidget {
  const NotificationChannelTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final NotificationChannel value;
  final ValueChanged<NotificationChannel> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
          const SizedBox(height: 8),
          NotificationChannelPicker(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
