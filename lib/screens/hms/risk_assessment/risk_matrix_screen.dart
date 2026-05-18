import 'package:flutter/material.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/services/hms/hms_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/risk_assessment.dart';
import 'new_risk_assessment_screen.dart';
import 'risk_assessment_list_screen.dart';

/// Interaktiv 5×5 risikomatrise fra Supabase-data.
class RiskMatrixScreen extends StatefulWidget {
  const RiskMatrixScreen({super.key});

  @override
  State<RiskMatrixScreen> createState() => _RiskMatrixScreenState();
}

class _RiskMatrixScreenState extends State<RiskMatrixScreen> {
  List<RiskAssessment> _risks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final companyId = await SupabaseService.getCurrentCompanyId();
      if (companyId != null) {
        _risks = await SupabaseService.fetchRiskAssessments(companyId: companyId);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _cellColor(int score, bool isDark) {
    if (score <= 4) return isDark ? Colors.green.shade900 : Colors.green.shade100;
    if (score <= 9) return isDark ? Colors.yellow.shade900 : Colors.yellow.shade100;
    if (score <= 14) return isDark ? Colors.orange.shade900 : Colors.orange.shade200;
    return isDark ? Colors.red.shade900 : Colors.red.shade200;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heat = HmsService.riskHeatmap(_risks);

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Risikomatrise 5×5'),
        actions: [
          IconButton(icon: const Icon(Icons.list), onPressed: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RiskAssessmentListScreen()));
          }),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Klikk en celle for å se risikoer. Farger følger sannsynlighet × konsekvens.',
                    style: DriftProTheme.bodySm,
                  ),
                  const SizedBox(height: 16),
                  _buildMatrix(heat, isDark),
                  const SizedBox(height: 24),
                  Text('Høyrisiko (${_risks.where((r) => r.isHighRisk).length})',
                      style: DriftProTheme.headingSm),
                  const SizedBox(height: 8),
                  ..._risks.where((r) => r.isHighRisk).map(
                        (r) => ListTile(
                          leading: Icon(AppIcons.riskAssessment,
                              color: DriftProTheme.riskHigh),
                          title: Text(r.title),
                          subtitle: Text(
                              'S:${r.probability} K:${r.consequence} = ${r.calculatedRiskScore}'),
                        ),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _buildMatrix(Map<int, Map<int, int>> heat, bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 36),
            ...List.generate(
              5,
              (c) => Expanded(
                child: Center(
                  child: Text('K${c + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ),
            ),
          ],
        ),
        ...List.generate(5, (row) {
          final p = 5 - row;
          return Row(
            children: [
              SizedBox(
                width: 36,
                child: Text('S$p', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...List.generate(5, (col) {
                final c = col + 1;
                final count = heat[p]?[c] ?? 0;
                final score = p * c;
                return Expanded(
                  child: GestureDetector(
                    onTap: count == 0
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NewRiskAssessmentScreen(
                                  initialProbability: p,
                                  initialConsequence: c,
                                ),
                              ),
                            )
                        : () => _showCellRisks(p, c),
                    child: Container(
                      height: 52,
                      margin: const EdgeInsets.all(2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _cellColor(score, isDark),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: count > 0
                              ? DriftProTheme.primaryGreen
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        count > 0 ? '$count' : '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  void _showCellRisks(int p, int c) {
    final list = _risks
        .where((r) => r.probability == p && r.consequence == c)
        .toList();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Sannsynlighet $p × Konsekvens $c',
                  style: DriftProTheme.headingSm),
            ),
            ...list.map((r) => ListTile(
                  title: Text(r.title),
                  subtitle: Text(r.area ?? ''),
                )),
          ],
        ),
      ),
    );
  }
}
