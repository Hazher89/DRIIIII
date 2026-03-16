import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/survey/survey_service.dart';
import '../../models/survey/survey.dart';
import 'survey_editor_screen.dart';
import 'survey_master_editor.dart';
import 'survey_results_screen.dart';

class SurveyListScreen extends StatefulWidget {
  const SurveyListScreen({super.key});

  @override
  State<SurveyListScreen> createState() => _SurveyListScreenState();
}

class _SurveyListScreenState extends State<SurveyListScreen> {
  bool _isLoading = true;
  List<Survey> _surveys = [];
  String? _companyId;

  @override
  void initState() {
    super.initState();
    _loadSurveys();
  }

  Future<void> _loadSurveys() async {
    setState(() => _isLoading = true);
    try {
      final profile = await SupabaseService.fetchCurrentUserProfile();
      if (profile != null) {
        _companyId = profile.companyId;
        final surveys = await SurveyService.fetchSurveys(companyId: profile.companyId!);
        setState(() {
          _surveys = surveys;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil ved henting av undersøkelser: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createSurvey() async {
    final title = await _showInputDialog('Ny undersøkelse', 'Tittel');
    if (title != null && title.isNotEmpty && _companyId != null) {
      final user = SupabaseService.currentUser;
      if (user == null) return;

      try {
        final survey = await SurveyService.createSurvey(
          companyId: _companyId!,
          title: title,
          createdBy: user.id,
        );
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SurveyEditorScreen(survey: survey),
            ),
          ).then((_) => _loadSurveys());
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kunne ikke opprette undersøkelse: $e')),
          );
        }
      }
    }
  }

  Future<String?> _showInputDialog(String title, String label) async {
    String value = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(context, value), child: const Text('Lagre')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Undersøkelser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSurveys,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _surveys.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _surveys.length,
                  itemBuilder: (context, index) {
                    final survey = _surveys[index];
                    return _buildSurveyCard(survey, isDark);
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSurvey,
        label: const Text('Ny undersøkelse'),
        icon: const Icon(Icons.add),
        backgroundColor: DriftProTheme.primaryGreen,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Ingen undersøkelser ennå',
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('Opprett din første undersøkelse for å komme i gang'),
        ],
      ),
    );
  }

  Widget _buildSurveyCard(Survey survey, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SurveyMasterEditor(survey: survey),
            ),
          ).then((_) => _loadSurveys());
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: survey.isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      survey.isActive ? 'Aktiv' : 'Inaktiv',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: survey.isActive ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.bar_chart, color: DriftProTheme.primaryGreen),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SurveyResultsScreen(survey: survey),
                        ),
                      );
                    },
                    tooltip: 'Se resultater',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Slett undersøkelse?'),
                          content: const Text('Dette kan ikke angres.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Slett', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await SurveyService.deleteSurvey(survey.id);
                        _loadSurveys();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                survey.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (survey.description != null && survey.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  survey.description!,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    'Opprettet: ${survey.createdAt.day}.${survey.createdAt.month}.${survey.createdAt.year}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
