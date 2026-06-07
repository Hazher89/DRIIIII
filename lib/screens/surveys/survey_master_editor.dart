import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/survey/survey_advanced_service.dart';
import '../../core/services/survey/survey_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/driftpro_theme_context.dart';
import '../../core/theme/driftpro_colors.dart';
import '../../models/survey/survey.dart';
import '../../models/survey/survey_advanced.dart';
import 'survey_analyze_view.dart';
import 'survey_builder_canvas.dart';
import 'survey_overview_panel.dart';
import 'survey_publish_view.dart';
import 'survey_responses_screen.dart';

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

  final List<String> _steps = [
    'Oversikt',
    'Bygg',
    'Del',
    'Svar',
    'Statistikk',
    'Tema',
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
        _themeConfig = SurveyThemeConfig(surveyId: _survey.id);
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildStepProgress(DriftProColors drift) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: drift.card,
        border: Border(bottom: BorderSide(color: drift.borderSubtle)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: _steps.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          final isSelected = _currentStep == index;
          return GestureDetector(
            onTap: () => setState(() => _currentStep = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : drift.textMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCurrentView() {
    if (_isLoading && _currentStep == 5) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_currentStep) {
      case 0:
        return SurveyOverviewPanel(
          survey: _survey,
          onGoToStep: (s) => setState(() => _currentStep = s),
        );
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
        return SurveyPublishView(
          survey: _survey,
          onSurveyChanged: _refreshSurvey,
        );
      case 3:
        return SurveyResponsesScreen(survey: _survey);
      case 4:
        return SurveyAnalyzeView(survey: _survey);
      case 5:
        return _buildThemeAndArchiveView();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildThemeAndArchiveView() {
    final cfg = _themeConfig ?? SurveyThemeConfig(surveyId: _survey.id);
    final drift = context.driftColors;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Theme Studio', style: DriftProTheme.headingMd.copyWith(color: drift.textPrimary)),
        const SizedBox(height: 8),
        Text(
          'Tilpass hvordan respondentene opplever undersøkelsen.',
          style: DriftProTheme.bodyMd.copyWith(color: drift.textMuted),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: drift.surfaceDecoration(radius: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Font: ${cfg.fontFamily} • Knapper: ${cfg.buttonStyle}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _colorChip('Primær', cfg.primaryHex),
                  _colorChip('Bakgrunn', cfg.backgroundHex),
                  _colorChip('Kort', cfg.cardHex),
                  _colorChip('Tekst', cfg.textHex),
                ],
              ),
            ],
          ),
        ),
        SwitchListTile(
          value: cfg.darkModeForRespondent,
          onChanged: (v) => _saveTheme(cfg.copyWith(darkModeForRespondent: v)),
          title: const Text('Mørk modus for respondenter'),
        ),
        SwitchListTile(
          value: cfg.showProgressBar,
          onChanged: (v) => _saveTheme(cfg.copyWith(showProgressBar: v)),
          title: const Text('Vis fremdriftslinje'),
        ),
        SwitchListTile(
          value: cfg.showEstimatedTime,
          onChanged: (v) => _saveTheme(cfg.copyWith(showEstimatedTime: v)),
          title: const Text('Vis estimert svartid'),
        ),
        const Divider(height: 40),
        Text('Arkiv', style: DriftProTheme.headingMd.copyWith(color: drift.textPrimary)),
        const SizedBox(height: 8),
        const Text(
          'Arkiver ferdige undersøkelser med snapshot av responsdata for historikk og trendanalyse.',
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _archiveSurvey,
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Arkiver undersøkelse'),
        ),
        if (_snapshots.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Historiske snapshots', style: DriftProTheme.headingSm),
          const SizedBox(height: 8),
          ..._snapshots.map((snap) => ListTile(
                title: Text('${snap.generatedAt.day}.${snap.generatedAt.month}.${snap.generatedAt.year}'),
                subtitle: Text(
                  'Completion ${snap.completionRate.toStringAsFixed(0)}% · ${snap.totalResponses} svar',
                ),
              )),
        ],
      ],
    );
  }

  Widget _colorChip(String label, String hex) {
    return Chip(label: Text('$label: $hex'));
  }

  Future<void> _saveTheme(SurveyThemeConfig config) async {
    await SurveyAdvancedService.upsertTheme(config);
    if (!mounted) return;
    setState(() => _themeConfig = config);
  }

  Future<void> _archiveSurvey() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await SurveyAdvancedService.archiveSurvey(
      survey: _survey,
      archivedBy: user.id,
      note: 'Archived from SurveyMasterEditor',
    );
    await _refreshSurvey();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Undersøkelse arkivert')),
    );
  }
}

extension on SurveyThemeConfig {
  SurveyThemeConfig copyWith({
    String? primaryHex,
    String? backgroundHex,
    String? cardHex,
    String? textHex,
    String? accentHex,
    String? logoUrl,
    String? fontFamily,
    String? buttonStyle,
    bool? darkModeForRespondent,
    bool? compactMode,
    bool? showProgressBar,
    bool? showEstimatedTime,
  }) {
    return SurveyThemeConfig(
      surveyId: surveyId,
      primaryHex: primaryHex ?? this.primaryHex,
      backgroundHex: backgroundHex ?? this.backgroundHex,
      cardHex: cardHex ?? this.cardHex,
      textHex: textHex ?? this.textHex,
      accentHex: accentHex ?? this.accentHex,
      logoUrl: logoUrl ?? this.logoUrl,
      fontFamily: fontFamily ?? this.fontFamily,
      buttonStyle: buttonStyle ?? this.buttonStyle,
      darkModeForRespondent: darkModeForRespondent ?? this.darkModeForRespondent,
      compactMode: compactMode ?? this.compactMode,
      showProgressBar: showProgressBar ?? this.showProgressBar,
      showEstimatedTime: showEstimatedTime ?? this.showEstimatedTime,
    );
  }
}
