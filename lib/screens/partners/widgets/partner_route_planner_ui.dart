import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/route_dispatch_status.dart';

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

  /// Samlet verktøyrad — hvite chips, grupperte handlinger.
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
      ],
    );
  }

  static Widget searchField({required TextEditingController controller}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Søk MAVI-kode eller partner…',
        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF6B7280)),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF9CA3AF)),
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

  /// Status for uken — hvit flate, nøytral fremdrift.
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
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
              Text(
                '$pct%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: accepted / total,
              minHeight: 6,
              backgroundColor: const Color(0xFFF3F4F6),
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountBadge(label: '$draft kladd', color: const Color(0xFF6B7280)),
              _CountBadge(label: '$waiting venter', color: const Color(0xFF6B7280)),
              _CountBadge(label: '$accepted akseptert', color: const Color(0xFF111827)),
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
              color: const Color(0xFF374151),
              bg: Colors.white,
              onTap: onNudge,
            ),
          ),
        if (pendingAck > 0) const SizedBox(width: 4),
        Expanded(
          child: _MiniDayButton(
            icon: Icons.delete_outline,
            label: 'Tøm',
            color: const Color(0xFF374151),
            bg: Colors.white,
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
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: -0.3,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle ??
                    'Velg dag, trykk tom celle eller bruk handlingsknappene under.',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
        if (busy)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF111827)),
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
          foregroundColor: const Color(0xFF374151),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
          backgroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: Color(0xFF6B7280),
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
    final enabled = onPressed != null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: emphasized ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: enabled ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabled ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
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
    const ink = Color(0xFF111827);
    const muted = Color(0xFF6B7280);
    const line = Color(0xFFE5E7EB);

    final card = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RoutePlannerUi._radius),
            border: Border.all(
              color: action.glow && enabled ? ink : line,
              width: action.glow && enabled ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: line),
                ),
                child: Icon(
                  action.icon,
                  color: enabled ? ink : const Color(0xFF9CA3AF),
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
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: enabled ? ink : muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      style: const TextStyle(fontSize: 11, color: muted),
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
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: line),
                  ),
                  child: Text(
                    action.badge!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
              ],
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: item.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              item.label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
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
            border: Border.all(color: const Color(0xFFE5E7EB)),
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
