import 'package:flutter/material.dart';

import '../../core/theme/driftpro_theme_context.dart';
import '../../models/survey/survey.dart';
import 'survey_analyze_view.dart';
import 'survey_responses_screen.dart';
import '../../core/layout/web_layout.dart';

/// Samlet resultat-hub — statistikk + individuelle svar i én ryddig visning.
class SurveyResultsHub extends StatefulWidget {
  const SurveyResultsHub({super.key, required this.survey});

  final Survey survey;

  @override
  State<SurveyResultsHub> createState() => _SurveyResultsHubState();
}

class _SurveyResultsHubState extends State<SurveyResultsHub> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drift = context.driftColors;

    return Column(
      children: [
        Container(
          color: drift.card,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resultater',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Statistikk og alle innsendte svar — alt på ett sted.',
                style: TextStyle(color: drift.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tab,
                indicatorWeight: 2.5,
                tabs: const [
                  Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Statistikk'),
                  Tab(icon: Icon(Icons.inbox_outlined, size: 18), text: 'Alle svar'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: DriftProTabView(
            controller: _tab,
            children: [
              SurveyAnalyzeView(survey: widget.survey, embedded: true),
              SurveyResponsesScreen(survey: widget.survey, embedded: true),
            ],
          ),
        ),
      ],
    );
  }
}
