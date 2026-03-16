import 'package:flutter/material.dart';
import '../../../core/constants/app_icons.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/risk_assessment.dart';
import 'package:uuid/uuid.dart';

class NewRiskAssessmentScreen extends StatefulWidget {
  const NewRiskAssessmentScreen({super.key});

  @override
  State<NewRiskAssessmentScreen> createState() => _NewRiskAssessmentScreenState();
}

class _NewRiskAssessmentScreenState extends State<NewRiskAssessmentScreen> {
  final _titleController = TextEditingController();
  final _areaController = TextEditingController();
  final _descController = TextEditingController();
  final _measuresController = TextEditingController();
  
  int _probability = 1;
  int _consequence = 1;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final score = _probability * _consequence;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(title: const Text('Ny Risikoanalyse')),
      bottomNavigationBar: _buildBottomBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInput('Tittel', _titleController, hint: 'Hva skal vurderes?', isDark: isDark),
            const SizedBox(height: 16),
            _buildInput('Område/Sted', _areaController, hint: 'F.eks. Byggeplass A eller Verksted', isDark: isDark),
            const SizedBox(height: 24),
            
            Text('Risikovurdering (5×5 Matrise)'.toUpperCase(), style: DriftProTheme.labelSm),
            const SizedBox(height: 16),
            _buildMatrixSelector(isDark),
            const SizedBox(height: 24),
            
            _buildScoreBadge(score, isDark),
            const SizedBox(height: 24),

            _buildInput('Faremoment / Beskrivelse', _descController, maxLines: 3, isDark: isDark),
            const SizedBox(height: 16),
            _buildInput('Tiltak', _measuresController, maxLines: 3, hint: 'Hva gjøres for å redusere risikoen?', isDark: isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, {String? hint, int maxLines = 1, required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DriftProTheme.labelMd),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            fillColor: isDark ? DriftProTheme.cardDark : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildMatrixSelector(bool isDark) {
    return Column(
      children: List.generate(5, (row) {
        final p = 5 - row;
        return Row(
          children: [
            SizedBox(width: 30, child: Text('$p', style: const TextStyle(fontWeight: FontWeight.bold))),
            ...List.generate(5, (col) {
              final c = col + 1;
              final isSelected = _probability == p && _consequence == c;
              final score = p * c;
              final color = _getRiskColor(score);
              
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() { _probability = p; _consequence = c; }),
                  child: Container(
                    height: 45,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? color : color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSelected ? Colors.white : color.withOpacity(0.3), width: isSelected ? 2 : 1),
                    ),
                    child: Center(
                      child: Text('$score', style: TextStyle(
                        color: isSelected ? Colors.white : color,
                        fontWeight: FontWeight.bold,
                      )),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      }),
    );
  }

  Widget _buildScoreBadge(int score, bool isDark) {
    final color = _getRiskColor(score);
    String label = 'Lav risiko';
    if (score > 14) label = 'KRITISK RISIKO';
    else if (score > 9) label = 'Høy risiko';
    else if (score > 4) label = 'Middels risiko';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(child: Text('$score', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              if (score >= 15) const Text('Verneombud vil bli varslet automatisk', style: TextStyle(fontSize: 10, color: DriftProTheme.error)),
            ],
          ),
        ],
      ),
    );
  }

  Color _getRiskColor(int score) {
    if (score <= 4) return DriftProTheme.riskLow;
    if (score <= 9) return DriftProTheme.riskMedium;
    if (score <= 14) return DriftProTheme.riskHigh;
    if (score <= 19) return DriftProTheme.riskCritical;
    return DriftProTheme.riskExtreme;
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.transparent,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _save,
        style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
        child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('LAGRE RISIKOANALYSE'),
      ),
    );
  }

  Future<void> _save() async {
    if (_titleController.text.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (profile == null) return;
      
      final ra = RiskAssessment(
        id: const Uuid().v4(),
        companyId: profile.companyId!,
        departmentId: profile.departmentId,
        createdBy: profile.id,
        title: _titleController.text,
        area: _areaController.text,
        description: _descController.text,
        proposedMeasures: _measuresController.text,
        probability: _probability,
        consequence: _consequence,
      );
      
      await SupabaseService.createRiskAssessment(ra);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feil: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
