import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/routing/app_paths.dart';
import '../../core/services/hms/hms_pdf_export_service.dart';
import '../../core/services/partner/partner_service.dart';
import '../../core/services/partner/vehicle_inspection_pdf.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/partner/partner.dart';
import '../../models/partner/vehicle_inspection.dart';
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

  bool _loading = true;
  String? _error;
  List<PartnerVehicleInspection> _items = [];
  _InspectionFilter _filter = _InspectionFilter.all;
  String? _partnerFilterId;
  final Set<String> _expandedPartnerIds = {};

  @override
  void initState() {
    super.initState();
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
    final partner = _partnerFor(inspection);
    await HmsPdfExportService.runWithFeedback(
      context,
      fileName: VehicleInspectionPdf.fileNameFor(inspection),
      generate: () => VehicleInspectionPdf.generate(
        inspection: inspection,
        partner: partner,
        inspectorName: inspection.inspectedByName,
      ),
    );
  }

  void _openPartner(String partnerId) {
    context.push(AppPaths.partnerDetailPath(partnerId, tab: 'bilkontroll'));
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilkontroll-arkiv'),
        actions: [
          IconButton(
            tooltip: 'Oppdater',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
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

    return RefreshIndicator(
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PartnerHeroBanner(
                    compact: true,
                    title: 'Bilkontroll-arkiv',
                    subtitle:
                        'Alle lagrede kontroller for alle samarbeidsbedrifter. '
                        'Søk, filtrer og last ned PDF.',
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.fact_check_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _KpiChip(
                          label: 'Kontroller',
                          value: '$total',
                          color: DriftProTheme.accentBlue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _KpiChip(
                          label: 'Med avvik',
                          value: '$withDev',
                          color: withDev > 0
                              ? DriftProTheme.warning
                              : DriftProTheme.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _KpiChip(
                          label: 'Åpen oppf.',
                          value: '$openFu',
                          color: openFu > 0
                              ? DriftProTheme.error
                              : DriftProTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Søk bedrift, reg.nr, MAVI, kontrollør…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    value: _partnerFilterId,
                    decoration: const InputDecoration(
                      labelText: 'Bedrift',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Alle bedrifter'),
                      ),
                      ...widget.partners.map(
                        (p) => DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text(p.displayLabel),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _partnerFilterId = v),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'Alle',
                        selected: _filter == _InspectionFilter.all,
                        onTap: () =>
                            setState(() => _filter = _InspectionFilter.all),
                      ),
                      _FilterChip(
                        label: 'Avvik',
                        selected: _filter == _InspectionFilter.deviation,
                        onTap: () => setState(
                          () => _filter = _InspectionFilter.deviation,
                        ),
                      ),
                      _FilterChip(
                        label: 'Åpen oppfølging',
                        selected: _filter == _InspectionFilter.openFollowUp,
                        onTap: () => setState(
                          () => _filter = _InspectionFilter.openFollowUp,
                        ),
                      ),
                      _FilterChip(
                        label: 'OK',
                        selected: _filter == _InspectionFilter.ok,
                        onTap: () =>
                            setState(() => _filter = _InspectionFilter.ok),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${grouped.length} bedrift(er) · $total kontroll(er)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Material(
                      color: Theme.of(context).cardColor,
                      borderRadius:
                          BorderRadius.circular(DriftProTheme.radiusMd),
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(DriftProTheme.radiusMd),
                        onTap: () {
                          setState(() {
                            if (expanded) {
                              _expandedPartnerIds.remove(partnerId);
                            } else {
                              _expandedPartnerIds.add(partnerId);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    expanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    color: DriftProTheme.primaryGreen,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          partner.displayLabel,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${list.length} kontroll(er)'
                                          '${devCount > 0 ? ' · $devCount med avvik' : ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _openPartner(partnerId),
                                    child: const Text('Åpne'),
                                  ),
                                ],
                              ),
                              if (expanded) ...[
                                const Divider(height: 16),
                                ...list.map((ins) => _InspectionRow(
                                      inspection: ins,
                                      dateLabel:
                                          _df.format(ins.inspectedAt.toLocal()),
                                      onPdf: () => _exportPdf(ins),
                                    )),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: grouped.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
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

class _KpiChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _KpiChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: DriftProTheme.primaryGreen.withValues(alpha: 0.18),
      checkmarkColor: DriftProTheme.primaryGreen,
    );
  }
}

class _InspectionRow extends StatelessWidget {
  final PartnerVehicleInspection inspection;
  final String dateLabel;
  final VoidCallback onPdf;

  const _InspectionRow({
    required this.inspection,
    required this.dateLabel,
    required this.onPdf,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = inspection.hasDeviation
        ? Colors.orange.shade700
        : Colors.green.shade700;
    final statusText = inspection.hasDeviation
        ? (inspection.followUpOpen
            ? 'Avvik · åpen oppfølging'
            : 'Avvik')
        : 'OK';

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        inspection.hasDeviation ? Icons.warning_amber : Icons.check_circle,
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
