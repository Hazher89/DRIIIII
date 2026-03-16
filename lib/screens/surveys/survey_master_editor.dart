import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/survey/survey_service.dart';
import '../../models/survey/survey.dart';
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

  final List<String> _steps = [
    'Sammendrag',
    'Lag undersøkelse',
    'Publiser',
    'Koble til apper',
    'Analyser resultater'
  ];

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
        IconButton(icon: const Icon(Icons.comment_outlined, size: 20), onPressed: () {}),
        IconButton(icon: const Icon(Icons.person_add_outlined, size: 20), onPressed: () {}),
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
    switch (_currentStep) {
      case 1:
        return SurveyBuilderCanvas(survey: widget.survey);
      case 2:
        return SurveyPublishView(survey: widget.survey);
      case 4:
        return SurveyAnalyzeView(survey: widget.survey);
      default:
        return Center(child: Text('Modul for ${_steps[_currentStep]} kommer snart'));
    }
  }
}
