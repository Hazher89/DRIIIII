import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner_deduction_case.dart';
import '../../../core/case_trace/case_trace_chip.dart';
import 'partner_deduction_logiqrma_panel.dart';
import 'partner_modern_ui.dart';

/// Kompakte UI-komponenter for Bot/Trekk — én scrollbar, ingen store faner.
class PartnerDeductionHubUi {
  PartnerDeductionHubUi._();

  static Widget compactHeader({
    required BuildContext context,
    required int activePartners,
    required VoidCallback onNewCase,
    VoidCallback? onOpenSettings,
    bool canManageArchive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bot / Trekk',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: PartnerModernUi.textPrimary(context),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  canManageArchive
                      ? 'Arkiv og fakturering — $activePartners aktive bedrifter'
                      : 'Registrer trekk og følg arkiv — $activePartners aktive bedrifter',
                  style: TextStyle(fontSize: 12, height: 1.35, color: PartnerModernUi.muted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (onOpenSettings != null)
            IconButton(
              tooltip: 'Varsler',
              visualDensity: VisualDensity.compact,
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune_rounded, size: 20),
            ),
          FilledButton.icon(
            onPressed: onNewCase,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Nytt'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              backgroundColor: const Color(0xFFEA580C),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: PartnerModernKpiGrid(
        items: [
          ('Åpne', openCount),
          ('Åpne kr', openAmount),
          ('Fakturert', invoicedCount),
          ('Bevis', evidenceCount),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _chip(context, 'Åpne ($openCount)', 'open', filter, onFilter),
          const SizedBox(width: 6),
          _chip(context, 'Fakturert ($invoicedCount)', 'invoiced', filter, onFilter),
          if (showDeleted) ...[
            const SizedBox(width: 6),
            _chip(context, 'Slettet ($deletedCount)', 'deleted', filter, onFilter),
          ],
          const SizedBox(width: 6),
          _chip(context, 'Alle', 'all', filter, onFilter),
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
      selectedColor: const Color(0xFFEA580C).withValues(alpha: 0.14),
      checkmarkColor: const Color(0xFFEA580C),
      labelStyle: TextStyle(
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        color: active ? const Color(0xFF9A3412) : PartnerModernUi.muted(context),
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          color: highlight ? const Color(0xFF9A3412) : PartnerModernUi.muted(context),
        ),
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
      elevation: 6,
      color: Theme.of(context).cardColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$selectedCount valgt',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: allSelected ? onClear : onSelectAll,
                child: Text(allSelected ? 'Fjern' : 'Velg alle'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: onMarkInvoiced,
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Fakturert'),
                style: FilledButton.styleFrom(
                  backgroundColor: DriftProTheme.primaryGreen,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
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
    final c = caseRow;
    final statusColor = c.isDeleted
        ? Colors.red.shade700
        : c.isLocked
            ? Colors.grey
            : const Color(0xFFEA580C);

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: PartnerModernUi.border(context).withValues(alpha: 0.6)),
              left: selected
                  ? BorderSide(color: DriftProTheme.primaryGreen, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showCheckbox && !c.isInvoiced && !c.isDeleted)
                Padding(
                  padding: const EdgeInsets.only(right: 4, top: 2),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.displayTraceRef,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              CaseTraceChip(
                                traceRef: c.displayTraceRef,
                                id: c.id,
                                compact: true,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          amountLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c.isInvoiced ? PartnerModernUi.muted(context) : DriftProTheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.partnerName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PartnerModernUi.textPrimary(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      c.logisticsDescription?.isNotEmpty == true
                          ? c.logisticsDescription!
                          : c.templateTitle,
                      style: TextStyle(fontSize: 11, color: PartnerModernUi.muted(context)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (c.hasLogiqrmaRef)
                      PartnerDeductionLogiqRmaInfo(caseRow: c, compact: true),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 3,
                      children: [
                        _miniBadge(context, dateLabel),
                        if (c.isDeleted)
                          _miniBadge(context, 'Slettet', color: Colors.red.shade700)
                        else if (c.isLocked)
                          _miniBadge(context, 'Låst', color: Colors.grey.shade700)
                        else
                          _miniBadge(context, c.isInvoiced ? 'Fakturert' : 'Åpen', color: statusColor),
                        if (c.isInvoiced && !c.isLocked && !c.isDeleted)
                          _miniBadge(context, 'Ulåst', color: Colors.orange),
                        if (c.evidenceCount > 0)
                          _miniBadge(context, '${c.evidenceCount} bevis', color: Colors.deepPurple),
                        if (c.smsSent) _miniBadge(context, 'SMS', color: Colors.teal),
                        if (c.emailSent) _miniBadge(context, 'E-post', color: Colors.blue),
                        if (c.hasLogiqrmaRef) _miniBadge(context, 'LogiqRMA', color: const Color(0xFF7C3AED)),
                        if (c.voucherNumber?.isNotEmpty == true)
                          _miniBadge(context, 'Bilag ${c.voucherNumber}', color: const Color(0xFF2563EB)),
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
                      if (c.deletionComment?.isNotEmpty == true)
                        Text(
                          '«${c.deletionComment}»',
                          style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ],
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

  static Widget _miniBadge(BuildContext context, String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? PartnerModernUi.muted(context)).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color ?? PartnerModernUi.muted(context)),
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

  @override
  double get minExtent => 96;

  @override
  double get maxExtent => 96;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: overlapsContent ? 1 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Søk BOT-ID, sporingskode, bedrift …',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: onSearchChanged,
                  ),
                ),
                const SizedBox(width: 8),
                partnerMenu,
              ],
            ),
          ),
          PartnerDeductionHubUi.filterChips(
            context: context,
            filter: filter,
            onFilter: onFilter,
            openCount: openCount,
            invoicedCount: invoicedCount,
            deletedCount: deletedCount,
            showDeleted: showDeletedFilter,
          ),
          if (partnerLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                partnerLabel,
                style: TextStyle(fontSize: 10, color: PartnerModernUi.muted(context)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
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
        oldDelegate.partnerLabel != partnerLabel;
  }
}
