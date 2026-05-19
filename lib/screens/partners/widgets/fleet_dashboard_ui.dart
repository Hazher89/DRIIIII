import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Kompakt vs romslig listevisning.
enum FleetListDensity { compact, comfortable }

enum FleetSortMode { unitCode, partner, status }

/// Filter på status i live-oversikt.
enum FleetStatusFilter { all, harRute, ledig, fri, gittBort }

extension FleetStatusFilterX on FleetStatusFilter {
  String get label {
    switch (this) {
      case FleetStatusFilter.all:
        return 'Alle';
      case FleetStatusFilter.harRute:
        return 'Har rute';
      case FleetStatusFilter.ledig:
        return 'Ledig';
      case FleetStatusFilter.fri:
        return 'Fri';
      case FleetStatusFilter.gittBort:
        return 'Gitt bort';
    }
  }

  String? get statusValue {
    switch (this) {
      case FleetStatusFilter.all:
        return null;
      case FleetStatusFilter.harRute:
        return 'har_rute';
      case FleetStatusFilter.ledig:
        return 'ledig';
      case FleetStatusFilter.fri:
        return 'fri';
      case FleetStatusFilter.gittBort:
        return 'gitt_bort';
    }
  }
}

class FleetKpiTile extends StatelessWidget {
  const FleetKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
    this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 108,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 16, color: color),
          if (icon != null) const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color, height: 1.1),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(fontSize: 9, color: Colors.grey[600]), maxLines: 2),
          ],
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(DriftProTheme.radiusMd), child: child);
  }
}

class FleetSectionHeader extends StatelessWidget {
  const FleetSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: DriftProTheme.headingSm),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class FleetFilterCard extends StatelessWidget {
  const FleetFilterCard({
    super.key,
    required this.focusDateLabel,
    required this.onPickDate,
    required this.shiftDropdown,
    this.shiftHint,
    this.actions,
  });

  final String focusDateLabel;
  final VoidCallback onPickDate;
  final Widget shiftDropdown;
  final String? shiftHint;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DriftProTheme.radiusMd),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth > 520;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 200,
                        child: _DateButton(label: focusDateLabel, onTap: onPickDate),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: shiftDropdown),
                      if (actions != null) ...[const SizedBox(width: 8), ...actions!],
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DateButton(label: focusDateLabel, onTap: onPickDate),
                    const SizedBox(height: 10),
                    shiftDropdown,
                    if (actions != null) ...[const SizedBox(height: 8), Wrap(spacing: 8, children: actions!)],
                  ],
                );
              },
            ),
            if (shiftHint != null) ...[
              const SizedBox(height: 8),
              Text(shiftHint!, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
            ],
          ],
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        alignment: Alignment.centerLeft,
      ),
    );
  }
}
