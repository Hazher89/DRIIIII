import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Fast knappehøyde for alle team-kontroller (filter, handling, switcher).
abstract final class TeamControlMetrics {
  static const double height = 44;
  static const double radius = 12;
  static const double gap = 8;
  static const EdgeInsets pad = EdgeInsets.symmetric(horizontal: 10);
}

/// Fullbredde segment med like store knapper.
class TeamEqualSegmentBar<T> extends StatelessWidget {
  const TeamEqualSegmentBar({
    super.key,
    required this.value,
    required this.onChanged,
    required this.items,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final List<TeamEqualSegmentItem<T>> items;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: TeamControlMetrics.height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(TeamControlMetrics.radius),
        border: Border.all(
          color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: _EqualSegButton(
                selected: value == items[i].value,
                label: items[i].label,
                icon: items[i].icon,
                onTap: () => onChanged(items[i].value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class TeamEqualSegmentItem<T> {
  const TeamEqualSegmentItem({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

class _EqualSegButton extends StatelessWidget {
  const _EqualSegButton({
    required this.selected,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final bool selected;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected
          ? (isDark ? DriftProTheme.cardDark : Colors.white)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(TeamControlMetrics.radius - 2),
      elevation: selected ? 0.5 : 0,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TeamControlMetrics.radius - 2),
        child: SizedBox(
          height: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? DriftProTheme.primaryGreen
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? DriftProTheme.primaryGreen
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Filterknapper i jevnt rutenett — alle like store.
class TeamEqualFilterGrid<T> extends StatelessWidget {
  const TeamEqualFilterGrid({
    super.key,
    required this.value,
    required this.onChanged,
    required this.items,
    this.columns = 2,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final List<TeamEqualFilterItem<T>> items;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cols = columns.clamp(2, 4);
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += cols) {
      final slice = items.skip(i).take(cols).toList();
      rows.add(
        Row(
          children: [
            for (var j = 0; j < cols; j++) ...[
              if (j > 0) const SizedBox(width: TeamControlMetrics.gap),
              Expanded(
                child: j < slice.length
                    ? _EqualFilterButton(
                        selected: value == slice[j].value,
                        label: slice[j].label,
                        icon: slice[j].icon,
                        badge: slice[j].badge,
                        accent: slice[j].accent,
                        onTap: () => onChanged(slice[j].value),
                      )
                    : const SizedBox(height: TeamControlMetrics.height),
              ),
            ],
          ],
        ),
      );
      if (i + cols < items.length) {
        rows.add(const SizedBox(height: TeamControlMetrics.gap));
      }
    }
    return Column(children: rows);
  }
}

class TeamEqualFilterItem<T> {
  const TeamEqualFilterItem({
    required this.value,
    required this.label,
    this.icon,
    this.badge,
    this.accent,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? badge;
  final Color? accent;
}

class _EqualFilterButton extends StatelessWidget {
  const _EqualFilterButton({
    required this.selected,
    required this.label,
    required this.onTap,
    this.icon,
    this.badge,
    this.accent,
  });

  final bool selected;
  final String label;
  final IconData? icon;
  final String? badge;
  final Color? accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = accent ?? DriftProTheme.primaryGreen;
    return SizedBox(
      height: TeamControlMetrics.height,
      child: Material(
        color: selected
            ? color.withValues(alpha: isDark ? 0.22 : 0.12)
            : (isDark ? DriftProTheme.cardDark : Colors.white),
        borderRadius: BorderRadius.circular(TeamControlMetrics.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TeamControlMetrics.radius),
          child: Container(
            padding: TeamControlMetrics.pad,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(TeamControlMetrics.radius),
              border: Border.all(
                color: selected
                    ? color.withValues(alpha: 0.55)
                    : (isDark ? DriftProTheme.dividerDark : Colors.grey.shade200),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? color
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? color
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ),
                if (badge != null && badge!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withValues(alpha: 0.2)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? color
                            : (isDark ? Colors.white60 : Colors.black54),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// To like store handlingsknapper (f.eks. Avvis / Godkjenn).
class TeamEqualActionRow extends StatelessWidget {
  const TeamEqualActionRow({
    super.key,
    required this.secondaryLabel,
    required this.primaryLabel,
    required this.onSecondary,
    required this.onPrimary,
    this.secondaryColor,
    this.primaryColor,
  });

  final String secondaryLabel;
  final String primaryLabel;
  final VoidCallback onSecondary;
  final VoidCallback onPrimary;
  final Color? secondaryColor;
  final Color? primaryColor;

  @override
  Widget build(BuildContext context) {
    final reject = secondaryColor ?? Colors.red.shade700;
    final accept = primaryColor ?? DriftProTheme.success;
    return SizedBox(
      height: TeamControlMetrics.height,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onSecondary,
              style: OutlinedButton.styleFrom(
                foregroundColor: reject,
                side: BorderSide(color: reject.withValues(alpha: 0.45)),
                minimumSize: const Size(0, TeamControlMetrics.height),
                maximumSize: const Size(double.infinity, TeamControlMetrics.height),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeamControlMetrics.radius),
                ),
              ),
              child: Text(
                secondaryLabel,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: TeamControlMetrics.gap),
          Expanded(
            child: FilledButton(
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: accept,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, TeamControlMetrics.height),
                maximumSize: const Size(double.infinity, TeamControlMetrics.height),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(TeamControlMetrics.radius),
                ),
              ),
              child: Text(
                primaryLabel,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Søkefelt med fast høyde som matcher øvrige kontroller.
class TeamEqualSearchField extends StatelessWidget {
  const TeamEqualSearchField({
    super.key,
    required this.controller,
    this.hintText = 'Søk…',
  });

  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: TeamControlMetrics.height,
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(TeamControlMetrics.radius),
            borderSide: BorderSide(
              color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(TeamControlMetrics.radius),
            borderSide: BorderSide(
              color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(TeamControlMetrics.radius),
            borderSide: const BorderSide(
              color: DriftProTheme.primaryGreen,
              width: 1.5,
            ),
          ),
          isDense: true,
        ),
      ),
    );
  }
}
