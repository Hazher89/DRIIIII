import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/hms/hms_templates.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/risk_assessment.dart';
import '../widgets/hms_template_picker_sheet.dart';
import 'new_risk_assessment_screen.dart';
import 'risk_assessment_detail_screen.dart';
import 'package:intl/intl.dart';

class RiskAssessmentListScreen extends StatefulWidget {
  const RiskAssessmentListScreen({super.key});

  @override
  State<RiskAssessmentListScreen> createState() => _RiskAssessmentListScreenState();
}

class _RiskAssessmentListScreenState extends State<RiskAssessmentListScreen> {
  List<RiskAssessment> _assessments = [];
  Map<String, String> _profileNames = {};
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadData();
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Risikoanalyser'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.add),
            onPressed: () => _createNew(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
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
                )
              : RefreshIndicator(
              onRefresh: _loadData,
              child: _assessments.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _assessments.length,
                      itemBuilder: (context, index) {
                        final ra = _assessments[index];
                        return _buildCard(ra, isDark);
                      },
                    ),
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
    if (score <= 4) riskColor = DriftProTheme.riskLow;
    else if (score <= 9) riskColor = DriftProTheme.riskMedium;
    else if (score <= 14) riskColor = DriftProTheme.riskHigh;
    else if (score <= 19) riskColor = DriftProTheme.riskCritical;
    else riskColor = DriftProTheme.riskExtreme;

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
            Text('Område: ${ra.area ?? "Ikke angitt"}', style: DriftProTheme.bodySm),
            Text('Ansvarlig: ${_name(ra.responsiblePerson)}', style: DriftProTheme.bodySm),
            Text('Opprettet av: ${_name(ra.createdBy)}', style: DriftProTheme.bodySm),
            Text('Dato: ${DateFormat('dd.MM.yyyy').format(ra.createdAt ?? DateTime.now())}', style: DriftProTheme.bodySm),
          ],
        ),
        trailing: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: riskColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Center(
            child: Text(score.toString(), style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 18)),
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
      ).then((v) { if (v == true) _loadData(); }),
      onBlank: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NewRiskAssessmentScreen()),
      ).then((v) { if (v == true) _loadData(); }),
    );
  }
}
