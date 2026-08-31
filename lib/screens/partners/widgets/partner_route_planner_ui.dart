import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/driftpro_theme_context.dart';

/// Delte UI-komponenter for rute-planlegger — tydelig hierarki og konsistent design.
class RoutePlannerUi {
  RoutePlannerUi._();

  static const _radius = 14.0;

  static Widget actionGrid({
    required BuildContext context,
    required List<RoutePlannerAction> actions,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 520;
              if (wide) {
                return Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: _ActionCard(action: actions[i])),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: actions
                    .map(
                      (a) => SizedBox(
                        width: constraints.maxWidth >= 340
                            ? (constraints.maxWidth - 10) / 2
                            : constraints.maxWidth,
                        child: _ActionCard(action: a),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing,
        ],
      ],
    );
  }

  static Widget dateNavigator({
    required DateTime weekStart,
    required DateTime weekEnd,
    required DateTime focusDay,
    required RoutePlannerViewMode mode,
    required ValueChanged<RoutePlannerViewMode> onModeChanged,
    required VoidCallback onPrevWeek,
    required VoidCallback onNextWeek,
    required VoidCallback? onToday,
    required VoidCallback? onPickDay,
    bool compact = false,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<RoutePlannerViewMode>(
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStateProperty.all(
              EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
            ),
          ),
          segments: const [
            ButtonSegment(
              value: RoutePlannerViewMode.week,
              label: Text('Uke'),
              icon: Icon(Icons.view_week_outlined, size: 18),
            ),
            ButtonSegment(
              value: RoutePlannerViewMode.month,
              label: Text('Måned'),
              icon: Icon(Icons.calendar_month_outlined, size: 18),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onModeChanged(s.first),
        ),
        _NavPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Forrige uke',
                visualDensity: VisualDensity.compact,
                onPressed: onPrevWeek,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                compact
                    ? '${DateFormat('d. MMM', 'nb_NO').format(weekStart)} – ${DateFormat('d. MMM', 'nb_NO').format(weekEnd)}'
                    : '${DateFormat.MMMd('nb_NO').format(weekStart)} – ${DateFormat.MMMd('nb_NO').format(weekEnd)}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              IconButton(
                tooltip: 'Neste uke',
                visualDensity: VisualDensity.compact,
                onPressed: onNextWeek,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onToday,
          icon: const Icon(Icons.today_outlined, size: 18),
          label: const Text('I dag'),
        ),
        OutlinedButton.icon(
          onPressed: onPickDay,
          icon: const Icon(Icons.event_outlined, size: 18),
          label: Text(DateFormat('EEE d.M', 'nb').format(focusDay)),
        ),
      ],
    );
  }

  static Widget focusDayActions({
    required BuildContext context,
    required DateTime focusDay,
    required int pendingAck,
    required int routeCount,
    required VoidCallback? onNudge,
    required VoidCallback? onClear,
    bool compact = false,
  }) {
    if (pendingAck == 0 && routeCount == 0) {
      return focusDayChip(context, focusDay);
    }

    final drift = context.driftColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: drift.surfaceMuted,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: drift.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.event_available_outlined, size: 18, color: drift.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Valgt dag · ${DateFormat('EEEE d. MMMM', 'nb').format(focusDay)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12 : 13,
                    color: drift.textPrimary,
                  ),
                ),
              ),
              if (routeCount > 0)
                _CountBadge(
                  label: '$routeCount rute${routeCount == 1 ? '' : 'r'}',
                  color: DriftProTheme.primaryGreen,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (pendingAck > 0)
                _SoftActionButton(
                  icon: Icons.notifications_active_outlined,
                  label: 'Send purring',
                  detail: '$pendingAck venter',
                  color: const Color(0xFFE65100),
                  background: const Color(0xFFFFF3E0),
                  onPressed: onNudge,
                ),
              if (routeCount > 0)
                _SoftActionButton(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Tøm dag',
                  detail: '$routeCount rute${routeCount == 1 ? '' : 'r'}',
                  color: DriftProTheme.error,
                  background: const Color(0xFFFFEBEE),
                  onPressed: onClear,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget focusDayChip(BuildContext context, DateTime focusDay) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: DriftProTheme.primaryGreen.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_outlined, size: 16, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 6),
          Text(
            DateFormat('EEEE d. MMM', 'nb').format(focusDay),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: DriftProTheme.primaryGreenDark,
            ),
          ),
        ],
      ),
    );
  }

  static Widget searchField({required TextEditingController controller}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Søk MAVI-kode eller partner…',
        prefixIcon: const Icon(Icons.search, size: 20),
        isDense: true,
        filled: true,
        fillColor: Colors.grey.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
    );
  }

  static Widget statusLegend({bool scrollable = false}) {
    const items = [
      _LegendItem('Kladd', Color(0xFFFF9800), 'Ikke sendt ennå'),
      _LegendItem('Uten varsel', Color(0xFF78909C), 'Registrert uten SMS/push'),
      _LegendItem('Varslet', Color(0xFF2E7D32), 'Sendt til sjåfør/eier'),
      _LegendItem('PDF lest', Color(0xFF1565C0), 'Sjåfør har åpnet PDF'),
      _LegendItem('Akseptert', Color(0xFF1B5E20), 'Rute godkjent'),
    ];

    final chips = items.map((e) => _LegendChip(item: e)).toList();

    if (!scrollable) {
      return Wrap(spacing: 12, runSpacing: 6, children: chips);
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  static Widget dayColumnActions({
    required int pendingAck,
    required VoidCallback? onNudge,
    required VoidCallback? onClear,
  }) {
    return Row(
      children: [
        if (pendingAck > 0)
          Expanded(
            child: _MiniDayButton(
              icon: Icons.notifications_active_outlined,
              label: 'Purr',
              color: const Color(0xFFE65100),
              bg: const Color(0xFFFFF3E0),
              onTap: onNudge,
            ),
          ),
        if (pendingAck > 0) const SizedBox(width: 4),
        Expanded(
          child: _MiniDayButton(
            icon: Icons.delete_outline,
            label: 'Tøm',
            color: DriftProTheme.error,
            bg: const Color(0xFFFFEBEE),
            onTap: onClear,
          ),
        ),
      ],
    );
  }

  static Widget header({
    required BuildContext context,
    bool busy = false,
    String? subtitle,
  }) {
    final drift = context.driftColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: DriftProTheme.primaryGreen.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.route_outlined,
            color: DriftProTheme.primaryGreen,
            size: 26,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rute-planlegger',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.3,
                  color: drift.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle ??
                    'Velg dag, trykk tom celle eller bruk handlingsknappene under.',
                style: TextStyle(fontSize: 12, height: 1.35, color: drift.textMuted),
              ),
            ],
          ),
        ),
        if (busy)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }

  static Widget refreshButton({required VoidCallback? onPressed}) {
    return Tooltip(
      message: 'Oppdater kalender',
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Icon(Icons.refresh_rounded),
      ),
    );
  }
}

enum RoutePlannerViewMode { week, month }

class RoutePlannerAction {
  const RoutePlannerAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onPressed,
    this.badge,
    this.badgeColor,
    this.glow = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onPressed;
  final String? badge;
  final Color? badgeColor;
  final bool glow;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});

  final RoutePlannerAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onPressed != null;
    final drift = context.driftColors;

    Widget card = Material(
      color: drift.card,
      borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
            border: Border.all(
              color: enabled
                  ? action.color.withValues(alpha: 0.35)
                  : drift.borderSubtle,
              width: 1.5,
            ),
            gradient: enabled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      action.color.withValues(alpha: 0.08),
                      action.color.withValues(alpha: 0.02),
                    ],
                  )
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: enabled ? 0.15 : 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  action.icon,
                  color: enabled ? action.color : drift.iconMuted,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: enabled ? drift.textPrimary : drift.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      style: TextStyle(fontSize: 11, color: drift.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (action.badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (action.badgeColor ?? action.color).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    action.badge!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: action.badgeColor ?? action.color,
                    ),
                  ),
                ),
              ],
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: enabled ? action.color.withValues(alpha: 0.6) : drift.iconMuted,
              ),
            ],
          ),
        ),
      ),
    );

    if (action.glow && enabled) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
          boxShadow: [
            BoxShadow(
              color: action.color.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: card,
      );
    }

    return Opacity(opacity: enabled ? 1 : 0.55, child: card);
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }
}

class _SoftActionButton extends StatelessWidget {
  const _SoftActionButton({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
    required this.background,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final Color background;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                  Text(
                    detail,
                    style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _LegendItem {
  const _LegendItem(this.label, this.color, this.hint);
  final String label;
  final Color color;
  final String hint;
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.item});
  final _LegendItem item;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.hint,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: item.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(item.label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        ],
      ),
    );
  }
}

class _MiniDayButton extends StatelessWidget {
  const _MiniDayButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
