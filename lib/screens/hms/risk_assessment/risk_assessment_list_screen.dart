import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/hms/hms_templates.dart';
import '../../../core/routing/app_paths.dart';
import '../../../core/routing/route_url_sync.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/risk_assessment.dart';
import '../../../models/risk_assessment_status.dart';
import '../widgets/hms_template_picker_sheet.dart';
import 'new_risk_assessment_screen.dart';
import 'risk_assessment_detail_screen.dart';
import 'stakeholder_risk/stakeholder_risk_hub_tab.dart';
import 'package:intl/intl.dart';

class RiskAssessmentListScreen extends StatefulWidget {
  const RiskAssessmentListScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  State<RiskAssessmentListScreen> createState() => _RiskAssessmentListScreenState();
}

class _RiskAssessmentListScreenState extends State<RiskAssessmentListScreen>
    with SingleTickerProviderStateMixin {
  List<RiskAssessment> _assessments = [];
  Map<String, String> _profileNames = {};
  bool _isLoading = true;
  String? _loadError;
  late TabController _tabController;
  String _filter = 'alle';

  static const _filters = [
    ('alle', 'Alle'),
    ('apne', 'Ikke behandlet'),
    ('under', 'Under behandling'),
    ('behandlet', 'Behandlet'),
    ('hoy', 'Høy risiko'),
  ];

  @override
  void initState() {
    super.initState();
    final idx = RouteUrlSync.indexForSlug(widget.initialTab, AppPaths.riskTabs);
    _tabController = TabController(length: 2, vsync: this, initialIndex: idx);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging || !mounted) return;
    RouteUrlSync.syncTab(
      context,
      basePath: AppPaths.hmsRisiko,
      index: _tabController.index,
      slugs: AppPaths.riskTabs,
    );
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId != null) {
        final data = await SupabaseService.fetchRiskAssessments(companyId: companyId);
        final profiles = await SupabaseService.fetchProfiles(companyId: companyId);
        final names = {for (final p in profiles) p.id: p.fullName};
        setState(() {
          _assessments = data;
          _profileNames = names;
        });
      } else {
        setState(() => _assessments = []);
      }
    } catch (e) {
      setState(() => _loadError = 'Kunne ikke hente risikoanalyser: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _name(String? id) =>
      id == null ? 'Ikke angitt' : (_profileNames[id] ?? 'Ukjent');

  List<RiskAssessment> get _filteredAssessments {
    return _assessments.where((ra) {
      switch (_filter) {
        case 'apne':
          return ra.status == RiskAssessmentStatuses.aktiv ||
              ra.status == RiskAssessmentStatuses.utkast;
        case 'under':
          return ra.status == RiskAssessmentStatuses.underBehandling;
        case 'behandlet':
          return RiskAssessmentStatuses.isTreated(ra.status);
        case 'hoy':
          return ra.isHighRisk;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Risikoanalyser'),
        actions: [
          if (_tabController.index == 0)
            IconButton(
              icon: const Icon(AppIcons.add),
              onPressed: () => _createNew(context),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Risikoanalyser', icon: Icon(Icons.analytics_outlined, size: 18)),
            Tab(text: 'Interessepart og risikovurdering', icon: Icon(Icons.groups_outlined, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildClassicTab(isDark),
          const StakeholderRiskHubTab(),
        ],
      ),
    );
  }

  Widget _buildClassicTab(bool isDark) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadData, child: const Text('Prøv igjen')),
            ],
          ),
        ),
      );
    }
    if (_assessments.isEmpty) return _buildEmptyState();
    final filtered = _filteredAssessments;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _filters[i];
                final selected = _filter == f.$1;
                return FilterChip(
                  label: Text(f.$2),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = f.$1),
                );
              },
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                      const Center(
                        child: Text('Ingen treff for filter', style: TextStyle(color: Colors.grey)),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _buildCard(filtered[index], isDark),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.riskAssessment, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('Ingen risikoanalyser registrert', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => _createNew(context), child: const Text('OPPRETT NY')),
        ],
      ),
    );
  }

  Widget _buildCard(RiskAssessment ra, bool isDark) {
    Color riskColor;
    final score = ra.calculatedRiskScore;
    if (score <= 4) {
      riskColor = DriftProTheme.riskLow;
    } else if (score <= 9) {
      riskColor = DriftProTheme.riskMedium;
    } else if (score <= 14) {
      riskColor = DriftProTheme.riskHigh;
    } else if (score <= 19) {
      riskColor = DriftProTheme.riskCritical;
    } else {
      riskColor = DriftProTheme.riskExtreme;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: DriftProTheme.cardShadow,
        border: Border.all(color: isDark ? DriftProTheme.dividerDark : Colors.grey.shade100),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(ra.title, style: DriftProTheme.labelLg),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text(
                    RiskAssessmentStatuses.label(ra.status),
                    style: const TextStyle(fontSize: 10),
                  ),
                  backgroundColor: RiskAssessmentStatuses.chipColor(ra.status).withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                if (ra.isoStandard != null)
                  Chip(label: Text(ra.isoStandard!, style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact),
                if (ra.attachmentCount > 0)
                  Chip(
                    label: Text('${ra.attachmentCount} vedlegg', style: const TextStyle(fontSize: 10)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            Text('Område: ${ra.area ?? "Ikke angitt"}', style: DriftProTheme.bodySm),
            Text('Ansvarlig: ${_name(ra.responsiblePerson)}', style: DriftProTheme.bodySm),
            Text('Dato: ${DateFormat('dd.MM.yyyy').format(ra.createdAt ?? DateTime.now())}', style: DriftProTheme.bodySm),
          ],
        ),
        trailing: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: riskColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              score.toString(),
              style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RiskAssessmentDetailScreen(assessment: ra),
            ),
          ).then((_) => _loadData());
        },
      ),
    );
  }

  void _createNew(BuildContext context) {
    HmsTemplatePickerSheet.show(
      context,
      kind: HmsModuleKind.risk,
      onSelected: (t) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NewRiskAssessmentScreen(template: t as HmsRiskTemplate),
        ),
      ).then((v) {
        if (v == true) _loadData();
      }),
      onBlank: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NewRiskAssessmentScreen()),
      ).then((v) {
        if (v == true) _loadData();
      }),
    );
  }
}
