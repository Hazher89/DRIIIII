import 'package:flutter/material.dart';

import '../../../core/layout/web_layout.dart';
import '../../../core/theme/app_theme.dart';
import 'partner_modern_ui.dart';

/// Delt Bilkontroll-UI — kompakt admin på web, ryddig mobil.
abstract final class PartnerInspectionHubUi {
  static const accent = Color(0xFF2563EB);

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

  static Widget header({
    required BuildContext context,
    required String subtitle,
    VoidCallback? onRefresh,
    bool refreshing = false,
  }) {
    final wide = WebLayout.isWide(context, minWidth: 800);
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 20 : 14, wide ? 16 : 10, wide ? 20 : 14, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.fact_check_rounded, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bilkontroll',
                  style: TextStyle(
                    fontSize: wide ? 22 : 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: PartnerModernUi.textPrimary(context),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: PartnerModernUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(
              tooltip: 'Oppdater',
              onPressed: refreshing ? null : onRefresh,
              icon: refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.refresh_rounded, color: PartnerModernUi.muted(context)),
            ),
        ],
      ),
    );
  }

  static Widget kpiStrip({
    required BuildContext context,
    required int total,
    required int withDeviation,
    required int openFollowUp,
    int? companies,
  }) {
    final wide = WebLayout.isWide(context, minWidth: 800);
    final items = <(String, String, Color)>[
      ('Kontroller', '$total', accent),
      (
        'Med avvik',
        '$withDeviation',
        withDeviation > 0 ? const Color(0xFFEA580C) : DriftProTheme.primaryGreen,
      ),
      (
        'Åpen oppfølging',
        '$openFollowUp',
        openFollowUp > 0 ? DriftProTheme.error : DriftProTheme.primaryGreen,
      ),
      if (companies != null) ('Bedrifter', '$companies', const Color(0xFF0F766E)),
    ];

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _KpiCard(label: items[i].$1, value: items[i].$2, color: items[i].$3),
              ),
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

  static Widget filterBar({
    required BuildContext context,
    required TextEditingController search,
    required String? partnerFilterId,
    required ValueChanged<String?> onPartnerChanged,
    required List<(String id, String label)> partners,
    required int selectedFilter,
    required ValueChanged<int> onFilter,
    required List<(String label, int index)> filters,
  }) {
    final wide = WebLayout.isWide(context, minWidth: 800);
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 20 : 14, 0, wide ? 20 : 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              children: [
                Expanded(flex: 3, child: _searchField(context, search)),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _partnerDropdown(
                    context,
                    partnerFilterId,
                    onPartnerChanged,
                    partners,
                  ),
                ),
              ],
            )
          else ...[
            _searchField(context, search),
            const SizedBox(height: 8),
            _partnerDropdown(context, partnerFilterId, onPartnerChanged, partners),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _segmentedFilters(
              context: context,
              selected: selectedFilter,
              onFilter: onFilter,
              filters: filters,
              wide: wide,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _searchField(BuildContext context, TextEditingController search) {
    return TextField(
      controller: search,
      decoration: InputDecoration(
        hintText: 'Søk bedrift, reg.nr, MAVI, kontrollør…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: search.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () {
                  search.clear();
                },
              ),
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
    );
  }

  static Widget _partnerDropdown(
    BuildContext context,
    String? partnerFilterId,
    ValueChanged<String?> onPartnerChanged,
    List<(String id, String label)> partners,
  ) {
    return DropdownButtonFormField<String?>(
      value: partnerFilterId,
      decoration: InputDecoration(
        labelText: 'Bedrift',
        isDense: true,
        filled: true,
        fillColor: PartnerModernUi.surface(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Alle bedrifter')),
        ...partners.map(
          (p) => DropdownMenuItem<String?>(value: p.$1, child: Text(p.$2)),
        ),
      ],
      onChanged: onPartnerChanged,
    );
  }

  static Widget _segmentedFilters({
    required BuildContext context,
    required int selected,
    required ValueChanged<int> onFilter,
    required List<(String label, int index)> filters,
    required bool wide,
  }) {
    if (wide) {
      return Container(
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
            for (final f in filters)
              _SegChip(
                label: f.$1,
                selected: selected == f.$2,
                onTap: () => onFilter(f.$2),
              ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            FilterChip(
              label: Text(filters[i].$1, style: const TextStyle(fontSize: 12)),
              selected: selected == filters[i].$2,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              selectedColor: accent.withValues(alpha: 0.14),
              onSelected: (_) => onFilter(filters[i].$2),
            ),
          ],
        ],
      ),
    );
  }

  static Widget summaryLine(BuildContext context, String text) {
    final wide = WebLayout.isWide(context, minWidth: 800);
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 20 : 14, 0, wide ? 20 : 14, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: PartnerModernUi.muted(context),
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
                  ? PartnerInspectionHubUi.accent
                  : PartnerModernUi.muted(context),
            ),
          ),
        ),
      ),
    );
  }
}
