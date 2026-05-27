import 'package:flutter/material.dart';

/// Nesten fullskjerm dialog for rute-arbeidsflyt (SAP, AUTO MASS, Ny rute).
Future<T?> showPartnerRouteWorkflowDialog<T>(
  BuildContext context, {
  required Widget child,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final compact = size.width < 640;
      // Nesten fullskjerm — samme størrelse for AUTO MASS, SAP og Ny rute.
      final inset = compact ? 0.0 : 6.0;
      final radius = compact ? 0.0 : 16.0;
      final w = size.width - inset * 2;
      final h = size.height - inset * 2;
      return Dialog(
        insetPadding: EdgeInsets.all(inset),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        child: SizedBox(width: w, height: h, child: child),
      );
    },
  );
}

class RouteWorkflowMetric {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? hint;

  const RouteWorkflowMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.hint,
  });
}

/// Kommandosenter: statistikk øverst, sidepanel + hovedliste, publisering nederst.
class PartnerRouteWorkflowShell extends StatelessWidget {
  final Color accent;
  final Color accentDark;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final List<RouteWorkflowMetric> metrics;
  final Widget sidebar;
  final Widget? guidePanel;
  final bool guideExpanded;
  final VoidCallback? onGuideToggle;
  final List<String> tabLabels;
  final List<int?> tabBadges;
  final List<Color?> tabBadgeColors;
  final int selectedTabIndex;
  final ValueChanged<int> onTabSelected;
  final String tabCaption;
  final Widget tabBody;
  final Widget footer;
  final Widget? topBanner;

  const PartnerRouteWorkflowShell({
    super.key,
    required this.accent,
    required this.accentDark,
    required this.icon,
    required this.title,
    this.subtitle,
    this.badge,
    required this.metrics,
    required this.sidebar,
    this.guidePanel,
    this.guideExpanded = false,
    this.onGuideToggle,
    required this.tabLabels,
    this.tabBadges = const [],
    this.tabBadgeColors = const [],
    required this.selectedTabIndex,
    required this.onTabSelected,
    required this.tabCaption,
    required this.tabBody,
    required this.footer,
    this.topBanner,
  });

  static const _bg = Color(0xFFEEF1F5);
  static const _railWidth = 340.0;
  static const _breakpoint = 980.0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _breakpoint;

    return Material(
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          _buildMetricsRow(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: wide ? _buildWideBody() : _buildNarrowBody(),
            ),
          ),
          _buildFooterArea(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentDark, accent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white38),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Lukk',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final n = metrics.length;
          if (n == 0) return const SizedBox.shrink();
          final cols = constraints.maxWidth >= 600 ? n.clamp(2, 4) : 2;
          final cellW = (constraints.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics
                .map((m) => SizedBox(width: cellW, child: _StatCard(metric: m, accent: accentDark)))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildWideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _railWidth,
          child: _buildSidebar(scrollable: true),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildMainPanel()),
      ],
    );
  }

  Widget _buildNarrowBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSidebar(scrollable: false),
        const SizedBox(height: 10),
        Expanded(child: _buildMainPanel()),
      ],
    );
  }

  Widget _buildSidebar({required bool scrollable}) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(14),
            child: sidebar,
          ),
        ),
        if (onGuideToggle != null) ...[
          const SizedBox(height: 10),
          _buildGuideToggle(),
        ],
        if (guideExpanded && guidePanel != null) ...[
          const SizedBox(height: 8),
          guidePanel!,
        ],
      ],
    );

    if (!scrollable) return content;

    return SingleChildScrollView(
      child: content,
    );
  }

  Widget _buildMainPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topBanner != null) ...[
          topBanner!,
          const SizedBox(height: 8),
        ],
        LayoutBuilder(
          builder: (context, constraints) => _buildTabBar(wide: constraints.maxWidth >= _breakpoint),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text(
            tabCaption,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.35),
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: tabBody,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar({required bool wide}) {
    Widget tabChip(int i) {
      final selected = i == selectedTabIndex;
      final badge = i < tabBadges.length ? tabBadges[i] : null;
      final badgeColor = i < tabBadgeColors.length ? tabBadgeColors[i] : null;
      return Padding(
        padding: EdgeInsets.only(right: wide ? 0 : 6, left: wide ? 0 : i == 0 ? 4 : 0),
        child: Material(
          color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onTabSelected(i),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 8 : 14,
                vertical: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Text(
                    tabLabels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? accentDark : Colors.grey.shade700,
                    ),
                  ),
                  if (badge != null && badge > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (badgeColor ?? accentDark).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: badgeColor ?? accentDark,
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: wide
          ? SizedBox(
              height: 52,
              child: Row(
                children: List.generate(
                  tabLabels.length,
                  (i) => Expanded(child: tabChip(i)),
                ),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: List.generate(tabLabels.length, tabChip),
              ),
            ),
    );
  }

  Widget _buildGuideToggle() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onGuideToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 20, color: accentDark),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Slik fungerer det',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Icon(guideExpanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: footer,
    );
  }
}

class _StatCard extends StatelessWidget {
  final RouteWorkflowMetric metric;
  final Color accent;

  const _StatCard({required this.metric, required this.accent});

  @override
  Widget build(BuildContext context) {
    final c = metric.color ?? accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(metric.icon, color: c, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  metric.value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: c,
                    height: 1.1,
                  ),
                ),
                Text(
                  metric.label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.2),
                ),
                if (metric.hint != null)
                  Text(
                    metric.hint!,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Oransje banner — kun manuell tildeling.
Widget routeShiftAttentionBanner({
  required int count,
  required VoidCallback onOpenList,
}) {
  return Material(
    color: const Color(0xFFFFEBEE),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpenList,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade800, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count rute(r) mangler skift',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.red.shade900,
                    ),
                  ),
                  Text(
                    'Trykk for å se listen og velge skiftplan',
                    style: TextStyle(fontSize: 11, color: Colors.red.shade800),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: Colors.red.shade800),
          ],
        ),
      ),
    ),
  );
}

Widget routeManualAttentionBanner({
  required int count,
  required VoidCallback onOpenManual,
}) {
  return Material(
    color: const Color(0xFFFFF3E0),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onOpenManual,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.pan_tool_alt_outlined, color: Colors.orange.shade900, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count PDF krever manuell tildeling',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  Text(
                    'Trykk for å åpne fanen Manuell',
                    style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: Colors.orange.shade900),
          ],
        ),
      ),
    ),
  );
}

Widget routeInfoChip(String label, {VoidCallback? onTap, Color? color}) {
  return ActionChip(
    visualDensity: VisualDensity.compact,
    label: Text(label, style: const TextStyle(fontSize: 11)),
    onPressed: onTap,
    backgroundColor: Colors.grey.shade50,
    side: BorderSide(color: color ?? Colors.grey.shade400),
    labelStyle: TextStyle(color: color ?? Colors.grey.shade800),
  );
}
