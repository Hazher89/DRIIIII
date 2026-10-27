import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/route_dispatch_status.dart';

/// Delte UI-komponenter for rute-planlegger — fargerik, lys og tydelig.
class RoutePlannerUi {
  RoutePlannerUi._();

  static const _radius = 16.0;

  static const colorNew = Color(0xFF0D9488);
  static const colorMass = Color(0xFF7C3AED);
  static const colorSap = Color(0xFF2563EB);
  static const colorTool = Color(0xFFEA580C);
  static const colorInk = Color(0xFF111827);
  static const colorMuted = Color(0xFF6B7280);
  static const colorLine = Color(0xFFE5E7EB);

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
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: _ActionCard(action: actions[i])),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: actions
                    .map(
                      (a) => SizedBox(
                        width: constraints.maxWidth >= 340
                            ? (constraints.maxWidth - 12) / 2
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
          const SizedBox(width: 12),
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
              value: RoutePlannerViewMode.day,
              label: Text('Dag'),
              icon: Icon(Icons.view_agenda_outlined, size: 18),
            ),
            ButtonSegment(
              value: RoutePlannerViewMode.week,
              label: Text('Uke'),
              icon: Icon(Icons.view_week_outlined, size: 18),
            ),
          ],
          selected: {mode == RoutePlannerViewMode.month ? RoutePlannerViewMode.week : mode},
          onSelectionChanged: (s) => onModeChanged(s.first),
        ),
        _NavPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: mode == RoutePlannerViewMode.day ? 'Forrige dag' : 'Forrige uke',
                visualDensity: VisualDensity.compact,
                onPressed: onPrevWeek,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                mode == RoutePlannerViewMode.day
                    ? DateFormat('EEE d. MMM', 'nb_NO').format(focusDay)
                    : compact
                        ? '${DateFormat('d. MMM', 'nb_NO').format(weekStart)} – ${DateFormat('d. MMM', 'nb_NO').format(weekEnd)}'
                        : '${DateFormat.MMMd('nb_NO').format(weekStart)} – ${DateFormat.MMMd('nb_NO').format(weekEnd)}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              IconButton(
                tooltip: mode == RoutePlannerViewMode.day ? 'Neste dag' : 'Neste uke',
                visualDensity: VisualDensity.compact,
                onPressed: onNextWeek,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: onToday,
          icon: const Icon(Icons.today_outlined, size: 18),
          label: const Text('I dag'),
          style: FilledButton.styleFrom(
            foregroundColor: colorNew,
            backgroundColor: colorNew.withValues(alpha: 0.12),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onPickDay,
          icon: const Icon(Icons.event_outlined, size: 18),
          label: Text(DateFormat('EEE d.M', 'nb').format(focusDay)),
        ),
      ],
    );
  }

  /// Fargerike verktøy-knapper.
  static Widget toolChipGroup({
    required BuildContext context,
    required List<RoutePlannerTool> tools,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionLabel('Verktøy'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < tools.length; i++)
              _ToolChip(
                icon: tools[i].icon,
                label: tools[i].label,
                onPressed: tools[i].onPressed,
                emphasized: tools[i].emphasized,
                color: tools[i].color ?? _toolPalette[i % _toolPalette.length],
              ),
          ],
        ),
      ],
    );
  }

  static const _toolPalette = [
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
    Color(0xFF4F46E5),
  ];

  static Widget searchField({required TextEditingController controller}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Søk MAVI-kode eller partner…',
        prefixIcon: const Icon(Icons.search, size: 20, color: colorMuted),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: colorLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorNew.withValues(alpha: 0.7), width: 1.5),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorLine),
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
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: RouteDispatchStatus.colorAccepted.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$pct%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: RouteDispatchStatus.colorAccepted,
                  ),
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
              backgroundColor: const Color(0xFFF3F4F6),
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
              color: RouteDispatchStatus.colorWaiting,
              bg: RouteDispatchStatus.colorWaiting.withValues(alpha: 0.1),
              onTap: onNudge,
            ),
          ),
        if (pendingAck > 0) const SizedBox(width: 4),
        Expanded(
          child: _MiniDayButton(
            icon: Icons.delete_outline,
            label: 'Tøm',
            color: colorMuted,
            bg: const Color(0xFFF3F4F6),
            onTap: onClear,
          ),
        ),
      ],
    );
  }

  /// Horisontal dag-stripe for dagstavle.
  static Widget dayStrip({
    required List<DateTime> days,
    required DateTime focusDay,
    required int Function(DateTime day) routeCount,
    required ValueChanged<DateTime> onSelect,
  }) {
    final now = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = days[i];
          final dayOnly = DateTime(d.year, d.month, d.day);
          final isToday = dayOnly == now;
          final isFocus = dayOnly == DateTime(focusDay.year, focusDay.month, focusDay.day);
          final n = routeCount(d);
          return Material(
            color: isFocus ? colorNew : Colors.white,
            borderRadius: BorderRadius.circular(14),
            elevation: isFocus ? 1 : 0,
            shadowColor: colorNew.withValues(alpha: 0.35),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onSelect(dayOnly),
              child: Container(
                width: 72,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isFocus
                        ? colorNew
                        : isToday
                            ? colorNew.withValues(alpha: 0.45)
                            : colorLine,
                    width: isFocus || isToday ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat.E('nb_NO').format(d),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: isFocus ? Colors.white : colorMuted,
                      ),
                    ),
                    Text(
                      DateFormat('d/M', 'nb_NO').format(d),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isFocus ? Colors.white : colorInk,
                      ),
                    ),
                    Text(
                      n == 0 ? 'tom' : '$n ruter',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isFocus
                            ? Colors.white.withValues(alpha: 0.9)
                            : n == 0
                                ? colorMuted
                                : colorNew,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget header({
    required BuildContext context,
    bool busy = false,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rute-planlegger',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.4,
                  color: colorInk,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle ??
                    'Velg dag → se sjåfører → legg til eller send ruter.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: colorMuted,
                ),
              ),
            ],
          ),
        ),
        if (busy)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: colorNew),
          ),
      ],
    );
  }

  static Widget refreshButton({required VoidCallback? onPressed}) {
    return Tooltip(
      message: 'Oppdater',
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colorNew,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Icon(Icons.refresh_rounded),
      ),
    );
  }

  static Widget sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: colorMuted,
      ),
    );
  }
}

enum RoutePlannerViewMode { day, week, month }

class RoutePlannerTool {
  const RoutePlannerTool({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;
  final Color? color;
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
    required this.color,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: color.withValues(alpha: emphasized ? 0.18 : 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: emphasized ? 0.55 : 0.28),
              width: emphasized ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: enabled ? color : RoutePlannerUi.colorMuted),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: enabled ? color : RoutePlannerUi.colorMuted,
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
    final c = action.color;

    final card = Material(
      color: c.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
      elevation: action.glow && enabled ? 2 : 0,
      shadowColor: c.withValues(alpha: 0.4),
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
            border: Border.all(
              color: c.withValues(alpha: action.glow && enabled ? 0.7 : 0.35),
              width: action.glow && enabled ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: enabled ? RoutePlannerUi.colorInk : RoutePlannerUi.colorMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      action.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: enabled
                            ? c.withValues(alpha: 0.9)
                            : RoutePlannerUi.colorMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (action.badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: action.badgeColor ?? c,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    action.badge!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
              Icon(Icons.arrow_forward_rounded, size: 20, color: c),
            ],
          ),
        ),
      ),
    );

    return Opacity(opacity: enabled ? 1 : 0.5, child: card);
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RoutePlannerUi.colorLine),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
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
          color: item.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: item.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
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
