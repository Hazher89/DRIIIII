import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey.dart';
import '../../core/services/survey/survey_service.dart';

class SurveyBuilderCanvas extends StatefulWidget {
  final Survey survey;
  const SurveyBuilderCanvas({super.key, required this.survey});

  @override
  State<SurveyBuilderCanvas> createState() => _SurveyBuilderCanvasState();
}

class _SurveyBuilderCanvasState extends State<SurveyBuilderCanvas> {
  bool _isLoading = true;
  List<SurveyQuestion> _questions = [];
  String? _logoUrl;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() => _isLoading = true);
    try {
      final questions = await SurveyService.fetchQuestions(widget.survey.id);
      setState(() {
        _questions = questions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // Style Sidebar
        _buildStyleSidebar(isDark),
        
        // Canvas
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                decoration: BoxDecoration(
                  color: isDark ? DriftProTheme.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                ),
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildCanvasHeader(),
                            _buildQuestionsList(),
                            _buildCanvasFooter(),
                          ],
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStyleSidebar(bool isDark) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        border: Border(right: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('Stil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.help_outline, size: 18), onPressed: () {}),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () {}),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Text('Innstillinger', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(width: 20),
                Text('Temaer', style: TextStyle(color: DriftProTheme.primaryGreen, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Themes List Placeholder
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildThemeItem('Original', true),
                _buildThemeItem('Enkelt', false),
                _buildThemeItem('Helfarget', false),
                _buildThemeItem('Skyskraper', false),
                _buildThemeItem('Duggdråpe', false),
                _buildThemeItem('Pastell', false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeItem(String name, bool selected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: selected ? DriftProTheme.primaryGreen : Colors.grey[200]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(width: 30, height: 20, color: Colors.grey[300]),
          const SizedBox(width: 10),
          Text(name, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          if (selected) const Icon(Icons.check, size: 14, color: DriftProTheme.primaryGreen),
        ],
      ),
    );
  }

  Widget _buildCanvasHeader() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo Placeholder
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!, style: BorderStyle.none),
            ),
            child: Row(
              children: [
                const Icon(Icons.business, color: DriftProTheme.primaryGreen, size: 40),
                const SizedBox(width: 12),
                Text('DIN LOGO HER', style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(
            widget.survey.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: DriftProTheme.primaryGreen),
          ),
          const SizedBox(height: 8),
          if (widget.survey.description != null)
            Text(widget.survey.description!, style: const TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildQuestionsList() {
    return Column(
      children: [
        for (int i = 0; i < _questions.length; i++) _buildQuestionEditor(i),
        _buildAddContentButton(),
      ],
    );
  }

  Widget _buildQuestionEditor(int index) {
    final q = _questions[index];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.grey[50]?.withOpacity(0.5),
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${index + 1}. ', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Expanded(
                child: Text(q.questionText, style: const TextStyle(fontSize: 16)),
              ),
              IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () {}),
            ],
          ),
          const SizedBox(height: 10),
          if (q.type == SurveyQuestionType.multiple_choice)
            Column(
              children: q.options.map((opt) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.radio_button_off, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(opt),
                  ],
                ),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAddContentButton() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: InkWell(
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: DriftProTheme.primaryGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasFooter() {
    return Container(
      padding: const EdgeInsets.all(40),
      color: Colors.grey[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: const Text('Ferdig', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
