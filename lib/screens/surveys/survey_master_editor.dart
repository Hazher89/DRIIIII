import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/survey/survey_advanced_service.dart';
import '../../models/survey/survey.dart';
import '../../models/survey/survey_advanced.dart';
import 'survey_builder_canvas.dart';
import 'survey_publish_view.dart';
import 'survey_analyze_view.dart';

class SurveyMasterEditor extends StatefulWidget {
  final Survey survey;
  const SurveyMasterEditor({super.key, required this.survey});

  @override
  State<SurveyMasterEditor> createState() => _SurveyMasterEditorState();
}

class _SurveyMasterEditorState extends State<SurveyMasterEditor> {
  int _currentStep = 1; // 0: Sammendrag, 1: Lag, 2: Publiser, 3: Koble, 4: Analyser
  bool _isLoading = false;
  final GlobalKey<SurveyBuilderCanvasState> _canvasKey = GlobalKey<SurveyBuilderCanvasState>();
  SurveyThemeConfig? _themeConfig;
  List<SurveyAnalyticsSnapshot> _snapshots = const [];

  final List<String> _steps = [
    'Sammendrag',
    'Lag undersøkelse',
    'Publiser',
    'Koble til apper',
    'Analyser resultater'
  ];

  @override
  void initState() {
    super.initState();
    _loadAdvancedData();
  }

  Future<void> _loadAdvancedData() async {
    setState(() => _isLoading = true);
    try {
      final theme = await SurveyAdvancedService.fetchTheme(widget.survey.id);
      final snapshots = await SurveyAdvancedService.fetchSnapshots(widget.survey.id);
      if (!mounted) return;
      setState(() {
        _themeConfig = theme;
        _snapshots = snapshots;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _themeConfig = SurveyThemeConfig(surveyId: widget.survey.id);
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? DriftProTheme.surfaceDark : const Color(0xFFF5F7F8);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildSubHeader(isDark),
      body: Column(
        children: [
          _buildStepProgress(isDark),
          Expanded(
            child: _buildCurrentView(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSubHeader(bool isDark) {
    return AppBar(
      elevation: 0,
      backgroundColor: isDark ? DriftProTheme.cardDark : Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.chevron_left),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          const Icon(Icons.assignment_turned_in_outlined, size: 20, color: DriftProTheme.primaryGreen),
          const SizedBox(width: 8),
          Text(
            widget.survey.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Åpen', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      actions: [
        if (_currentStep == 1)
          TextButton.icon(
            onPressed: () {
              _canvasKey.currentState?.saveChanges();
            },
            icon: const Icon(Icons.save_outlined, size: 18, color: DriftProTheme.primaryGreen),
            label: const Text('Lagre', style: TextStyle(color: DriftProTheme.primaryGreen, fontWeight: FontWeight.bold)),
          ),
        const SizedBox(width: 8),
        IconButton(icon: const Icon(Icons.notifications_none, size: 20), onPressed: () {}),
        IconButton(icon: const Icon(Icons.help_outline, size: 20), onPressed: () {}),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildStepProgress(bool isDark) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _steps.asMap().entries.map((entry) {
          final index = entry.key;
          final label = entry.value;
          final isSelected = _currentStep == index;
          
          return GestureDetector(
            onTap: () => setState(() => _currentStep = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? DriftProTheme.primaryGreen : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? DriftProTheme.primaryGreen : (isDark ? Colors.grey[400] : Colors.grey[600]),
                    ),
                  ),
                  if (index < _steps.length - 1)
                    Icon(Icons.chevron_right, size: 16, color: isDark ? Colors.white24 : Colors.grey[300]),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCurrentView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_currentStep) {
      case 0:
        return _buildSummaryView();
      case 1:
        return SurveyBuilderCanvas(
          key: _canvasKey,
          survey: widget.survey,
          onAfterSuccessfulSave: () {
            if (!mounted) return;
            setState(() => _currentStep = 2);
          },
        );
      case 2:
        return SurveyPublishView(survey: widget.survey);
      case 3:
        return _buildIntegrationsAndArchiveView();
      case 4:
        return _buildAnalyticsView();
      default:
        return Center(child: Text('Modul for ${_steps[_currentStep]} kommer snart'));
    }
  }

  Widget _buildSummaryView() {
    final cfg = _themeConfig ?? SurveyThemeConfig(surveyId: widget.survey.id);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Theme Studio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Font: ${cfg.fontFamily} • Knappestil: ${cfg.buttonStyle}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _colorChip('Primær', cfg.primaryHex),
                    _colorChip('Bakgrunn', cfg.backgroundHex),
                    _colorChip('Kort', cfg.cardHex),
                    _colorChip('Tekst', cfg.textHex),
                    _colorChip('Accent', cfg.accentHex),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: cfg.darkModeForRespondent,
          onChanged: (value) => _saveTheme(cfg.copyWith(darkModeForRespondent: value)),
          title: const Text('Aktiver dark mode for respondenter'),
        ),
        SwitchListTile(
          value: cfg.showProgressBar,
          onChanged: (value) => _saveTheme(cfg.copyWith(showProgressBar: value)),
          title: const Text('Vis fremdriftslinje'),
        ),
        SwitchListTile(
          value: cfg.showEstimatedTime,
          onChanged: (value) => _saveTheme(cfg.copyWith(showEstimatedTime: value)),
          title: const Text('Vis estimert svartid'),
        ),
      ],
    );
  }

  Widget _buildIntegrationsAndArchiveView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Smart Archive', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Arkiver ferdige undersøkelser med snapshot av responsdata for historikk, revisjon og trendanalyse.',
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _archiveSurvey,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Arkiver undersøkelse'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsView() {
    return Column(
      children: [
        Expanded(child: SurveyAnalyzeView(survey: widget.survey)),
        if (_snapshots.isNotEmpty)
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _snapshots.length,
              itemBuilder: (context, index) {
                final snap = _snapshots[index];
                return Container(
                  width: 260,
                  margin: const EdgeInsets.only(left: 12, right: 4, bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${snap.generatedAt.day}.${snap.generatedAt.month}.${snap.generatedAt.year}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text('Completion: ${snap.completionRate.toStringAsFixed(1)}%'),
                          Text('Drop-off: ${snap.dropOffCount}'),
                          Text('Sentiment: ${snap.sentimentScore.toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
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
      survey: widget.survey,
      archivedBy: user.id,
      note: 'Archived from SurveyMasterEditor',
    );
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
