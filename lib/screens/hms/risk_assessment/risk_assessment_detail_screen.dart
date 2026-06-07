import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/hms/hms_ecosystem_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/risk_assessment.dart';
import '../../../models/user_profile.dart';
import '../widgets/interactive_risk_matrix.dart';

class RiskAssessmentDetailScreen extends StatefulWidget {
  final RiskAssessment assessment;

  const RiskAssessmentDetailScreen({super.key, required this.assessment});

  @override
  State<RiskAssessmentDetailScreen> createState() =>
      _RiskAssessmentDetailScreenState();
}

class _RiskAssessmentDetailScreenState
    extends State<RiskAssessmentDetailScreen> {
  late RiskAssessment _ra;
  UserProfile? _profile;
  bool _loading = true;
  bool _saving = false;

  int _initialP = 3;
  int _initialC = 3;
  int _residualP = 3;
  int _residualC = 3;

  final _measuresController = TextEditingController();
  final _proposedController = TextEditingController();

  bool get _canEdit =>
      _profile?.isAdmin == true ||
      _profile?.role == UserRole.leder ||
      _profile?.id == _ra.createdBy;

  @override
  void initState() {
    super.initState();
    _ra = widget.assessment;
    _syncFromRa();
    _load();
  }

  void _syncFromRa() {
    _initialP = _ra.initialProbability;
    _initialC = _ra.initialConsequence;
    _residualP = _ra.residualProbability;
    _residualC = _ra.residualConsequence;
    _measuresController.text = _ra.existingMeasures ?? '';
    _proposedController.text = _ra.proposedMeasures ?? '';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _profile = await SupabaseService.fetchCurrentUserProfile();
      final fresh = await HmsEcosystemService.fetchRiskAssessmentById(_ra.id);
      if (fresh != null) {
        _ra = fresh;
        _syncFromRa();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    setState(() => _saving = true);
    try {
      await HmsEcosystemService.updateRiskAssessment(_ra.id, {
        'initial_probability': _initialP,
        'initial_consequence': _initialC,
        'residual_probability': _residualP,
        'residual_consequence': _residualC,
        'probability': _initialP,
        'consequence': _initialC,
        'existing_measures': _measuresController.text.trim(),
        'proposed_measures': _proposedController.text.trim(),
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ROS-analyse lagret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kunne ikke lagre: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _measuresController.dispose();
    _proposedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      backgroundColor:
          isDark ? DriftProTheme.surfaceDark : DriftProTheme.surfaceLight,
      appBar: AppBar(
        title: Text(_ra.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_canEdit)
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              onPressed: _saving ? null : _save,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_ra.avvikBoosted) _buildAvvikBoostBanner(isDark),
                  _buildHeaderCard(isDark, fmt),
                  const SizedBox(height: 20),
                  DualRiskMatrixPanel(
                    initialP: _initialP,
                    initialC: _initialC,
                    residualP: _residualP,
                    residualC: _residualC,
                    readOnly: !_canEdit,
                    onInitialP: _canEdit ? (v) => setState(() => _initialP = v) : null,
                    onInitialC: _canEdit ? (v) => setState(() => _initialC = v) : null,
                    onResidualP:
                        _canEdit ? (v) => setState(() => _residualP = v) : null,
                    onResidualC:
                        _canEdit ? (v) => setState(() => _residualC = v) : null,
                  ),
                  const SizedBox(height: 24),
                  _buildComparisonSummary(isDark),
                  const SizedBox(height: 24),
                  Text('Eksisterende tiltak', style: DriftProTheme.labelLg),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _measuresController,
                    readOnly: !_canEdit,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Tiltak som allerede finnes...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Planlagte tiltak', style: DriftProTheme.labelLg),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _proposedController,
                    readOnly: !_canEdit,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Nye tiltak som reduserer rest-risiko...',
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAvvikBoostBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DriftProTheme.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DriftProTheme.warning),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: DriftProTheme.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_ra.avvikSignalCount} like avvik (${_ra.linkedTicketCategory ?? 'ukjent'}) '
              'øker reell sannsynlighet. Revider analysen.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark, DateFormat fmt) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_ra.area != null)
              Text(_ra.area!, style: DriftProTheme.labelSm),
            if (_ra.description != null && _ra.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_ra.description!),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('Status: ${_ra.status}', DriftProTheme.info),
                if (_ra.scenarioCategory != null)
                  _chip(_ra.scenarioCategory!, Colors.blueGrey),
                if (_ra.creatorName != null)
                  _chip('Opprettet av ${_ra.creatorName}', Colors.grey),
                if (_ra.createdAt != null)
                  _chip(fmt.format(_ra.createdAt!), Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildComparisonSummary(bool isDark) {
    final initialScore = _initialP * _initialC;
    final residualScore = _residualP * _residualC;
    final reduction = initialScore - residualScore;

    return Card(
      elevation: 0,
      color: isDark ? Colors.white10 : Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text('Initial', style: DriftProTheme.labelSm),
                  Text(
                    '$initialScore',
                    style: DriftProTheme.headingMd.copyWith(
                      color: DriftProTheme.riskHigh,
                    ),
                  ),
                  Text(_ra.riskLevelForScore(initialScore),
                      style: DriftProTheme.bodySm),
                ],
              ),
            ),
            Icon(
              reduction > 0 ? Icons.trending_down : Icons.horizontal_rule,
              color: reduction > 0 ? DriftProTheme.success : Colors.grey,
            ),
            Expanded(
              child: Column(
                children: [
                  Text('Rest', style: DriftProTheme.labelSm),
                  Text(
                    '$residualScore',
                    style: DriftProTheme.headingMd.copyWith(
                      color: DriftProTheme.primaryGreen,
                    ),
                  ),
                  Text(_ra.riskLevelForScore(residualScore),
                      style: DriftProTheme.bodySm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
