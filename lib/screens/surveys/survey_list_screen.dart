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
    final title = await _showInputDialog('Lag ny undersøkelse', 'Tittel på undersøkelsen');
    if (title != null && title.isNotEmpty && _companyId != null) {
      final user = SupabaseService.currentUser;
      if (user == null) return;

      setState(() => _isLoading = true);
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
              builder: (context) => SurveyMasterEditor(survey: survey),
            ),
          ).then((_) => _loadSurveys());
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kunne ikke opprette undersøkelse: $e')),
          );
        }
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _showInputDialog(String title, String label) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          contentPadding: EdgeInsets.zero,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: DriftProTheme.primaryGreen),
            child: const Text('Opprett', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? DriftProTheme.surfaceDark : const Color(0xFFF5F7F8),
      appBar: AppBar(
        title: const Text('Undersøkelser'),
        elevation: 0,
        backgroundColor: isDark ? DriftProTheme.cardDark : Colors.white,
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
        label: const Text('Lag ny undersøkelse', style: TextStyle(fontWeight: FontWeight.bold)),
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
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: DriftProTheme.primaryGreen.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.assignment_outlined, size: 64, color: DriftProTheme.primaryGreen),
          ),
          const SizedBox(height: 24),
          const Text(
            'Ingen undersøkelser ennå',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Opprett din første undersøkelse for å samle inn\nverdifull innsikt fra dine ansatte.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], height: 1.5),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _createSurvey,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Kom i gang', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: DriftProTheme.primaryGreen,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSurveyCard(Survey survey, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!),
      ),
      color: isDark ? DriftProTheme.cardDark : Colors.white,
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: survey.isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      survey.isActive ? 'AKTIV' : 'INAKTIV',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: survey.isActive ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.bar_chart_rounded, color: DriftProTheme.primaryGreen, size: 22),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SurveyResultsScreen(survey: survey),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 22, color: Colors.redAccent),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Slett undersøkelse?'),
                          content: Text('Er du sikker på at du vil slette "${survey.title}"? Dette kan ikke angres.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              child: const Text('Slett', style: TextStyle(color: Colors.white)),
                            ),
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
              const SizedBox(height: 16),
              Text(
                survey.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (survey.description != null && survey.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  survey.description!,
                  style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildStat(Icons.people_alt_outlined, '${survey.totalResponses} svar'),
                  const SizedBox(width: 24),
                  _buildStat(Icons.event_outlined, '${survey.createdAt.day}.${survey.createdAt.month}.${survey.createdAt.year}'),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
