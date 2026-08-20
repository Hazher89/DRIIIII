import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/case_trace/case_trace.dart';
import '../../../core/layout/web_layout.dart';
import '../../../core/services/partner/partner_deduction_access.dart';
import '../../../core/services/partner/partner_deduction_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/partner/partner.dart';
import '../../../models/partner/partner_deduction_case.dart';
import '../../../models/partner/partner_deduction_stats.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/driftpro_loading_indicator.dart';
import 'partner_deduction_case_sheet.dart';
import 'partner_deduction_hub_ui.dart';
import 'partner_modern_ui.dart';

class PartnerDeductionArchivePanel extends StatefulWidget {
  const PartnerDeductionArchivePanel({
    super.key,
    required this.profile,
    required this.onChanged,
    required this.partners,
    required this.onNewCase,
    this.nestedScroll = false,
    this.canManageNotifications = false,
    this.onOpenSettings,
  });

  final UserProfile? profile;
  final VoidCallback onChanged;
  final List<Partner> partners;
  final VoidCallback onNewCase;
  final bool nestedScroll;
  final bool canManageNotifications;
  final VoidCallback? onOpenSettings;

  @override
  State<PartnerDeductionArchivePanel> createState() => _PartnerDeductionArchivePanelState();
}

class _PartnerDeductionArchivePanelState extends State<PartnerDeductionArchivePanel> {
  List<PartnerDeductionCase> _allCases = [];
  List<PartnerDeductionCase> _cases = [];
  final Set<String> _selected = {};
  bool _loading = true;
  String? _companyId;
  String _filter = 'open';
  String _search = '';
  String? _partnerFilterId;
  PartnerDeductionStats? _stats;
  final _searchCtrl = TextEditingController();

  bool get _canInvoice => PartnerDeductionAccess.canManageArchive(widget.profile);
  bool get _canUnlock => PartnerDeductionAccess.canUnlockAndDelete(widget.profile);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Partner? _partnerFor(PartnerDeductionCase c) {
    for (final p in widget.partners) {
      if (p.id == c.partnerId) return p;
    }
    return Partner(
      id: c.partnerId,
      companyId: c.companyId,
      name: c.partnerName,
      createdAt: DateTime.now(),
    );
  }

  List<PartnerDeductionCase> get _visibleCases {
    final q = _search.trim().toLowerCase();
    return _cases.where((c) {
      if (_partnerFilterId != null && c.partnerId != _partnerFilterId) return false;
      if (q.isEmpty) return true;
      return CaseTrace.matchesQuery(
        query: q,
        traceRef: c.displayTraceRef,
        caseNumber: c.caseNumber,
        id: c.id,
        logiqrmaCaseNumber: c.logiqrmaCaseNumber,
        voucherNumber: c.voucherNumber,
        title: c.templateTitle,
        partnerName: c.partnerName,
      ) || (c.comment ?? '').toLowerCase().contains(q);
    }).toList();
  }

  int get _openTotal => _allCases.where((c) => !c.isInvoiced && !c.isDeleted).length;
  int get _invoicedTotal =>
      _allCases.where((c) => c.isInvoiced && !c.isDeleted).length;
  int get _deletedTotal => _allCases.where((c) => c.isDeleted).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cid = await SupabaseService.getCurrentCompanyId();
    if (cid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _companyId = cid;
    final stats = await PartnerDeductionService.fetchStats(cid);
    final rows = await PartnerDeductionService.listCases(companyId: cid);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _allCases = rows;
      _cases = _filteredCases(rows);
      _loading = false;
    });
  }

  List<PartnerDeductionCase> _filteredCases(List<PartnerDeductionCase> rows) {
    return switch (_filter) {
      'invoiced' => rows.where((c) => c.isInvoiced && !c.isDeleted).toList(),
      'open' => rows.where((c) => !c.isInvoiced && !c.isDeleted).toList(),
      'deleted' => rows.where((c) => c.isDeleted).toList(),
      _ => rows,
    };
  }

  Future<void> _reloadCases() async {
    final cid = _companyId;
    if (cid == null) return;
    final stats = await PartnerDeductionService.fetchStats(cid);
    final rows = await PartnerDeductionService.listCases(companyId: cid);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _allCases = rows;
      _cases = _filteredCases(rows);
      _selected.clear();
    });
  }

  Future<void> _markInvoiced({List<String>? ids}) async {
    final cid = _companyId;
    final target = ids ?? _selected.toList();
    if (cid == null || target.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marker som fakturert'),
        content: Text(
          target.length == 1
              ? 'Marker saken som fakturert/trukket?'
              : 'Marker ${target.length} saker som fakturert/trukket?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bekreft')),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    try {
      final n = await PartnerDeductionService.markInvoiced(
        companyId: cid,
        caseIds: target,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$n sak(er) markert som fakturert og låst')),
      );
      widget.onChanged();
      await _reloadCases();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _onFilterChanged(String value) {
    setState(() {
      _filter = value;
      _cases = _filteredCases(_allCases);
      _selected.clear();
    });
  }

  String get _partnerLabel {
    if (_partnerFilterId == null) return '';
    for (final p in widget.partners) {
      if (p.id == _partnerFilterId) return 'Bedrift: ${p.name}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const DriftProLoadingCenter();

    final df = DateFormat('dd.MM.yy');
    final money = NumberFormat.currency(locale: 'nb_NO', symbol: 'kr', decimalDigits: 0);
    final stats = _stats;
    final activePartners = widget.partners.where((p) => p.isActive).length;
    final visible = _visibleCases;
    final openSelectable = visible.where((c) => !c.isInvoiced && !c.isDeleted).toList();
    final allSelected = openSelectable.isNotEmpty &&
        openSelectable.every((c) => _selected.contains(c.id));
    final wide = WebLayout.isWide(context, minWidth: 900);
    final showCheckbox = _canInvoice && _filter == 'open';

    final slivers = <Widget>[
      if (widget.nestedScroll)
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
      SliverToBoxAdapter(
        child: PartnerDeductionHubUi.compactHeader(
          context: context,
          activePartners: activePartners,
          onNewCase: widget.onNewCase,
          onOpenSettings: widget.canManageNotifications ? widget.onOpenSettings : null,
          canManageArchive: _canInvoice,
        ),
      ),
      if (stats != null)
        SliverToBoxAdapter(
          child: PartnerDeductionHubUi.kpiStrip(
            context: context,
            openCount: '${stats.openCount}',
            openAmount: money.format(stats.openAmount),
            invoicedCount: '${stats.invoicedCount}',
            invoicedAmount: money.format(stats.invoicedAmount),
            evidenceCount: '${stats.evidenceCount}',
          ),
        ),
      SliverPersistentHeader(
        pinned: true,
        delegate: PartnerDeductionArchiveToolbar(
          searchController: _searchCtrl,
          onSearchChanged: (v) => setState(() => _search = v),
          filter: _filter,
          onFilter: _onFilterChanged,
          openCount: stats?.openCount ?? _openTotal,
          invoicedCount: stats?.invoicedCount ?? _invoicedTotal,
          deletedCount: _deletedTotal,
          showDeletedFilter: _canUnlock,
          partnerLabel: _partnerLabel,
          wide: WebLayout.isWide(context, minWidth: 800),
          partnerMenu: widget.partners.isEmpty
              ? const SizedBox.shrink()
              : PopupMenuButton<String?>(
                  tooltip: 'Filtrer bedrift',
                  icon: Icon(
                    _partnerFilterId == null
                        ? Icons.filter_list_rounded
                        : Icons.filter_alt_rounded,
                    size: 22,
                    color: _partnerFilterId == null
                        ? PartnerModernUi.muted(context)
                        : const Color(0xFFEA580C),
                  ),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: null, child: Text('Alle bedrifter')),
                    ...widget.partners.map(
                      (p) => PopupMenuItem(value: p.id, child: Text(p.name)),
                    ),
                  ],
                  onSelected: (v) => setState(() => _partnerFilterId = v),
                ),
        ),
      ),
      if (_canInvoice && _filter == 'open')
        SliverToBoxAdapter(
          child: PartnerDeductionHubUi.summaryLine(
            context: context,
            text: _selected.isEmpty
                ? 'Velg åpne saker for å markere som fakturert/trukket'
                : '${_selected.length} sak(er) valgt · ${money.format(_selectedAmount)}',
            highlight: _selected.isNotEmpty,
          ),
        )
      else if (!_canInvoice)
        SliverToBoxAdapter(
          child: PartnerDeductionHubUi.summaryLine(
            context: context,
            text: 'Kun økonomi/superadmin kan markere som fakturert',
          ),
        ),
      if (visible.isNotEmpty)
        SliverToBoxAdapter(
          child: PartnerDeductionHubUi.tableHeader(
            context,
            showCheckbox: showCheckbox,
          ),
        ),
      if (visible.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 40, color: PartnerModernUi.muted(context)),
                  const SizedBox(height: 12),
                  Text(
                    switch (_filter) {
                      'open' => 'Ingen åpne saker',
                      'invoiced' => 'Ingen fakturerte saker',
                      'deleted' => 'Ingen slettede saker',
                      _ => 'Ingen saker i arkivet',
                    },
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: PartnerModernUi.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Opprett trekk med «Nytt trekk»',
                    style: TextStyle(fontSize: 12.5, color: PartnerModernUi.muted(context)),
                  ),
                ],
              ),
            ),
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final c = visible[i];
              return PartnerDeductionCaseRow(
                caseRow: c,
                dateLabel: df.format(c.createdAt),
                amountLabel: money.format(c.amountNok),
                selected: _selected.contains(c.id),
                showCheckbox: showCheckbox,
                showDeletionAudit: _canUnlock,
                onTap: () async {
                  await PartnerDeductionCaseSheet.show(
                    context,
                    caseRow: c,
                    partner: _partnerFor(c)!,
                    profile: widget.profile,
                    canManageArchive: _canInvoice,
                    canUnlockAndDelete: _canUnlock,
                    onMarkInvoiced: c.isInvoiced || c.isDeleted
                        ? null
                        : () => _markInvoiced(ids: [c.id]),
                    onChanged: () {
                      widget.onChanged();
                      _reloadCases();
                    },
                  );
                },
                onToggleSelect: (v) => setState(() {
                  if (v) {
                    _selected.add(c.id);
                  } else {
                    _selected.remove(c.id);
                  }
                }),
              );
            },
            childCount: visible.length,
          ),
        ),
      if (wide && visible.isNotEmpty)
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            height: 12,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: PartnerModernUi.border(context).withValues(alpha: 0.8)),
                right: BorderSide(color: PartnerModernUi.border(context).withValues(alpha: 0.8)),
                bottom: BorderSide(color: PartnerModernUi.border(context).withValues(alpha: 0.8)),
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
          ),
        ),
      if (_canInvoice && _selected.isNotEmpty)
        SliverToBoxAdapter(
          child: PartnerDeductionHubUi.bulkBar(
            context: context,
            selectedCount: _selected.length,
            allSelected: allSelected,
            onSelectAll: () => setState(() {
              _selected
                ..clear()
                ..addAll(openSelectable.map((c) => c.id));
            }),
            onClear: () => setState(_selected.clear),
            onMarkInvoiced: () => _markInvoiced(),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];

    return PartnerDeductionHubUi.pageShell(
      context: context,
      child: RefreshIndicator(
        onRefresh: _load,
        color: DriftProTheme.primaryGreen,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        ),
      ),
    );
  }

  double get _selectedAmount {
    var sum = 0.0;
    for (final c in _allCases) {
      if (_selected.contains(c.id)) sum += c.amountNok;
    }
    return sum;
  }
}
