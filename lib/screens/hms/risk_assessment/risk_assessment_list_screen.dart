import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/risk_assessment.dart';
import 'new_risk_assessment_screen.dart';
import 'package:intl/intl.dart';

class RiskAssessmentListScreen extends StatefulWidget {
  const RiskAssessmentListScreen({super.key});

  @override
  State<RiskAssessmentListScreen> createState() => _RiskAssessmentListScreenState();
}

class _RiskAssessmentListScreenState extends State<RiskAssessmentListScreen> {
  List<RiskAssessment> _assessments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId != null) {
        final data = await SupabaseService.fetchRiskAssessments(companyId: companyId);
        setState(() => _assessments = data);
      } else {
        setState(() => _assessments = []);
      }
    } catch (_) {
      // Handle error
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
            Text('Opprettet av: ${ra.creatorName ?? "Ukjent"}', style: DriftProTheme.bodySm),
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
          // View details
        },
      ),
    );
  }

  void _createNew(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewRiskAssessmentScreen()),
    ).then((v) { if (v == true) _loadData(); });
  }
}
