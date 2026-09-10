import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/route_dispatch_status.dart';
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

  /// Samlet verktøyrad — like chips, grupperte handlinger.
  static Widget toolChipGroup({
    required BuildContext context,
    required List<RoutePlannerTool> tools,
  }) {
    final drift = context.driftColors;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: drift.surfaceMuted,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: drift.borderSubtle),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in tools)
            _ToolChip(
              icon: t.icon,
              label: t.label,
              onPressed: t.onPressed,
              emphasized: t.emphasized,
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
      _LegendItem('Kladd', RouteDispatchStatus.colorDraft, 'Ikke delt ut til sjåfør'),
      _LegendItem(
        'Venter',
        RouteDispatchStatus.colorWaiting,
        'Sendt — venter på aksept',
      ),
      _LegendItem(
        'Akseptert',
        RouteDispatchStatus.colorAccepted,
        'Sjåfør har akseptert',
      ),
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

  /// Glass-statistikk: akseptert av totalt + kladd/venter.
  static Widget acceptanceOverview({
    required int total,
    required int accepted,
    required int draft,
    required int waiting,
  }) {
    if (total <= 0) {
      return const SizedBox.shrink();
    }
    final pct = ((accepted / total) * 100).round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.85),
            RouteDispatchStatus.colorAccepted.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$accepted av $total akseptert',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: RouteDispatchStatus.colorAccepted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: accepted / total,
              minHeight: 8,
              backgroundColor: Colors.black.withValues(alpha: 0.06),
              color: RouteDispatchStatus.colorAccepted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountBadge(
                label: '$draft kladd',
                color: RouteDispatchStatus.colorDraft,
              ),
              _CountBadge(
                label: '$waiting venter',
                color: RouteDispatchStatus.colorWaiting,
              ),
              _CountBadge(
                label: '$accepted akseptert',
                color: RouteDispatchStatus.colorAccepted,
              ),
            ],
          ),
        ],
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

class RoutePlannerTool {
  const RoutePlannerTool({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;
}

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

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;
    final enabled = onPressed != null;
    return Material(
      color: emphasized
          ? DriftProTheme.primaryGreen.withValues(alpha: 0.12)
          : drift.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: enabled
                    ? (emphasized ? DriftProTheme.primaryGreen : drift.textPrimary)
                    : drift.iconMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? (emphasized
                          ? DriftProTheme.primaryGreenDark
                          : drift.textPrimary)
                      : drift.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.9),
              item.color.withValues(alpha: 0.14),
            ],
          ),
          border: Border.all(color: item.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: item.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: item.color.withValues(alpha: 0.45),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: item.color,
              ),
            ),
          ],
        ),
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
