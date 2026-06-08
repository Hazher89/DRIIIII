import 'package:flutter/material.dart';

import '../../core/constants/leave_rules.dart';
import '../../core/services/absence/vacation_admin_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/vacation_distribute_wizard.dart';
import '../../widgets/driftpro_loading_indicator.dart';

/// Avansert ferieadministrasjon — oversiktlig for admin.
class VacationAdminScreen extends StatefulWidget {
  final String companyId;
  final CompanyLeaveSettings companySettings;

  const VacationAdminScreen({
    super.key,
    required this.companyId,
    required this.companySettings,
  });

  @override
  State<VacationAdminScreen> createState() => _VacationAdminScreenState();
}

class _VacationAdminScreenState extends State<VacationAdminScreen> {
  bool _loading = true;
  String? _error;
  List<EmployeeVacationOverview> _all = [];
  int _selectedYear = VacationYearWindow.currentYear;
  VacationEmployeeFilter _filter = VacationEmployeeFilter.all;
  final _searchCtrl = TextEditingController();
  String _search = '';
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await VacationAdminService.loadCompanyOverview(
        companyId: widget.companyId,
      );
      setState(() => _all = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<EmployeeVacationOverview> get _filtered =>
      VacationAdminService.filterEmployees(
        _all,
        filter: _filter,
        year: _selectedYear,
        maxCarryover: widget.companySettings.maxVacationCarryover,
        search: _search,
      );

  VacationYearSummary get _yearSummary =>
      VacationAdminService.summarizeYear(
        overviews: _all,
        year: _selectedYear,
        maxCarryover: widget.companySettings.maxVacationCarryover,
      );

  int get _missingAllocation => _all.where((o) => !o.hasAllocationFor(_selectedYear)).length;

  Future<void> _openDistributeWizard({List<String>? ids}) async {
    final ok = await VacationDistributeWizard.show(
      context,
      companyId: widget.companyId,
      year: _selectedYear,
      allEmployees: _all,
      preselectedUserIds: ids,
    );
    if (ok == true) {
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Ferieadministrasjon'),
        actions: [
          if (_selectionMode)
            TextButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedIds.clear();
              }),
              child: const Text('Avbryt'),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const DriftProLoadingCenter()
          : _error != null
              ? _errorView()
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(child: _yearHeader(isDark)),
                            SliverToBoxAdapter(child: _summaryBanner(isDark)),
                            SliverToBoxAdapter(child: _actionCards(isDark)),
                            SliverToBoxAdapter(child: _filterBar(isDark)),
                            _employeeTableSliver(isDark),
                            const SliverToBoxAdapter(child: SizedBox(height: 88)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _selectionMode ? _selectionBottomBar() : _mainBottomBar(isDark),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: DriftProTheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Prøv igjen')),
          ],
        ),
      ),
    );
  }

  /// Steg 1: tydelig valgt år
  Widget _yearHeader(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Du administrerer feriedager for', style: DriftProTheme.caption),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '$_selectedYear',
                style: DriftProTheme.headingXl.copyWith(
                  fontSize: 36,
                  color: DriftProTheme.primaryGreen,
                ),
              ),
              if (_selectedYear == VacationYearWindow.currentYear) ...[
                const SizedBox(width: 8),
                _badge('I år', DriftProTheme.primaryGreen),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: VacationYearWindow.years.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final y = VacationYearWindow.years[i];
                final selected = y == _selectedYear;
                return FilterChip(
                  label: Text('$y'),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedYear = y),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Steg 2: oversikt i én setning
  Widget _summaryBanner(bool isDark) {
    final s = _yearSummary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              DriftProTheme.primaryGreen.withValues(alpha: 0.15),
              DriftProTheme.primaryGreen.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Oversikt for $_selectedYear', style: DriftProTheme.labelLg),
            const SizedBox(height: 10),
            Text(
              '${s.withAllocation} av ${s.employeeCount} ansatte har feriedager. '
              'Totalt ${s.totalRemaining} dager igjen å ta ut. '
              '${s.totalCarryoverEligible} dager kan overføres til ${_selectedYear + 1}.',
              style: DriftProTheme.bodySm.copyWith(height: 1.45),
            ),
            if (_missingAllocation > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: DriftProTheme.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_missingAllocation ansatte mangler tildeling — bruk «Del ut feriedager» nedenfor.',
                      style: DriftProTheme.bodySm.copyWith(
                        color: DriftProTheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Steg 3: tydelige handlinger
  Widget _actionCards(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hva vil du gjøre?', style: DriftProTheme.headingSm),
          const SizedBox(height: 10),
          _actionCard(
            isDark: isDark,
            icon: Icons.groups_rounded,
            color: DriftProTheme.primaryGreen,
            title: 'Del ut til alle',
            subtitle:
                'Gi samme antall dager til alle ${_all.length} ansatte for $_selectedYear',
            onTap: () => _openDistributeWizard(
              ids: _all.map((e) => e.employee.id).toList(),
            ),
          ),
          const SizedBox(height: 8),
          _actionCard(
            isDark: isDark,
            icon: Icons.checklist_rounded,
            color: Colors.blue,
            title: 'Velg ansatte',
            subtitle: 'Kryss av hvem som skal få (eller endre) feriedager',
            onTap: () => setState(() {
              _selectionMode = true;
              _selectedIds.clear();
            }),
          ),
          const SizedBox(height: 8),
          _actionCard(
            isDark: isDark,
            icon: Icons.swap_horiz_rounded,
            color: Colors.orange,
            title: 'Overfør restferie',
            subtitle:
                'Flytt ubrukte dager fra $_selectedYear til ${_selectedYear + 1} (maks ${widget.companySettings.maxVacationCarryover} d/ pers)',
            onTap: _carryoverAll,
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? DriftProTheme.cardDark : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: DriftProTheme.labelLg),
                    const SizedBox(height: 2),
                    Text(subtitle, style: DriftProTheme.caption),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Søk på navn…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('Alle (${_all.length})', VacationEmployeeFilter.all),
                _filterChip('Har ferie igjen', VacationEmployeeFilter.hasRemaining),
                _filterChip('Mangler tildeling ($_missingAllocation)',
                    VacationEmployeeFilter.noAllocation),
                _filterChip('Kan overføre', VacationEmployeeFilter.canCarryover),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Viser ${_filtered.length} ansatte',
            style: DriftProTheme.caption,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _filterChip(String label, VacationEmployeeFilter f) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: _filter == f,
        onSelected: (_) => setState(() => _filter = f),
      ),
    );
  }

  Widget _employeeTableSliver(bool isDark) {
    final list = _filtered;
    if (list.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('Ingen ansatte matcher filteret.')),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i == 0) return _tableHeader(isDark);
            final o = list[i - 1];
            return _tableRow(o, isDark);
          },
          childCount: list.length + 1,
        ),
      ),
    );
  }

  Widget _tableHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          if (_selectionMode) const SizedBox(width: 40),
          const Expanded(flex: 3, child: Text('Ansatt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          const Expanded(child: Text('Tildelt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
          const Expanded(child: Text('Brukt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
          const Expanded(child: Text('Igjen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _tableRow(EmployeeVacationOverview o, bool isDark) {
    final q = o.quotaFor(_selectedYear);
    final remaining = o.remainingFor(_selectedYear);
    final hasAlloc = q != null;
    final selected = _selectedIds.contains(o.employee.id);

    Color statusColor;
    String statusLabel;
    if (!hasAlloc) {
      statusColor = DriftProTheme.warning;
      statusLabel = 'Mangler';
    } else if (remaining == 0) {
      statusColor = DriftProTheme.error;
      statusLabel = 'Oppbrukt';
    } else {
      statusColor = DriftProTheme.primaryGreen;
      statusLabel = 'OK';
    }

    return Material(
      color: selected
          ? DriftProTheme.primaryGreen.withValues(alpha: 0.1)
          : (isDark ? DriftProTheme.cardDark : Colors.white),
      child: InkWell(
        onTap: _selectionMode
            ? () => setState(() {
                if (selected) {
                  _selectedIds.remove(o.employee.id);
                } else {
                  _selectedIds.add(o.employee.id);
                }
              })
            : () => _openDistributeWizard(ids: [o.employee.id]),
        onLongPress: () => setState(() {
          _selectionMode = true;
          _selectedIds.add(o.employee.id);
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade200,
              ),
            ),
          ),
          child: Row(
            children: [
              if (_selectionMode)
                SizedBox(
                  width: 40,
                  child: Checkbox(
                    value: selected,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedIds.add(o.employee.id);
                      } else {
                        _selectedIds.remove(o.employee.id);
                      }
                    }),
                  ),
                ),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      child: Text(o.employee.initials, style: const TextStyle(fontSize: 10)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.employee.fullName,
                            style: DriftProTheme.labelMd,
                            overflow: TextOverflow.ellipsis,
                          ),
                          _badge(statusLabel, statusColor),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  hasAlloc ? '${q.vacationDaysTotal}' : '—',
                  textAlign: TextAlign.center,
                  style: DriftProTheme.bodySm,
                ),
              ),
              Expanded(
                child: Text(
                  hasAlloc ? '${q.vacationDaysUsed}' : '—',
                  textAlign: TextAlign.center,
                  style: DriftProTheme.bodySm,
                ),
              ),
              Expanded(
                child: Text(
                  hasAlloc ? '$remaining' : '—',
                  textAlign: TextAlign.center,
                  style: DriftProTheme.labelMd.copyWith(
                    color: remaining > 0 ? DriftProTheme.primaryGreen : DriftProTheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Rediger feriedager',
                onPressed: () => _openDistributeWizard(ids: [o.employee.id]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mainBottomBar(bool isDark) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: FilledButton.icon(
          onPressed: () => _openDistributeWizard(ids: _all.map((e) => e.employee.id).toList()),
          icon: const Icon(Icons.beach_access),
          label: Text('Del ut feriedager for $_selectedYear'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ),
    );
  }

  Widget _selectionBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        color: DriftProTheme.primaryGreen.withValues(alpha: 0.08),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_selectedIds.length} valgt',
                style: DriftProTheme.labelLg,
              ),
            ),
            FilledButton(
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => _openDistributeWizard(ids: _selectedIds.toList()),
              child: const Text('Del ut feriedager'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _carryoverAll() async {
    final from = _selectedYear;
    final to = from + 1;
    if (to > VacationYearWindow.toYear) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kan ikke overføre utenfor planleggingsvinduet.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Overfør restferie for alle'),
        content: Text(
          'Alle ansatte med ubrukte feriedager i $from får resten overført til $to '
          '(maks ${widget.companySettings.maxVacationCarryover} dager hver).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Overfør alle')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final result = await SupabaseService.carryoverVacationBetweenYears(
        companyId: widget.companyId,
        fromYear: from,
        toYear: to,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ferdig: ${result['total_days_carried'] ?? 0} dager overført for '
              '${result['employees_updated'] ?? 0} ansatte.',
            ),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: DriftProTheme.error),
        );
      }
    }
  }
}
