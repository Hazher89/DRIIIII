import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/web_layout.dart';
import '../../core/routing/app_paths.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/vehicle_inspection.dart';
import 'widgets/partner_inspection_hub_ui.dart';
import 'widgets/vehicle_inspection_detail_page.dart';
import 'widgets/vehicle_inspection_pdf_actions.dart';
import 'widgets/partner_modern_ui.dart';
import 'widgets/partner_ui.dart';
import '../../widgets/driftpro_loading_indicator.dart';

enum _InspectionFilter { all, deviation, openFollowUp, ok }

/// Firmavis arkiv: alle bilkontroller for alle samarbeidsbedrifter.
class VehicleInspectionHubScreen extends StatefulWidget {
  final bool embedded;
  final bool nestedScroll;
  final List<Partner> partners;

  const VehicleInspectionHubScreen({
    super.key,
    this.embedded = false,
    this.nestedScroll = false,
    required this.partners,
  });

  @override
  State<VehicleInspectionHubScreen> createState() =>
      _VehicleInspectionHubScreenState();
}

class _VehicleInspectionHubScreenState extends State<VehicleInspectionHubScreen> {
  final _search = TextEditingController();
  final _df = DateFormat('dd.MM.yyyy HH:mm');
  final _dfShort = DateFormat('dd.MM.yy');

  bool _loading = true;
  String? _error;
  List<PartnerVehicleInspection> _items = [];
  _InspectionFilter _filter = _InspectionFilter.all;
  String? _partnerFilterId;
  final Set<String> _expandedPartnerIds = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, Partner> get _partnerById => {
        for (final p in widget.partners) p.id: p,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cid = await SupabaseService.getCurrentCompanyId();
      if (cid == null) throw Exception('Fant ikke bedrift.');
      final list = await PartnerService.fetchCompanyVehicleInspections(cid);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        if (_expandedPartnerIds.isEmpty && list.isNotEmpty) {
          final grouped = <String, List<PartnerVehicleInspection>>{};
          for (final ins in list) {
            grouped.putIfAbsent(ins.partnerId, () => []).add(ins);
          }
          if (grouped.isNotEmpty) {
            _expandedPartnerIds.add(grouped.keys.first);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Partner _partnerFor(PartnerVehicleInspection ins) {
    final known = _partnerById[ins.partnerId];
    if (known != null) return known;
    return Partner(
      id: ins.partnerId,
      companyId: ins.companyId,
      name: ins.partnerDisplayName,
      tradeName: ins.partnerTradeName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  List<PartnerVehicleInspection> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _items.where((ins) {
      if (_partnerFilterId != null && ins.partnerId != _partnerFilterId) {
        return false;
      }
      switch (_filter) {
        case _InspectionFilter.all:
          break;
        case _InspectionFilter.deviation:
          if (!ins.hasDeviation) return false;
        case _InspectionFilter.openFollowUp:
          if (!ins.followUpOpen) return false;
        case _InspectionFilter.ok:
          if (ins.hasDeviation) return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        ins.partnerDisplayName,
        ins.vehicleLabel,
        ins.registrationNumber ?? '',
        ins.unitCode ?? '',
        ins.inspectedByName ?? '',
        ins.deviationNotes ?? '',
        ins.stampLine,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Map<String, List<PartnerVehicleInspection>> get _filteredGrouped {
    final map = <String, List<PartnerVehicleInspection>>{};
    for (final ins in _filtered) {
      map.putIfAbsent(ins.partnerId, () => []).add(ins);
    }
    final entries = map.entries.toList()
      ..sort((a, b) {
        final an = _partnerFor(a.value.first).displayLabel.toLowerCase();
        final bn = _partnerFor(b.value.first).displayLabel.toLowerCase();
        return an.compareTo(bn);
      });
    return {for (final e in entries) e.key: e.value};
  }

  Future<void> _exportPdf(PartnerVehicleInspection inspection) async {
    await VehicleInspectionPdfActions.openPdf(
      context,
      inspection: inspection,
      partner: _partnerFor(inspection),
    );
  }

  void _openDetail(PartnerVehicleInspection inspection) {
    VehicleInspectionDetailPage.open(
      context,
      inspection: inspection,
      partner: _partnerFor(inspection),
      canCloseFollowUp: true,
    ).then((_) => _load());
  }

  void _openPartner(String partnerId) {
    context.push(AppPaths.partnerDetailPath(partnerId, tab: 'bilkontroll'));
  }

  @override
  Widget build(BuildContext context) {
    final canvas = WebLayout.prefersPointerNav
        ? WebLayout.canvasColor(context)
        : (Theme.of(context).brightness == Brightness.dark
            ? DriftProTheme.surfaceDark
            : DriftProTheme.surfaceLight);

    final body = ColoredBox(color: canvas, child: _buildBody());
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        title: const Text('Bilkontroll'),
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    if (_loading) return const DriftProLoadingCenter();
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          PartnerEmptyState(
            icon: Icons.error_outline,
            title: 'Kunne ikke laste bilkontroller',
            subtitle: _error,
            action: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Prøv igjen'),
            ),
          ),
        ],
      );
    }

    final grouped = _filteredGrouped;
    final total = _filtered.length;
    final withDev = _filtered.where((i) => i.hasDeviation).length;
    final openFu = _filtered.where((i) => i.followUpOpen).length;
    final wide = WebLayout.isWide(context, minWidth: 900);
    final partnerOptions = widget.partners
        .map((p) => (p.id, p.displayLabel))
        .toList()
      ..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));

    return PartnerInspectionHubUi.pageShell(
      context: context,
      child: RefreshIndicator(
        onRefresh: _load,
        color: DriftProTheme.primaryGreen,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (widget.nestedScroll)
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              ),
            SliverToBoxAdapter(
              child: PartnerInspectionHubUi.header(
                context: context,
                subtitle: 'Arkiv for alle samarbeidsbedrifter · søk, filtrer, PDF',
                onRefresh: _load,
              ),
            ),
            SliverToBoxAdapter(
              child: PartnerInspectionHubUi.kpiStrip(
                context: context,
                total: total,
                withDeviation: withDev,
                openFollowUp: openFu,
                companies: grouped.length,
              ),
            ),
            SliverToBoxAdapter(
              child: PartnerInspectionHubUi.filterBar(
                context: context,
                search: _search,
                partnerFilterId: _partnerFilterId,
                onPartnerChanged: (v) => setState(() => _partnerFilterId = v),
                partners: partnerOptions,
                selectedFilter: _filter.index,
                onFilter: (i) => setState(() => _filter = _InspectionFilter.values[i]),
                filters: const [
                  ('Alle', 0),
                  ('Avvik', 1),
                  ('Åpen oppfølging', 2),
                  ('OK', 3),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: PartnerInspectionHubUi.summaryLine(
                context,
                '${grouped.length} bedrift(er) · $total kontroll(er)',
              ),
            ),
            if (grouped.isEmpty)
              const SliverToBoxAdapter(
                child: PartnerEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Ingen kontroller funnet',
                  subtitle:
                      'Lagrede bilkontroller for alle bedrifter vises her. '
                      'Prøv et annet søk eller filter.',
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final partnerId = grouped.keys.elementAt(index);
                    final list = grouped[partnerId]!;
                    final partner = _partnerFor(list.first);
                    final expanded = _expandedPartnerIds.contains(partnerId);
                    final devCount = list.where((i) => i.hasDeviation).length;
                    final openCount = list.where((i) => i.followUpOpen).length;
                    return _PartnerGroupCard(
                      wide: wide,
                      partnerName: partner.displayLabel,
                      count: list.length,
                      deviationCount: devCount,
                      openFollowUpCount: openCount,
                      expanded: expanded,
                      onToggle: () {
                        setState(() {
                          if (expanded) {
                            _expandedPartnerIds.remove(partnerId);
                          } else {
                            _expandedPartnerIds.add(partnerId);
                          }
                        });
                      },
                      onOpenPartner: () => _openPartner(partnerId),
                      children: [
                        if (wide && expanded) const _InspectionTableHeader(),
                        ...list.map(
                          (ins) => _InspectionRow(
                            wide: wide,
                            inspection: ins,
                            dateLabel: wide
                                ? _dfShort.format(ins.inspectedAt.toLocal())
                                : _df.format(ins.inspectedAt.toLocal()),
                            onTap: () => _openDetail(ins),
                            onPdf: () => _exportPdf(ins),
                          ),
                        ),
                      ],
                    );
                  },
                  childCount: grouped.length,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

extension on Partner {
  String get displayLabel {
    final trade = (tradeName ?? '').trim();
    if (trade.isNotEmpty) return trade;
    return name.trim().isEmpty ? 'Samarbeidspartner' : name.trim();
  }
}

class _PartnerGroupCard extends StatelessWidget {
  const _PartnerGroupCard({
    required this.wide,
    required this.partnerName,
    required this.count,
    required this.deviationCount,
    required this.openFollowUpCount,
    required this.expanded,
    required this.onToggle,
    required this.onOpenPartner,
    required this.children,
  });

  final bool wide;
  final String partnerName;
  final int count;
  final int deviationCount;
  final int openFollowUpCount;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenPartner;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(wide ? 20 : 14, 0, wide ? 20 : 14, 10),
      decoration: BoxDecoration(
        color: PartnerModernUi.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PartnerModernUi.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: PartnerInspectionHubUi.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partnerName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: PartnerModernUi.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            '$count kontroll${count == 1 ? '' : 'er'}',
                            if (deviationCount > 0) '$deviationCount avvik',
                            if (openFollowUpCount > 0) '$openFollowUpCount åpen oppf.',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: PartnerModernUi.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenPartner,
                    child: const Text('Åpne bedrift'),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: PartnerModernUi.border(context)),
            ...children,
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _InspectionTableHeader extends StatelessWidget {
  const _InspectionTableHeader();

  @override
  Widget build(BuildContext context) {
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          const SizedBox(width: 28),
          col('Kjøretøy', flex: 3),
          col('Dato', flex: 1),
          col('Kontrollør', flex: 2),
          col('Status', flex: 2),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _InspectionRow extends StatelessWidget {
  final PartnerVehicleInspection inspection;
  final String dateLabel;
  final VoidCallback onTap;
  final VoidCallback onPdf;
  final bool wide;

  const _InspectionRow({
    required this.inspection,
    required this.dateLabel,
    required this.onTap,
    required this.onPdf,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = inspection.hasDeviation
        ? (inspection.followUpOpen ? DriftProTheme.error : const Color(0xFFEA580C))
        : DriftProTheme.primaryGreen;
    final statusText = inspection.hasDeviation
        ? (inspection.followUpOpen ? 'Avvik · oppfølging' : 'Avvik')
        : 'OK';

    if (wide) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                inspection.hasDeviation ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  inspection.vehicleLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
                child: Text(
                  inspection.inspectedByName ?? 'Ukjent',
                  style: TextStyle(fontSize: 12.5, color: PartnerModernUi.muted(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _StatusPill(label: statusText, color: statusColor),
                ),
              ),
              IconButton(
                tooltip: 'Last ned PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                onPressed: onPdf,
              ),
            ],
          ),
        ),
      );
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      onTap: onTap,
      leading: Icon(
        inspection.hasDeviation ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
        color: statusColor,
      ),
      title: Text(
        inspection.vehicleLabel,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '$dateLabel · ${inspection.inspectedByName ?? "Ukjent"}\n$statusText'
        '${inspection.hasDeviation && (inspection.deviationNotes ?? "").isNotEmpty ? " — ${inspection.deviationNotes}" : ""}',
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: 'Last ned PDF',
        icon: const Icon(Icons.picture_as_pdf_outlined),
        onPressed: onPdf,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}
