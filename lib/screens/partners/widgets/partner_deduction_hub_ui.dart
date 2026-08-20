import 'package:flutter/material.dart';

import '../../../core/layout/web_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_deduction_case.dart';
import '../../../core/case_trace/case_trace_chip.dart';
import 'partner_deduction_logiqrma_panel.dart';
import 'partner_modern_ui.dart';

/// Bot/Trekk UI — kompakt admin på web, ryddig mobil.
class PartnerDeductionHubUi {
  PartnerDeductionHubUi._();

  static const _accent = Color(0xFFEA580C);
  static const _accentDark = Color(0xFF9A3412);

  static Widget pageShell({required BuildContext context, required Widget child}) {
    if (!WebLayout.prefersPointerNav) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: WebLayout.contentMaxWidth(wide: 1180)),
        child: child,
      ),
    );
  }

  static Widget compactHeader({
    required BuildContext context,
    required int activePartners,
    required VoidCallback onNewCase,
    VoidCallback? onOpenSettings,
    bool canManageArchive = false,
  }) {
    final wide = WebLayout.isWide(context, minWidth: 800);
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 20 : 14, wide ? 16 : 10, wide ? 20 : 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.gavel_rounded, color: _accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bot / Trekk',
                  style: TextStyle(
                    fontSize: wide ? 22 : 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                ),
                Text(
                  canManageArchive
                      ? 'Arkiv · fakturering · $activePartners bedrifter'
                      : 'Registrer og følg trekk · $activePartners bedrifter',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: PartnerModernUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
          if (onOpenSettings != null)
            IconButton(
              tooltip: 'Varsler',
              onPressed: onOpenSettings,
              icon: Icon(Icons.tune_rounded, color: PartnerModernUi.muted(context)),
            ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: onNewCase,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(wide ? 'Nytt trekk' : 'Nytt'),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 12, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  static Widget kpiStrip({
    required BuildContext context,
    required String openCount,
    required String openAmount,
    required String invoicedCount,
    required String invoicedAmount,
    required String evidenceCount,
  }) {
    final wide = WebLayout.isWide(context, minWidth: 800);
    final items = <(String, String, Color)>[
      ('Åpne', openCount, _accent),
      ('Åpne beløp', openAmount, const Color(0xFFDC2626)),
      ('Fakturert', invoicedCount, DriftProTheme.primaryGreen),
      ('Bevis', evidenceCount, const Color(0xFF7C3AED)),
    ];

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _KpiCard(label: items[i].$1, value: items[i].$2, color: items[i].$3)),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in items)
            SizedBox(
              width: (MediaQuery.sizeOf(context).width - 36) / 2,
              child: _KpiCard(label: item.$1, value: item.$2, color: item.$3),
            ),
        ],
      ),
    );
  }

  static Widget filterChips({
    required BuildContext context,
    required String filter,
    required ValueChanged<String> onFilter,
    required int openCount,
    required int invoicedCount,
    int deletedCount = 0,
    bool showDeleted = false,
  }) {
    final wide = WebLayout.isWide(context, minWidth: 720);
    final chips = <(String, String)>[
      ('Åpne ($openCount)', 'open'),
      ('Fakturert ($invoicedCount)', 'invoiced'),
      if (showDeleted) ('Slettet ($deletedCount)', 'deleted'),
      ('Alle', 'all'),
    ];

    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PartnerModernUi.border(context).withValues(alpha: 0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in chips) ...[
                _SegChip(
                  label: c.$1,
                  selected: filter == c.$2,
                  onTap: () => onFilter(c.$2),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _chip(context, chips[i].$1, chips[i].$2, filter, onFilter),
          ],
        ],
      ),
    );
  }

  static Widget _chip(
    BuildContext context,
    String label,
    String value,
    String selected,
    ValueChanged<String> onFilter,
  ) {
    final active = selected == value;
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: active,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      selectedColor: _accent.withValues(alpha: 0.14),
      labelStyle: TextStyle(
        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
        color: active ? _accentDark : PartnerModernUi.muted(context),
      ),
      onSelected: (_) => onFilter(value),
    );
  }

  static Widget summaryLine({
    required BuildContext context,
    required String text,
    bool highlight = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        WebLayout.isWide(context, minWidth: 800) ? 20 : 14,
        4,
        WebLayout.isWide(context, minWidth: 800) ? 20 : 14,
        6,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          color: highlight ? _accentDark : PartnerModernUi.muted(context),
        ),
      ),
    );
  }

  static Widget tableHeader(BuildContext context, {required bool showCheckbox}) {
    if (!WebLayout.isWide(context, minWidth: 900)) return const SizedBox.shrink();
    final muted = PartnerModernUi.muted(context);
    Widget col(String t, {int flex = 1}) => Expanded(
          flex: flex,
          child: Text(
            t,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: muted,
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: PartnerModernUi.border(context).withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          if (showCheckbox) const SizedBox(width: 28),
          col('Sak', flex: 2),
          col('Bedrift', flex: 2),
          col('Beskrivelse', flex: 3),
          col('Dato', flex: 1),
          col('Status', flex: 2),
          SizedBox(
            width: 88,
            child: Text(
              'Beløp',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: muted),
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  static Widget bulkBar({
    required BuildContext context,
    required int selectedCount,
    required VoidCallback onSelectAll,
    required VoidCallback onClear,
    required VoidCallback onMarkInvoiced,
    required bool allSelected,
  }) {
    return Material(
      elevation: 8,
      color: Theme.of(context).cardColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$selectedCount valgt',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: allSelected ? onClear : onSelectAll,
                    child: Text(allSelected ? 'Fjern valg' : 'Velg alle'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onMarkInvoiced,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Marker fakturert'),
                    style: FilledButton.styleFrom(
                      backgroundColor: DriftProTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: PartnerModernUi.muted(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: color,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _SegChip extends StatelessWidget {
  const _SegChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected
          ? (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white)
          : Colors.transparent,
      elevation: selected && !isDark ? 1 : 0,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected
                  ? PartnerDeductionHubUi._accentDark
                  : PartnerModernUi.muted(context),
            ),
          ),
        ),
      ),
    );
  }
}

class PartnerDeductionCaseRow extends StatelessWidget {
  const PartnerDeductionCaseRow({
    super.key,
    required this.caseRow,
    required this.dateLabel,
    required this.amountLabel,
    required this.selected,
    required this.showCheckbox,
    required this.onTap,
    required this.onToggleSelect,
    this.showDeletionAudit = false,
  });

  final PartnerDeductionCase caseRow;
  final String dateLabel;
  final String amountLabel;
  final bool selected;
  final bool showCheckbox;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleSelect;
  final bool showDeletionAudit;

  @override
  Widget build(BuildContext context) {
    final wide = WebLayout.isWide(context, minWidth: 900);
    return wide ? _desktopRow(context) : _mobileRow(context);
  }

  Color _statusColor(PartnerDeductionCase c) {
    if (c.isDeleted) return Colors.red.shade700;
    if (c.isLocked) return Colors.grey.shade700;
    if (c.isInvoiced) return DriftProTheme.primaryGreen;
    return PartnerDeductionHubUi._accent;
  }

  String _statusLabel(PartnerDeductionCase c) {
    if (c.isDeleted) return 'Slettet';
    if (c.isLocked) return 'Låst';
    if (c.isInvoiced) return 'Fakturert';
    return 'Åpen';
  }

  Widget _desktopRow(BuildContext context) {
    final c = caseRow;
    final statusColor = _statusColor(c);
    final desc = c.logisticsDescription?.isNotEmpty == true
        ? c.logisticsDescription!
        : c.templateTitle;

    return Material(
      color: selected
          ? DriftProTheme.primaryGreen.withValues(alpha: 0.06)
          : PartnerModernUi.surface(context),
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              left: selected
                  ? const BorderSide(color: DriftProTheme.primaryGreen, width: 3)
                  : BorderSide.none,
              bottom: BorderSide(
                color: PartnerModernUi.border(context).withValues(alpha: 0.55),
              ),
            ),
          ),
          child: Row(
            children: [
              if (showCheckbox && !c.isInvoiced && !c.isDeleted)
                SizedBox(
                  width: 28,
                  child: Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => onToggleSelect(v == true),
                  ),
                )
              else if (showCheckbox)
                const SizedBox(width: 28),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.displayTraceRef,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    CaseTraceChip(traceRef: c.displayTraceRef, id: c.id, compact: true),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  c.partnerName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  desc,
                  style: TextStyle(fontSize: 12.5, color: PartnerModernUi.muted(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  dateLabel,
                  style: TextStyle(fontSize: 12.5, color: PartnerModernUi.muted(context)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _miniBadge(context, _statusLabel(c), color: statusColor),
                    if (c.smsSent) _miniBadge(context, 'SMS', color: Colors.teal),
                    if (c.emailSent) _miniBadge(context, 'E-post', color: Colors.blue),
                    if (c.evidenceCount > 0)
                      _miniBadge(context, '${c.evidenceCount} bevis', color: Colors.deepPurple),
                  ],
                ),
              ),
              SizedBox(
                width: 88,
                child: Text(
                  amountLabel,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: c.isInvoiced ? PartnerModernUi.muted(context) : DriftProTheme.error,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 20, color: PartnerModernUi.muted(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileRow(BuildContext context) {
    final c = caseRow;
    final statusColor = _statusColor(c);

    return Material(
      color: selected
          ? DriftProTheme.primaryGreen.withValues(alpha: 0.06)
          : PartnerModernUi.surface(context),
      child: InkWell(
        onTap: onTap,
        onLongPress: showCheckbox && !c.isInvoiced
            ? () => onToggleSelect(!selected)
            : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? DriftProTheme.primaryGreen.withValues(alpha: 0.45)
                  : PartnerModernUi.border(context),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showCheckbox && !c.isInvoiced && !c.isDeleted)
                Padding(
                  padding: const EdgeInsets.only(right: 6, top: 2),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: selected,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => onToggleSelect(v == true),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.displayTraceRef,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          amountLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: c.isInvoiced ? PartnerModernUi.muted(context) : DriftProTheme.error,
                          ),
                        ),
                      ],
                    ),
                    CaseTraceChip(traceRef: c.displayTraceRef, id: c.id, compact: true),
                    const SizedBox(height: 4),
                    Text(
                      c.partnerName,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      c.logisticsDescription?.isNotEmpty == true
                          ? c.logisticsDescription!
                          : c.templateTitle,
                      style: TextStyle(fontSize: 11.5, color: PartnerModernUi.muted(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (c.hasLogiqrmaRef)
                      PartnerDeductionLogiqRmaInfo(caseRow: c, compact: true),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        _miniBadge(context, dateLabel),
                        _miniBadge(context, _statusLabel(c), color: statusColor),
                        if (c.isInvoiced && !c.isLocked && !c.isDeleted)
                          _miniBadge(context, 'Ulåst', color: Colors.orange),
                        if (c.evidenceCount > 0)
                          _miniBadge(context, '${c.evidenceCount} bevis', color: Colors.deepPurple),
                        if (c.smsSent) _miniBadge(context, 'SMS', color: Colors.teal),
                        if (c.emailSent) _miniBadge(context, 'E-post', color: Colors.blue),
                        if (c.hasLogiqrmaRef)
                          _miniBadge(context, 'LogiqRMA', color: const Color(0xFF7C3AED)),
                      ],
                    ),
                    if (showDeletionAudit && c.isDeleted) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Slettet av ${c.deletedByName ?? 'ukjent'}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: PartnerModernUi.muted(context)),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _miniBadge(BuildContext context, String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? PartnerModernUi.muted(context)).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color ?? PartnerModernUi.muted(context),
        ),
      ),
    );
  }
}

class PartnerDeductionArchiveToolbar extends SliverPersistentHeaderDelegate {
  PartnerDeductionArchiveToolbar({
    required this.searchController,
    required this.onSearchChanged,
    required this.filter,
    required this.onFilter,
    required this.openCount,
    required this.invoicedCount,
    required this.deletedCount,
    required this.showDeletedFilter,
    required this.partnerMenu,
    required this.partnerLabel,
    required this.wide,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String filter;
  final ValueChanged<String> onFilter;
  final int openCount;
  final int invoicedCount;
  final int deletedCount;
  final bool showDeletedFilter;
  final Widget partnerMenu;
  final String partnerLabel;
  final bool wide;

  @override
  double get minExtent => wide ? 108 : 100;

  @override
  double get maxExtent => wide ? 108 : 100;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: WebLayout.prefersPointerNav
          ? WebLayout.canvasColor(context)
          : Theme.of(context).scaffoldBackgroundColor,
      elevation: overlapsContent ? 1 : 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(wide ? 20 : 14, 8, wide ? 20 : 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Søk BOT-ID, sporingskode, bedrift …',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: PartnerModernUi.surface(context),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: PartnerModernUi.border(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: PartnerModernUi.border(context)),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13.5),
                    onChanged: onSearchChanged,
                  ),
                ),
                const SizedBox(width: 8),
                partnerMenu,
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: PartnerDeductionHubUi.filterChips(
                context: context,
                filter: filter,
                onFilter: onFilter,
                openCount: openCount,
                invoicedCount: invoicedCount,
                deletedCount: deletedCount,
                showDeleted: showDeletedFilter,
              ),
            ),
            if (partnerLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  partnerLabel,
                  style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant PartnerDeductionArchiveToolbar oldDelegate) {
    return oldDelegate.filter != filter ||
        oldDelegate.openCount != openCount ||
        oldDelegate.invoicedCount != invoicedCount ||
        oldDelegate.deletedCount != deletedCount ||
        oldDelegate.showDeletedFilter != showDeletedFilter ||
        oldDelegate.partnerLabel != partnerLabel ||
        oldDelegate.wide != wide;
  }
}
