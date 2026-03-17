import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../models/survey/survey.dart';
import '../../core/services/supabase_service.dart';
import '../../models/user_profile.dart';

class SurveyPublishView extends StatelessWidget {
  final Survey survey;
  const SurveyPublishView({super.key, required this.survey});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final publicLink = 'https://driftpro.no/s/${survey.id}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Publiser & Del',
                style: DriftProTheme.headingLg,
              ),
              const SizedBox(height: 8),
              Text(
                'DelDenne undersøkelsen er ${survey.isActive ? "åpen og klar for svar" : "lukket"}.',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 48),

              // Link Card
              Container(
                decoration: BoxDecoration(
                  color: isDark ? DriftProTheme.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.05), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                  border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!),
                ),
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: DriftProTheme.primaryGreen.withOpacity(0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.public, color: DriftProTheme.primaryGreen, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Offentlig lenke', style: DriftProTheme.headingMd),
                              const SizedBox(height: 4),
                              const Text('Del denne lenken med hvem som helst. Krever ikke innlogging.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: survey.isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20)
                          ),
                          child: Text(survey.isActive ? 'Aktiv' : 'Lukket', style: TextStyle(color: survey.isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(publicLink, style: const TextStyle(fontSize: 15, color: Colors.blue)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: 'Kopier lenke',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: publicLink));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offentlig lenke kopiert!')));
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatItem(Icons.analytics_outlined, '${survey.totalResponses}', 'Totalt antall svar', isDark),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatItem(Icons.calendar_today_outlined, '${survey.createdAt.day}/${survey.createdAt.month}/${survey.createdAt.year}', 'Opprettet dato', isDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => _showInternalShareSheet(context),
                        icon: const Icon(Icons.people),
                        label: const Text('Del direkte med ansatte', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DriftProTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: isDark ? Colors.white10 : Colors.grey[200]!), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey, size: 20),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  void _showInternalShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InternalShareSheet(survey: survey),
    );
  }
}

class _InternalShareSheet extends StatefulWidget {
  final Survey survey;
  const _InternalShareSheet({required this.survey});
  @override
  State<_InternalShareSheet> createState() => _InternalShareSheetState();
}

class _InternalShareSheetState extends State<_InternalShareSheet> {
  List<UserProfile> _allUsers = [];
  bool _isLoading = true;
  final Set<String> _selectedUsers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final companyId = await SupabaseService.getCurrentCompanyId();
    if (companyId != null) {
      final users = await SupabaseService.fetchProfiles(companyId: companyId);
      if (mounted) {
        setState(() {
          _allUsers = users;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DriftProTheme.cardDark : Colors.white, 
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24))
      ),
      padding: const EdgeInsets.all(24),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Del med ansatte', style: DriftProTheme.headingMd),
          const SizedBox(height: 8),
          const Text('Velg hvilke ansatte du vil sende direkte lenke til.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : ListView.builder(
                    itemCount: _allUsers.length,
                    itemBuilder: (context, index) {
                      final user = _allUsers[index];
                      return CheckboxListTile(
                        title: Text(user.fullName),
                        subtitle: Text(user.role.name, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        value: _selectedUsers.contains(user.id),
                        activeColor: DriftProTheme.primaryGreen,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) _selectedUsers.add(user.id);
                            else _selectedUsers.remove(user.id);
                          });
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _selectedUsers.isEmpty ? null : () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sendt til ${_selectedUsers.length} ansatte!'))
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: DriftProTheme.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Send Invitasjon', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}
