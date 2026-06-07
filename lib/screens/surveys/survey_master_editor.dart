import 'package:flutter/material.dart';

import '../../core/services/survey/survey_advanced_service.dart';
import '../../core/services/survey/survey_service.dart';
import '../../core/services/survey/survey_theme_presets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../core/theme/driftpro_colors.dart';
import '../../models/survey/survey.dart';
import '../../models/survey/survey_advanced.dart';
import 'survey_builder_canvas.dart';
import 'survey_overview_panel.dart';
import 'survey_publish_view.dart';
import 'survey_results_hub.dart';
import 'widgets/survey_theme_studio.dart';

class SurveyMasterEditor extends StatefulWidget {
  final Survey survey;
  const SurveyMasterEditor({super.key, required this.survey});

  @override
  State<SurveyMasterEditor> createState() => _SurveyMasterEditorState();
}

class _SurveyMasterEditorState extends State<SurveyMasterEditor> {
  int _currentStep = 0;
  bool _isLoading = false;
  late Survey _survey;
  final GlobalKey<SurveyBuilderCanvasState> _canvasKey = GlobalKey<SurveyBuilderCanvasState>();
  SurveyThemeConfig? _themeConfig;
  List<SurveyAnalyticsSnapshot> _snapshots = const [];

  /// Rekkefølge: Oversikt → Bygg → Tema → Del → Resultater (sist)
  static const _steps = [
    ('Oversikt', Icons.dashboard_outlined),
    ('Bygg', Icons.edit_note_outlined),
    ('Tema', Icons.palette_outlined),
    ('Del', Icons.share_outlined),
    ('Resultater', Icons.insights_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _survey = widget.survey;
    _loadAdvancedData();
  }

  Future<void> _loadAdvancedData() async {
    setState(() => _isLoading = true);
    try {
      final theme = await SurveyAdvancedService.fetchTheme(_survey.id);
      final snapshots = await SurveyAdvancedService.fetchSnapshots(_survey.id);
      if (!mounted) return;
      setState(() {
        _themeConfig = theme;
        _snapshots = snapshots;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _themeConfig = SurveyThemePresets.byNameOrDefault(_survey.theme).toConfig(_survey.id);
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshSurvey() async {
    final fresh = await SurveyService.fetchSurveyById(_survey.id);
    if (mounted) setState(() => _survey = fresh);
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;

    return Scaffold(
      backgroundColor: drift.scaffold,
      appBar: _buildSubHeader(drift),
      body: Column(
        children: [
          _buildStepProgress(drift),
          Expanded(child: _buildCurrentView()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSubHeader(DriftProColors drift) {
    return AppBar(
      elevation: 0,
      backgroundColor: drift.card,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.chevron_left, color: drift.iconPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Icon(Icons.poll_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _survey.title,
              style: DriftProTheme.headingSm.copyWith(color: drift.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (_survey.isActive ? Colors.green : Colors.orange).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _survey.isActive ? 'Åpen' : 'Lukket',
              style: TextStyle(
                color: _survey.isActive ? Colors.green : Colors.orange,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (_currentStep == 1)
          TextButton.icon(
            onPressed: () => _canvasKey.currentState?.saveChanges(),
            icon: Icon(Icons.save_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
            label: Text(
              'Lagre',
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildStepProgress(DriftProColors drift) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: drift.card,
        border: Border(bottom: BorderSide(color: drift.borderSubtle)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: _steps.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value.$1;
          final icon = entry.value.$2;
          final isSelected = _currentStep == index;
          final isLast = index == _steps.length - 1;
          return GestureDetector(
            onTap: () => setState(() => _currentStep = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Theme.of(context).colorScheme.primary : drift.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(icon, size: 16, color: isSelected ? Theme.of(context).colorScheme.primary : drift.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Theme.of(context).colorScheme.primary : drift.textMuted,
                    ),
                  ),
                  if (isLast) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.flag_outlined, size: 12, color: isSelected ? Theme.of(context).colorScheme.primary : drift.textMuted),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCurrentView() {
    if (_isLoading && _currentStep == 2) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_currentStep) {
      case 0:
        return SurveyOverviewPanel(survey: _survey, onGoToStep: (s) => setState(() => _currentStep = s));
      case 1:
        return SurveyBuilderCanvas(
          key: _canvasKey,
          survey: _survey,
          onAfterSuccessfulSave: () {
            if (!mounted) return;
            _refreshSurvey();
            setState(() => _currentStep = 2);
          },
        );
      case 2:
        return SurveyThemeStudio(
          survey: _survey,
          themeConfig: _themeConfig ?? SurveyThemePresets.byNameOrDefault(_survey.theme).toConfig(_survey.id),
          snapshots: _snapshots,
          onSurveyRefresh: _refreshSurvey,
          onThemeSaved: _saveTheme,
          onContinueToDel: () => setState(() => _currentStep = 3),
        );
      case 3:
        return SurveyPublishView(survey: _survey, onSurveyChanged: _refreshSurvey);
      case 4:
        return SurveyResultsHub(survey: _survey);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _saveTheme(SurveyThemeConfig config) async {
    await SurveyAdvancedService.upsertTheme(config);
    if (!mounted) return;
    setState(() => _themeConfig = config);
  }
}
